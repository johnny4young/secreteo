import Darwin
import Foundation
import notify

/// Fixed by the spec. Only tests shorten them.
public struct OwnershipTimings: Sendable {
    public static let standard = OwnershipTimings(
        changeDeadline: .seconds(10), capturePoll: .milliseconds(10), armRetry: .milliseconds(50))

    public var changeDeadline: Duration
    public var capturePoll: Duration
    public var armRetry: Duration

    public init(changeDeadline: Duration, capturePoll: Duration, armRetry: Duration) {
        self.changeDeadline = changeDeadline
        self.capturePoll = capturePoll
        self.armRetry = armRetry
    }
}

public protocol OwnershipTriggers: Sendable {
    /// Returns false if a trigger cannot be armed yet. May be called again.
    func arm() async -> Bool
    func disarm() async
}

public enum HandoffOutcome: Equatable, Sendable {
    case completed(generation: Int)
    case alreadyOwner
    case notConfirmed
    case notAvailable(ParticipantState)
    /// Another participant's intent is live.
    case busy
    /// Something still held the capture lock. `flock` does not reveal what, so no app is named.
    case timedOut
    case triggerConflict
    case targetNotReady
    case superseded
    case ioError
}

public enum OwnershipChange: Equatable, Sendable {
    case changed(generation: Int)
    /// The condition for the change no longer holds, so nothing was written.
    case noChange
    case busy
    case failed
}

/// How a holder treats its session once it sees a live intent.
public enum SessionPhase: Equatable, Sendable {
    case preparing
    case listening
    /// Transcribing, polishing, delivering or restoring the pasteboard.
    case microphoneClosed
    case practice

    public static let listeningGrace: TimeInterval = 5

    public func shouldCancel(secondsSinceIntentSeen elapsed: TimeInterval) -> Bool {
        switch self {
        case .preparing, .practice: true
        case .listening: elapsed >= Self.listeningGrace
        case .microphoneClosed: false
        }
    }
}

extension DictationOwnership {
    private enum HandoffStep: Error {
        case failed(HandoffOutcome)
    }

    public var isDevelopment: Bool { participant.hasSuffix(".dev") }

    /// The handoff in the spec, with this participant as the target.
    public func takeOwnership(userConfirmed: Bool, triggers: some OwnershipTriggers) async -> HandoffOutcome {
        guard userConfirmed else { return .notConfirmed }
        if case .success(let state) = files.read(), state.owner == participant { return .alreadyOwner }
        let current = status()
        guard current == .available else { return .notAvailable(current) }

        let intent: OwnershipIntent
        let generation: Int
        switch publishIntent() {
        case .success(let published): (intent, generation) = published
        case .failure(.failed(let outcome)): return outcome
        }
        postChange()

        let deadline = ContinuousClock.now.advanced(by: timings.changeDeadline)
        var capture: HeldLock?
        do {
            let lock = try await pollCapture(until: deadline)
            capture = lock
            try await arm(triggers, until: deadline)
            let committed = try commit(intent: intent, generation: generation)
            postChange()
            lock.release()
            return .completed(generation: committed)
        } catch {
            await triggers.disarm()
            capture?.release()
            clear(intent)
            postChange()
            if case HandoffStep.failed(let outcome) = error { return outcome }
            return .ioError
        }
    }

    /// Turning on with no owner is itself the user's request.
    public func preferenceTurnedOn(triggers: some OwnershipTriggers) async -> HandoffOutcome {
        guard case .success(let state) = files.read() else { return .ioError }
        guard state.owner == nil else { return .notAvailable(status()) }
        return await takeOwnership(userConfirmed: true, triggers: triggers)
    }

    /// Call after cancelling this app's own session. Changes nothing if it is no longer the owner.
    public func turnOff() async -> OwnershipChange {
        await relinquish { !self.conditions().preferenceIsOn }
    }

    /// For the version that removes dictation, whose preference may still be on.
    public func relinquishForRemoval() async -> OwnershipChange {
        await relinquish { true }
    }

    public func resetCorruptState() async -> OwnershipChange {
        await changeHoldingBothLocks { result in
            guard case .failure(.corruptState) = result else { return nil }
            return OwnershipState(owner: nil, generation: 1, previous: nil, intent: nil)
        }
    }

    /// Only for an app with existing users. Never waits for capture, so call it again on reevaluation.
    public func claimAtFirstRun() -> OwnershipChange {
        guard !isDevelopment, case .success = files.read(), !isSandboxedOrUnprepared else { return .noChange }
        switch files.tryLock(files.captureLock) {
        case .held(let capture):
            defer { capture.release() }
            return change(capture: capture) { result in
                guard case .success(let state) = result, state.generation == 0,
                      state.intent?.isLive(at: self.now()) != true,
                      self.conditions().preferenceIsOn else { return nil }
                return OwnershipState(owner: self.participant, generation: 1, previous: nil, intent: nil)
            }
        case .busy: return .busy
        case .failed: return .failed
        }
    }

    func postChange() {
        notify_post(changeNotificationName)
    }

    private func relinquish(when condition: @escaping @Sendable () -> Bool) async -> OwnershipChange {
        await changeHoldingBothLocks { result in
            guard case .success(let state) = result, state.owner == self.participant, condition() else { return nil }
            return OwnershipState(
                owner: nil, generation: state.generation + 1, previous: self.participant, intent: state.intent)
        }
    }

    private func changeHoldingBothLocks(
        _ next: @escaping @Sendable (Result<OwnershipState, UnavailableReason>) -> OwnershipState?
    ) async -> OwnershipChange {
        let deadline = ContinuousClock.now.advanced(by: timings.changeDeadline)
        guard let capture = try? await pollCapture(until: deadline) else { return .busy }
        defer { capture.release() }
        return change(capture: capture, next)
    }

    private func change(
        capture: HeldLock,
        _ next: (Result<OwnershipState, UnavailableReason>) -> OwnershipState?
    ) -> OwnershipChange {
        guard let stateLock = lockState() else { return .failed }
        defer { stateLock.release() }
        guard let state = next(files.read()) else { return .noChange }
        guard files.write(state) else { return .failed }
        postChange()
        return .changed(generation: state.generation)
    }

    private func publishIntent() -> Result<(OwnershipIntent, Int), HandoffStep> {
        guard let stateLock = lockState() else { return .failure(.failed(.ioError)) }
        defer { stateLock.release() }
        guard case .success(var state) = files.read() else { return .failure(.failed(.ioError)) }
        let time = now()
        if state.intent?.isLive(at: time) == true { return .failure(.failed(.busy)) }
        if state.owner == participant { return .failure(.failed(.alreadyOwner)) }
        let intent = OwnershipIntent(from: state.owner, to: participant, now: time)
        state.intent = intent
        guard files.write(state) else { return .failure(.failed(.ioError)) }
        return .success((intent, state.generation))
    }

    private func pollCapture(until deadline: ContinuousClock.Instant) async throws -> HeldLock {
        while true {
            switch files.tryLock(files.captureLock) {
            case .held(let lock): return lock
            case .failed: throw HandoffStep.failed(.ioError)
            case .busy: break
            }
            guard ContinuousClock.now < deadline else { throw HandoffStep.failed(.timedOut) }
            try await Task.sleep(for: timings.capturePoll)
        }
    }

    private func arm(_ triggers: some OwnershipTriggers, until deadline: ContinuousClock.Instant) async throws {
        while true {
            guard isStillEligible else { throw HandoffStep.failed(.targetNotReady) }
            if await triggers.arm() { return }
            guard ContinuousClock.now < deadline else { throw HandoffStep.failed(.triggerConflict) }
            try await Task.sleep(for: timings.armRetry)
        }
    }

    /// The rename inside `write` is the commit point of the whole handoff.
    private func commit(intent: OwnershipIntent, generation: Int) throws -> Int {
        guard isStillEligible else { throw HandoffStep.failed(.targetNotReady) }
        guard let stateLock = lockState() else { throw HandoffStep.failed(.ioError) }
        defer { stateLock.release() }
        guard case .success(let state) = files.read() else { throw HandoffStep.failed(.ioError) }
        guard state.intent?.id == intent.id, intent.isLive(at: now()), state.generation == generation else {
            throw HandoffStep.failed(.superseded)
        }
        let next = OwnershipState(owner: participant, generation: generation + 1, previous: state.owner, intent: nil)
        guard files.write(next) else { throw HandoffStep.failed(.ioError) }
        return next.generation
    }

    /// Best effort. If this cannot write, the intent simply expires.
    private func clear(_ intent: OwnershipIntent) {
        guard let stateLock = lockState() else { return }
        defer { stateLock.release() }
        guard case .success(var state) = files.read(), state.intent?.id == intent.id else { return }
        state.intent = nil
        _ = files.write(state)
    }

    private var isStillEligible: Bool {
        let current = conditions()
        return current.preferenceIsOn && current.missingForReadiness == nil && !current.legacyPeerIsActive
    }

    private var isSandboxedOrUnprepared: Bool {
        if case .unavailable = status() { return true }
        return false
    }

    /// Polled for at most a second, and never held across a wait.
    private func lockState() -> HeldLock? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while true {
            switch files.tryLock(files.stateLock) {
            case .held(let lock): return lock
            case .failed: return nil
            case .busy: break
            }
            guard ContinuousClock.now < deadline else { return nil }
            usleep(1_000)
        }
    }
}
