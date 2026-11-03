import Darwin
import Foundation
import notify

/// Re-derives the state on every hint, and on its own timer where a hint might not come.
public actor OwnershipObserver {
    public struct Snapshot: Equatable, Sendable {
        public let state: ParticipantState
        /// The live intent, for a holder to act on.
        public let intent: OwnershipIntent?
    }

    private static let holderInterval: TimeInterval = 1

    private let ownership: DictationOwnership
    private let onChange: @Sendable (Snapshot) -> Void
    private var isHoldingLease = false
    private var last: Snapshot?
    private var timer: Task<Void, Never>?
    private var token: Int32?

    public init(ownership: DictationOwnership, onChange: @escaping @Sendable (Snapshot) -> Void) {
        self.ownership = ownership
        self.onChange = onChange
    }

    public func start() {
        var registered: Int32 = 0
        let name = ownership.changeNotificationName
        let status = notify_register_dispatch(name, &registered, .global()) { [weak self] _ in
            guard let self else { return }
            Task { await self.reevaluate() }
        }
        if status == NOTIFY_STATUS_OK { token = registered }
        reevaluate()
    }

    public func stop() {
        if let token { notify_cancel(token) }
        token = nil
        timer?.cancel()
        timer = nil
    }

    /// A holder re-reads every second, so a missed notification cannot hide an intent.
    public func setHoldingLease(_ holding: Bool) {
        isHoldingLease = holding
        reevaluate()
    }

    /// Also call this on activation, wake, and any change of the preference or readiness.
    public func reevaluate() {
        let time = ownership.now()
        let intent: OwnershipIntent?
        if case .success(let state) = ownership.files.read(), let live = state.intent, live.isLive(at: time) {
            intent = live
        } else {
            intent = nil
        }
        let snapshot = Snapshot(state: ownership.status(), intent: intent)
        if snapshot != last {
            last = snapshot
            onChange(snapshot)
        }
        schedule(after: nextCheck(intent: intent, now: time))
    }

    private func nextCheck(intent: OwnershipIntent?, now: Date) -> TimeInterval? {
        let untilExpiry = intent.map { $0.expiresAt.timeIntervalSince(now) }
        let holder = isHoldingLease ? Self.holderInterval : nil
        return [untilExpiry, holder].compactMap { $0 }.min()
    }

    // The continuous clock counts sleep, so a timer that came due asleep fires on wake.
    private func schedule(after interval: TimeInterval?) {
        timer?.cancel()
        timer = nil
        guard let interval else { return }
        timer = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(interval, 0.01)), clock: .continuous)
            } catch {
                return
            }
            await self?.reevaluate()
        }
    }
}
