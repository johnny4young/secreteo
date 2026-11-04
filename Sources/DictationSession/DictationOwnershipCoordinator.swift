import AppKit
import DictationOwnership
import Foundation
import Observation

/// Secreteo's side of the cooperative ownership protocol: at most one global capture
/// or delivery per macOS user, across this app, Portavoz and their Dev builds.
/// It is not a security boundary, and it never writes the user's preference.
@MainActor
@Observable
final class DictationOwnershipCoordinator {
    private(set) var state = ParticipantState.off
    @ObservationIgnored var onStateChange: (_ previous: ParticipantState) -> Void = { _ in }
    @ObservationIgnored var onIntentChange: (_ isLive: Bool) -> Void = { _ in }

    @ObservationIgnored private let ownership: DictationOwnership
    @ObservationIgnored private let settle: () async -> Void
    @ObservationIgnored private var observer: OwnershipObserver?
    @ObservationIgnored private var held: SharedLease?
    @ObservationIgnored private var workspaceObservers: [any NSObjectProtocol] = []
    /// Step 5 of a handoff arms the triggers just before this app becomes the owner.
    @ObservationIgnored private var armsForHandoff = false
    @ObservationIgnored private var hasStarted = false
    /// Takes the capture lock even to change nothing, so it runs only while it can still matter:
    /// another app's key press must not meet a lock this app took just to look.
    @ObservationIgnored private var turnOffIsPending = true

    @ObservationIgnored private let turnOffRetry: Duration

    init(ownership: DictationOwnership, turnOffRetry: Duration = .seconds(5), settle: @escaping () async -> Void) {
        self.ownership = ownership
        self.turnOffRetry = turnOffRetry
        self.settle = settle
    }

    private static let shippedIdentifiers = ["com.johnny4young.secreteo", "com.johnny4young.secreteo.dev"]

    /// Only a shipped build with a real library touches the real owner. Disposable
    /// launches and test hosts get a scratch folder and notification of their own.
    static func usesRealOwner(identifier: String, usesTemporaryStore: Bool) -> Bool {
        !usesTemporaryStore && shippedIdentifiers.contains(identifier)
    }

    /// - Parameter missingForReadiness: names what is missing (microphone, Accessibility, engine),
    ///   or nil when ready. Ownership is offered and held only while this is nil.
    static func live(
        defaults: UserDefaults, usesTemporaryStore: Bool, missingForReadiness: @escaping @Sendable () -> String?
    ) -> DictationOwnershipCoordinator {
        let participant = Bundle.main.bundleIdentifier ?? "com.johnny4young.secreteo.unbundled"
        let isReal = usesRealOwner(identifier: participant, usesTemporaryStore: usesTemporaryStore)
        let peers = isReal ? legacyPeers() : nil
        // UserDefaults is thread-safe, and the protocol reads conditions off the main actor.
        nonisolated(unsafe) let preferences = defaults
        let preferenceKey = DictationController.defaultsKey
        let conditions: @Sendable () -> ParticipantConditions = {
            ParticipantConditions(
                preferenceIsOn: preferences.bool(forKey: preferenceKey),
                missingForReadiness: missingForReadiness(),
                legacyPeerIsActive: peers?.activePeer() != nil)
        }
        let scratch = UUID().uuidString
        let ownership = isReal
            ? DictationOwnership(participant: participant, conditions: conditions)
            : DictationOwnership(
                participant: participant,
                root: FileManager.default.temporaryDirectory
                    .appendingPathComponent("dictation-ownership-\(scratch)", isDirectory: true),
                conditions: conditions,
                notificationName: "com.johnny4young.secreteo.dictation-ownership.scratch.\(scratch)")
        return DictationOwnershipCoordinator(ownership: ownership) {
            _ = await DictationClipboard.shared.waitForRestoration(on: .general)
        }
    }

    /// Every Secreteo build has the protocol, so only the other app can be a legacy peer.
    private static func legacyPeers() -> NonCooperatingPeers {
        NonCooperatingPeers(
            known: KnownDictationPeers.all,
            running: {
                NSWorkspace.shared.runningApplications.compactMap { app in
                    app.bundleIdentifier.map { RunningApp(identifier: $0, bundleURL: app.bundleURL) }
                }
            })
    }

    /// For a disposable launch only, which has its own root and no user to take ownership.
    func claimScratchOwnership() {
        _ = ownership.claimAtFirstRun()
    }

    var admission: DictationAdmission {
        DictationAdmission(
            acquire: { [weak self] kind in self?.acquire(kind) ?? .failure(.dictationOff) },
            isEligible: { [weak self] in self?.state.allowsPrewarm ?? false })
    }

    var armsTriggers: Bool { state.armsTriggers || armsForHandoff }
    /// Watching continues until the last release, whoever released first.
    var holdsLease: Bool { held != nil }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        publish(ownership.status())
        turnOffIfPending()
        let observer = OwnershipObserver(ownership: ownership) { [weak self] snapshot in
            Task { @MainActor [weak self] in self?.apply(snapshot) }
        }
        self.observer = observer
        Task { await observer.start() }
        // Nothing else re-reads while idle, and a legacy peer quitting frees this app.
        workspaceObservers = [
            NSWorkspace.didWakeNotification, NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ].map { name in
            let center = NSWorkspace.shared.notificationCenter
            return center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reevaluate() }
            }
        }
    }

    /// A hint, as is activation or wake: the state is read again and nothing is decided from it.
    func reevaluate() {
        guard hasStarted else { return }
        publish(ownership.status())
        turnOffIfPending()
        Task { [observer] in await observer?.reevaluate() }
    }

    private func turnOffIfPending() {
        guard turnOffIsPending, state == .off else { return }
        turnOffIsPending = false
        Task { [ownership, turnOffRetry] in
            let change = await ownership.turnOff()
            guard change == .busy || change == .failed else { return }
            turnOffIsPending = true
            // The holder's release changes no state, so no other event may come to retry this.
            try? await Task.sleep(for: turnOffRetry)
            turnOffIfPending()
        }
    }

    /// The user's own action in Settings or onboarding. The result says why turning on
    /// did not make this app the owner; nil when turning off.
    @discardableResult
    func preferenceChanged(
        isOn: Bool, arm: @escaping @MainActor () -> Bool, disarm: @escaping @MainActor () -> Void
    ) async -> HandoffOutcome? {
        var outcome: HandoffOutcome?
        if isOn {
            outcome = await ownership.preferenceTurnedOn(triggers: handoffTriggers(arm: arm, disarm: disarm))
        } else {
            let change = await ownership.turnOff()
            turnOffIsPending = change == .busy || change == .failed
        }
        await settleAfterChange()
        return outcome
    }

    /// The user's choice to take dictation from another owner, offered only in `available`.
    func takeOwnership(
        arm: @escaping @MainActor () -> Bool, disarm: @escaping @MainActor () -> Void
    ) async -> HandoffOutcome {
        let outcome = await ownership.takeOwnership(
            userConfirmed: true, triggers: handoffTriggers(arm: arm, disarm: disarm))
        await settleAfterChange()
        return outcome
    }

    private func handoffTriggers(
        arm: @escaping @MainActor () -> Bool, disarm: @escaping @MainActor () -> Void
    ) -> HandoffTriggers {
        HandoffTriggers(
            arm: { [weak self] in
                self?.armsForHandoff = true
                return arm()
            },
            disarm: { [weak self] in
                self?.armsForHandoff = false
                disarm()
            })
    }

    private func settleAfterChange() async {
        armsForHandoff = false
        publish(ownership.status())
        turnOffIfPending()
        await observer?.reevaluate()
    }

    private func acquire(_ kind: DictationAdmissionKind) -> Result<DictationLease, DictationAdmissionRefusal> {
        if let held {
            // A new session shares the lease only while the last one waits for the clipboard,
            // and repeats admission on the held lock, so sessions in a row cannot hold off a handoff.
            // This actor is what keeps a join and the last release from interleaving.
            guard kind == .global, held.lease.kind == .global, held.working == 0 else { return .failure(.busy) }
            let current = ownership.status()
            guard current == .owned else { return .failure(refusal(for: current)) }
            guard held.lease.revalidate() else { return .failure(.unavailable(.ioError)) }
            held.holders += 1
            held.working += 1
            return .success(lease(sharing: held))
        }
        switch ownership.acquire(kind == .global ? .global : .practice) {
        case .refused(let refusal):
            return .failure(Self.refusal(for: refusal))
        case .admitted(let lease):
            let shared = SharedLease(lease: lease)
            held = shared
            reportHolding()
            return .success(self.lease(sharing: shared))
        }
    }

    private func lease(sharing shared: SharedLease) -> DictationLease {
        DictationLease(
            generation: shared.lease.generation,
            revalidate: { shared.lease.revalidate() },
            settle: settle,
            finishWork: { shared.working -= 1 },
            end: { [weak self] in
                shared.holders -= 1
                guard shared.holders == 0 else { return }
                shared.lease.release()
                guard let self, self.held === shared else { return }
                self.held = nil
                self.reportHolding()
            })
    }

    /// Reads the value when it runs, because these tasks can overtake each other.
    private func reportHolding() {
        Task { [weak self] in
            guard let self else { return }
            await observer?.setHoldingLease(holdsLease)
        }
    }

    private func apply(_ snapshot: OwnershipObserver.Snapshot) {
        onIntentChange(snapshot.intent != nil)
        publish(snapshot.state)
    }

    private func publish(_ new: ParticipantState) {
        let previous = state
        guard new != previous else { return }
        state = new
        onStateChange(previous)
    }

    private func refusal(for state: ParticipantState) -> DictationAdmissionRefusal {
        switch state {
        case .off: .dictationOff
        case .transferring: .transferring
        case .available, .preparing: .notOwner
        case .unavailable(let reason): .unavailable(reason)
        case .owned: .busy
        }
    }

    private static func refusal(for refusal: AdmissionRefusal) -> DictationAdmissionRefusal {
        switch refusal {
        case .busy: .busy
        case .transferring: .transferring
        case .notOwner: .notOwner
        case .off: .dictationOff
        case .unavailable(let reason): .unavailable(reason)
        }
    }
}

/// One capture lock shared by this process's sessions. It is unlocked only after the last
/// one ends, because unlocking frees it for everyone sharing the descriptor.
@MainActor
private final class SharedLease {
    let lease: OwnershipLease
    var holders = 1
    /// Sessions still capturing, transcribing or delivering.
    var working = 1

    init(lease: OwnershipLease) {
        self.lease = lease
    }
}

private struct HandoffTriggers: OwnershipTriggers {
    let arm: @MainActor @Sendable () -> Bool
    let disarm: @MainActor @Sendable () -> Void

    func arm() async -> Bool { await arm() }
    func disarm() async { await disarm() }
}
