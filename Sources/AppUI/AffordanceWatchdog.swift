import Foundation

/// An agent with microphone and Accessibility access must never run without a visible
/// icon. `tick` reports the loss once, and the owner cancels any session and quits.
@MainActor
public final class AffordanceWatchdog {
    private let hasAffordance: () -> Bool
    private let onLost: () -> Void
    private var timer: Timer?
    private var didReport = false

    public init(hasAffordance: @escaping () -> Bool, onLost: @escaping () -> Void) {
        self.hasAffordance = hasAffordance
        self.onLost = onLost
    }

    public func start(interval: TimeInterval = 0.75) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func tick() {
        guard !didReport, !hasAffordance() else { return }
        didReport = true
        timer?.invalidate()
        onLost()
    }
}
