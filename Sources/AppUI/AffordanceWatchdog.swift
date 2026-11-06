import AppKit

/// An agent with microphone and Accessibility access must never run without a visible
/// icon. `tick` reports the loss once, and the owner cancels any session and quits. It
/// waits for a few misses in a row, because a display change recreates the menu bar.
/// Launch, a miss, or any event that can take the icon away puts it on the fast schedule
/// for a few checks. Otherwise a slow timer covers a loss that nothing announced.
@MainActor
public final class AffordanceWatchdog {
    private let hasAffordance: () -> Bool
    private let onLost: () -> Void
    private let idleInterval: TimeInterval
    private let checkInterval: TimeInterval
    private var timer: Timer?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    private var didReport = false
    private var consecutiveMisses = 0
    private var fastChecksLeft = 0
    private let missesBeforeLoss = 3

    public init(
        hasAffordance: @escaping () -> Bool,
        onLost: @escaping () -> Void,
        idleInterval: TimeInterval = 5,
        checkInterval: TimeInterval = 0.75
    ) {
        self.hasAffordance = hasAffordance
        self.onLost = onLost
        self.idleInterval = idleInterval
        self.checkInterval = checkInterval
    }

    /// The wait before the next check, or nil once the loss is reported.
    var nextInterval: TimeInterval? {
        guard !didReport else { return nil }
        return consecutiveMisses > 0 || fastChecksLeft > 0 ? checkInterval : idleInterval
    }

    var nextCheck: Date? { timer?.fireDate }

    public func start() {
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let events = [
            (app, NSApplication.didChangeScreenParametersNotification),
            (app, NSWindow.didChangeOcclusionStateNotification),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
            (workspace, NSWorkspace.screensDidWakeNotification)
        ]
        for (center, name) in events {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkSoon() }
            }
            observers.append((center, observer))
        }
        fastChecksLeft = missesBeforeLoss
        schedule(firstIn: checkInterval)
    }

    /// A burst of events never brings checks closer together, so a menu bar being rebuilt
    /// still gets the full grace.
    public func checkSoon() {
        guard !didReport else { return }
        let wasIdle = nextInterval == idleInterval
        fastChecksLeft = missesBeforeLoss
        if timer != nil, wasIdle { schedule(firstIn: checkInterval) }
    }

    public func tick() {
        guard !didReport else { return }
        let interval = nextInterval
        if hasAffordance() {
            consecutiveMisses = 0
            fastChecksLeft = max(0, fastChecksLeft - 1)
        } else {
            consecutiveMisses += 1
            if consecutiveMisses >= missesBeforeLoss {
                report()
                return
            }
        }
        if timer != nil, let next = nextInterval, next != interval { schedule(firstIn: next) }
    }

    private func schedule(firstIn delay: TimeInterval) {
        guard let interval = nextInterval else { return }
        timer?.invalidate()
        let timer = Timer(fire: Date(timeIntervalSinceNow: delay), interval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval / 10
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func report() {
        didReport = true
        stop()
        onLost()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
    }
}
