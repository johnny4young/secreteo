import AppKit
import Carbon.HIToolbox

/// The configured push-to-talk mouse button as stored settings. Button
/// numbers follow `CGEvent`: 0 = left, 1 = right, 2 = middle, 3+ = extra
/// buttons. In vendor-facing labels those are Button 1, Button 2, Button 3,
/// and Button 4+. Middle click and additional buttons are eligible; left and
/// right can never become a PTT trigger.
struct MouseButtonSetting {
    static let buttonKey = "dictationMouseButton"
    /// Sentinel for "no mouse PTT configured" (also the left button's
    /// number, which is never eligible — the two can share safely).
    static let off = 0

    static func isEligible(_ button: Int) -> Bool { button >= 2 }

    static func load(from defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: buttonKey)
        return isEligible(stored) ? stored : off
    }

    static func save(_ button: Int, to defaults: UserDefaults = .standard) {
        defaults.set(isEligible(button) ? button : off, forKey: buttonKey)
    }

    /// Human ordinal: hardware button 2 reads "Button 3" like mouse vendors
    /// label it.
    static func label(for button: Int) -> String {
        L10n.format("Button %d", button + 1)
    }
}

/// A session event tap that turns one spare mouse button into a
/// push-to-talk trigger anywhere on the system. The tap CONSUMES the
/// configured button's press/release (the target app never sees the click)
/// and passes every other button through untouched. Requires the same
/// Accessibility trust the paste path already asks for; `init` fails
/// without it and the caller stays keyboard-only.
@MainActor
final class MouseButtonPTT {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let button: Int64
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var hold = MousePTTHold()

    init?(
        button: Int,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        guard MouseButtonSetting.isEligible(button) else { return nil }
        self.button = Int64(button)
        self.onPress = onPress
        self.onRelease = onRelease

        let mask = (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let ptt = Unmanaged<MouseButtonPTT>.fromOpaque(userInfo)
                    .takeUnretainedValue()
                let button = event.getIntegerValueField(.mouseEventButtonNumber)
                // The source is attached to the main run loop, so the
                // callback always arrives on the main thread. Only Sendable
                // values cross into the isolation check — the CGEvent stays
                // out here.
                let consumed = MainActor.assumeIsolated {
                    ptt.handle(type: type, button: button)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer)
        else { return nil }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Returns whether the event was consumed — true means the click never
    /// reaches the app under the cursor.
    private func handle(type: CGEventType, button: Int64) -> Bool {
        // macOS disables a tap it considers slow; silently staying dead
        // would strand the user mid-dictation, so always re-arm.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if hold.tapLost() { onRelease() }
            return false
        }
        guard button == self.button else { return false }
        if type == .otherMouseDown {
            hold.press()
            onPress()
        } else {
            hold.release()
            onRelease()
        }
        return true
    }

    func invalidate() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.tap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    // No deinit cleanup for the same reason as GlobalHotkey: a nonisolated
    // deinit cannot touch main-actor state under Swift 6. The controller
    // owns exactly one instance and always calls `invalidate()` first.
}
