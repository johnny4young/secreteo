import AppKit
import Carbon.HIToolbox
import Synchronization

/// A modifier held on its own as push-to-talk. Holding Fn is the default.
enum ModifierKeySetting: String, CaseIterable, Sendable {
    case off
    case function
    case rightOption
    case rightCommand

    static let defaultsKey = "dictationModifierKey"
    static let standard = Self.function

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? standard
    }

    /// macOS's “Press 🌐 key to” choice; only “Do Nothing” (0) leaves the key to Secreteo alone.
    static func systemFnKeyIsFree(usage: Int?) -> Bool { usage == 0 }

    static func systemFnUsage() -> Int? {
        CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? Int
    }

    var keyCode: Int64? {
        switch self {
        case .off: nil
        case .function: Int64(kVK_Function)
        case .rightOption: Int64(kVK_RightOption)
        case .rightCommand: Int64(kVK_RightCommand)
        }
    }

    /// Device-dependent bits keep the right-hand key apart from its left twin.
    var flag: UInt64 {
        switch self {
        case .off: 0
        case .function: CGEventFlags.maskSecondaryFn.rawValue
        case .rightOption: 0x40
        case .rightCommand: 0x10
        }
    }

    /// Another modifier already held means a shortcut, not dictation.
    func holdsOtherModifier(_ flags: UInt64) -> Bool {
        let own: CGEventFlags = switch self {
        case .off: []
        case .function: .maskSecondaryFn
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        }
        let others = CGEventFlags([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
            .subtracting(own)
        return flags & others.rawValue != 0
    }
}

/// Pure hold logic. A press starts only after `startDelay` with nothing else
/// typed, so Fn+arrow or ⌥+letter shortcuts never open dictation.
struct ModifierKeyGesture {
    enum Input: Equatable {
        case down
        case up
        case otherKey
        case delayElapsed
    }

    enum Output: Equatable {
        case scheduleStart
        case press
        case release
        case chord
    }

    static let startDelay: DispatchTimeInterval = .milliseconds(200)

    /// Maps one tapped keyboard event to a gesture input.
    static func input(
        for type: CGEventType, keyCode: Int64, flags: UInt64, setting: ModifierKeySetting
    ) -> Input {
        guard type == .flagsChanged, keyCode == setting.keyCode else { return .otherKey }
        guard flags & setting.flag != 0 else { return .up }
        return setting.holdsOtherModifier(flags) ? .otherKey : .down
    }

    private enum State { case idle, pending, held, ignoredUntilUp }
    private var state = State.idle

    var isIdle: Bool { state == .idle }

    mutating func handle(_ input: Input) -> Output? {
        switch (state, input) {
        case (.idle, .down):
            state = .pending
            return .scheduleStart
        case (.pending, .delayElapsed):
            state = .held
            return .press
        case (.pending, .otherKey):
            state = .ignoredUntilUp
            return nil
        case (.held, .otherKey):
            state = .ignoredUntilUp
            return .chord
        case (.held, .up):
            state = .idle
            return .release
        case (_, .up):
            state = .idle
            return nil
        default:
            return nil
        }
    }
}

/// Thread-safe gesture router for the modifier event tap. Normal typing while
/// idle exits on a fast path without scheduling timers or touching the main actor.
final class ModifierKeyTapRouter: Sendable {
    private struct State {
        var gesture = ModifierKeyGesture()
        var delayGeneration: UInt64 = 0
        var invalidated = false
    }

    private let setting: ModifierKeySetting
    private let startDelay: DispatchTimeInterval
    private let timerQueue: DispatchQueue
    private let deliveryQueue: DispatchQueue
    private let state = Mutex(State())
    private let onPress: @Sendable () -> Void
    private let onRelease: @Sendable () -> Void
    private let onChord: @Sendable () -> Void

    init(
        setting: ModifierKeySetting,
        startDelay: DispatchTimeInterval = ModifierKeyGesture.startDelay,
        deliveryQueue: DispatchQueue = .main,
        onPress: @escaping @Sendable () -> Void,
        onRelease: @escaping @Sendable () -> Void,
        onChord: @escaping @Sendable () -> Void
    ) {
        self.setting = setting
        self.startDelay = startDelay
        timerQueue = DispatchQueue(label: "com.johnny4young.secreteo.modifier-ptt-timer", qos: .userInteractive)
        self.deliveryQueue = deliveryQueue
        self.onPress = onPress
        self.onRelease = onRelease
        self.onChord = onChord
    }

    /// Returns true when the tap reported being disabled and must be re-enabled.
    @discardableResult
    func handleEvent(type: CGEventType, keyCode: Int64, flags: UInt64) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Events may have been lost while disabled: end any hold rather than
            // let a pending start or a missed release keep dictation listening.
            apply(.up)
            return true
        }
        let scheduleGeneration: UInt64? = state.withLock { current in
            guard !current.invalidated else { return nil }
            if current.gesture.isIdle, type == .keyDown || (type == .flagsChanged && keyCode != setting.keyCode) {
                return nil
            }
            let input = ModifierKeyGesture.input(for: type, keyCode: keyCode, flags: flags, setting: setting)
            return applyLocked(&current, input: input)
        }
        if let generation = scheduleGeneration { scheduleDelay(generation: generation) }
        return false
    }

    func invalidate() {
        state.withLock { current in
            current.invalidated = true
            current.delayGeneration &+= 1
        }
    }

    private var isInvalidated: Bool {
        state.withLock { $0.invalidated }
    }

    private func apply(_ input: ModifierKeyGesture.Input) {
        let scheduleGeneration: UInt64? = state.withLock { current in
            guard !current.invalidated else { return nil }
            return applyLocked(&current, input: input)
        }
        if let generation = scheduleGeneration { scheduleDelay(generation: generation) }
    }

    /// Enqueues delivery while holding the state lock so cross-thread transitions
    /// (timer press vs tap release/chord) reach the receiver in strict FIFO order.
    private func applyLocked(_ current: inout State, input: ModifierKeyGesture.Input) -> UInt64? {
        switch current.gesture.handle(input) {
        case .scheduleStart:
            current.delayGeneration &+= 1
            return current.delayGeneration
        case .press:
            enqueue(onPress)
            return nil
        case .release:
            enqueue(onRelease)
            return nil
        case .chord:
            enqueue(onChord)
            return nil
        case nil:
            if input != .delayElapsed { current.delayGeneration &+= 1 }
            return nil
        }
    }

    private func enqueue(_ callback: @escaping @Sendable () -> Void) {
        deliveryQueue.async { [weak self] in
            guard let self, !self.isInvalidated else { return }
            callback()
        }
    }

    private func scheduleDelay(generation: UInt64) {
        timerQueue.asyncAfter(deadline: .now() + startDelay) { [weak self] in
            guard let self else { return }
            _ = self.state.withLock { current -> UInt64? in
                guard !current.invalidated, current.delayGeneration == generation else { return nil }
                return self.applyLocked(&current, input: .delayElapsed)
            }
        }
    }
}

/// Core Foundation handles handed once to the dedicated tap thread and stopped via
/// thread-safe `CGEvent.tapEnable` and `CFRunLoopStop`; released after `CFRunLoopRun` exits.
private final class ModifierTapHandles: @unchecked Sendable {
    let router: ModifierKeyTapRouter
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var stopped = false

    init(router: ModifierKeyTapRouter) {
        self.router = router
    }

    func install(tap: CFMachPort, source: CFRunLoopSource) {
        lock.lock()
        self.tap = tap
        self.source = source
        lock.unlock()
    }

    func reenableTap() {
        lock.lock()
        if !stopped, let activeTap = tap {
            CGEvent.tapEnable(tap: activeTap, enable: true)
        }
        lock.unlock()
    }

    func runOnCurrentThread(ready: DispatchSemaphore) {
        guard let runLoop = CFRunLoopGetCurrent() else {
            ready.signal()
            return
        }
        lock.lock()
        let activeTap = tap
        let activeSource = source
        let canStart = !stopped && activeTap != nil && activeSource != nil
        if canStart { self.runLoop = runLoop }
        lock.unlock()
        if canStart, let activeTap, let activeSource {
            CFRunLoopAddSource(runLoop, activeSource, .commonModes)
            CGEvent.tapEnable(tap: activeTap, enable: true)
            // Signal once CFRunLoopRun has entered its loop so stop() cannot miss it.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                ready.signal()
            }
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, activeSource, .commonModes)
        } else {
            ready.signal()
        }
        if let activeTap {
            CGEvent.tapEnable(tap: activeTap, enable: false)
            CFMachPortInvalidate(activeTap)
        }
        lock.lock()
        tap = nil
        source = nil
        self.runLoop = nil
        lock.unlock()
    }

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let activeTap = tap
        let loop = runLoop
        runLoop = nil
        lock.unlock()
        if let activeTap { CGEvent.tapEnable(tap: activeTap, enable: false) }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(loop)
            }
            CFRunLoopStop(loop)
            CFRunLoopWakeUp(loop)
        }
    }
}

/// Watches one modifier through a session event tap on a dedicated background
/// run loop so main-thread stalls never delay typing across macOS.
@MainActor
final class ModifierKeyPTT {
    private let router: ModifierKeyTapRouter
    private let handles: ModifierTapHandles

    init?(
        setting: ModifierKeySetting,
        onPress: @escaping @MainActor () -> Void,
        onRelease: @escaping @MainActor () -> Void,
        onChord: @escaping @MainActor () -> Void
    ) {
        guard setting.keyCode != nil else { return nil }
        let router = ModifierKeyTapRouter(
            setting: setting,
            deliveryQueue: .main,
            onPress: { MainActor.assumeIsolated { onPress() } },
            onRelease: { MainActor.assumeIsolated { onRelease() } },
            onChord: { MainActor.assumeIsolated { onChord() } })
        self.router = router
        let handles = ModifierTapHandles(router: router)

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let handlesPointer = Unmanaged.passUnretained(handles).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let handles = Unmanaged<ModifierTapHandles>.fromOpaque(userInfo).takeUnretainedValue()
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags.rawValue
                if handles.router.handleEvent(type: type, keyCode: keyCode, flags: flags) {
                    handles.reenableTap()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: handlesPointer),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        else { return nil }

        handles.install(tap: tap, source: source)
        self.handles = handles
        let ready = DispatchSemaphore(value: 0)
        // The thread closure retains handles until CFMachPortInvalidate finishes.
        let thread = Thread {
            handles.runOnCurrentThread(ready: ready)
        }
        thread.name = "com.johnny4young.secreteo.modifier-ptt"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func invalidate() {
        router.invalidate()
        handles.stop()
    }

    deinit {
        router.invalidate()
        handles.stop()
    }
}
