import Darwin
@testable import DictationOwnership
import Foundation
import Synchronization
import Testing

/// Records what the protocol asks of the triggers, with no real shortcut or event tap.
final class FakeTriggers: OwnershipTriggers {
    private let state = Mutex((armed: false, armCalls: 0, refusals: 0))

    init(refusals: Int = 0) {
        state.withLock { $0.refusals = refusals }
    }

    var armed: Bool { state.withLock { $0.armed } }
    var armCalls: Int { state.withLock { $0.armCalls } }

    func setArmed(_ armed: Bool) {
        state.withLock { $0.armed = armed }
    }

    func arm() async -> Bool {
        state.withLock { value in
            value.armCalls += 1
            guard value.refusals == 0 else {
                value.refusals -= 1
                return false
            }
            value.armed = true
            return true
        }
    }

    func disarm() async {
        state.withLock { $0.armed = false }
    }
}

// A wide deadline for handoffs that should complete, and a short one for those that should time out.
private let patient = OwnershipTimings(changeDeadline: .seconds(10), capturePoll: .milliseconds(2), armRetry: .milliseconds(5))
private let quick = OwnershipTimings(changeDeadline: .milliseconds(200), capturePoll: .milliseconds(2), armRetry: .milliseconds(5))

extension Scratch {
    /// Runs on the real clock, for the handoff paths that compare it with an intent.
    func live(_ id: String, timings: OwnershipTimings = patient) -> DictationOwnership {
        let conditions = conditions
        return DictationOwnership(
            participant: id,
            root: root,
            isSandboxed: false,
            conditions: { conditions.current },
            notificationName: notificationName,
            timings: timings)
    }

    var notificationName: String {
        "com.example.dictation-ownership-test.\(root.deletingLastPathComponent().lastPathComponent)"
    }

    var state: OwnershipState? { try? files.read().get() }
}

struct HandoffTests {
    @Test func aHandoffMovesOwnershipAndArmsOnlyTheTarget() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(ownerID, generation: 4)
        let triggers = FakeTriggers()
        let outcome = await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: triggers)
        #expect(outcome == .completed(generation: 5))
        #expect(triggers.armed)
        #expect(scratch.state == OwnershipState(owner: otherID, generation: 5, previous: ownerID, intent: nil))
        #expect(scratch.live(otherID).status() == .owned)
        #expect(scratch.live(ownerID).status() == .available)
        #expect(refusal(from: scratch.live(ownerID).acquire(.global)) == .notOwner(otherID))
    }

    @Test func noUserActionMeansNoChange() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let triggers = FakeTriggers()
        #expect(await scratch.live(otherID).takeOwnership(userConfirmed: false, triggers: triggers) == .notConfirmed)
        #expect(triggers.armCalls == 0)
        #expect(scratch.state?.owner == ownerID)
    }

    @Test func aHandoffToTheCurrentOwnerDoesNothing() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(generation: 2)
        #expect(await scratch.live(ownerID).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .alreadyOwner)
        #expect(scratch.state?.generation == 2)
    }

    @Test func aTargetThatIsNotAvailableIsRefusedBeforePublishing() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        scratch.conditions.current.missingForReadiness = "practice"
        let outcome = await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers())
        #expect(outcome == .notAvailable(.preparing))
        #expect(scratch.state?.intent == nil)
    }

    @Test func aLiveIntentFromAnotherTargetIsBusy() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let intent = OwnershipIntent(from: ownerID, to: "com.example.third", now: Date())
        try scratch.seed(OwnershipState(owner: ownerID, generation: 1, previous: nil, intent: intent))
        #expect(await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .busy)
        #expect(scratch.state?.intent?.id == intent.id)
    }

    @Test func aHolderThatFinishesInTimeLetsTheHandoffComplete() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let held = lease(from: scratch.live(ownerID).acquire(.global))
        let handoff = Task { await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) }
        try await waitUntil { scratch.state?.intent != nil }
        #expect(refusal(from: scratch.live(ownerID).acquire(.global)) == .busy)
        #expect(held?.revalidate() == true, "A session under way may still deliver")
        held?.release()
        #expect(await handoff.value == .completed(generation: 2))
    }

    @Test func bothSidesReportTransferringDuringAHandoff() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let holder = lease(from: scratch.live(ownerID).acquire(.practice))
        let handoff = Task { await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) }
        try await waitUntil { scratch.state?.intent != nil }
        #expect(scratch.live(ownerID).status() == .transferring)
        #expect(scratch.live(otherID).status() == .transferring)
        holder?.release()
        _ = await handoff.value
    }

    @Test func aWedgedHolderTimesOutAndNothingChanges() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(generation: 3)
        let before = scratch.state
        let held = lease(from: scratch.live(ownerID).acquire(.global))
        let triggers = FakeTriggers()
        let outcome = await scratch.live(otherID, timings: quick).takeOwnership(userConfirmed: true, triggers: triggers)
        #expect(outcome == .timedOut)
        #expect(scratch.state == before, "Owner and generation unchanged, intent cleared")
        #expect(!triggers.armed)
        #expect(held?.revalidate() == true, "The holder was not interrupted")
    }

    @Test func aTriggerThatCannotArmRollsBack() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let before = scratch.state
        let triggers = FakeTriggers(refusals: .max)
        let outcome = await scratch.live(otherID, timings: quick).takeOwnership(userConfirmed: true, triggers: triggers)
        #expect(outcome == .triggerConflict)
        #expect(triggers.armCalls > 1, "It retries until the deadline")
        #expect(scratch.state == before)
        #expect(lease(from: scratch.live(ownerID).acquire(.global)) != nil, "The lock is free again")
    }

    @Test func armingIsRetriedUntilThePriorOwnerLetsGo() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let outcome = await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers(refusals: 3))
        #expect(outcome == .completed(generation: 2))
    }

    @Test(arguments: [
        ParticipantConditions(preferenceIsOn: false, missingForReadiness: nil, legacyPeerIsActive: false),
        ParticipantConditions(preferenceIsOn: true, missingForReadiness: "microphone", legacyPeerIsActive: false),
        ParticipantConditions(preferenceIsOn: true, missingForReadiness: nil, legacyPeerIsActive: true)
    ])
    func aTargetThatStopsBeingEligibleNeverArms(change: ParticipantConditions) async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let held = lease(from: scratch.live(ownerID).acquire(.global))
        let triggers = FakeTriggers()
        let handoff = Task { await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: triggers) }
        try await waitUntil { scratch.state?.intent != nil }
        scratch.conditions.current = change
        held?.release()
        #expect(await handoff.value == .targetNotReady)
        #expect(triggers.armCalls == 0)
        #expect(scratch.state?.owner == ownerID)
        #expect(scratch.state?.intent == nil)
    }

    @Test func aPriorOwnerTurningOffDuringAHandoffSupersedesIt() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(generation: 3)
        let triggers = FakeArmingHook { _ = scratch.files.write(OwnershipState(owner: nil, generation: 4, previous: ownerID, intent: scratch.state?.intent)) }
        let outcome = await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: triggers)
        #expect(outcome == .superseded)
        #expect(scratch.state?.owner == nil)
        #expect(scratch.state?.intent == nil)
    }

    @Test func anIntentReplacedDuringAHandoffSupersedesIt() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let other = OwnershipIntent(from: ownerID, to: "com.example.third", now: Date())
        let triggers = FakeArmingHook { _ = scratch.files.write(OwnershipState(owner: ownerID, generation: 1, previous: nil, intent: other)) }
        let outcome = await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: triggers)
        #expect(outcome == .superseded)
        #expect(scratch.state?.intent?.id == other.id, "Rollback clears only its own intent")
    }

    @Test func aFailedWriteDuringRollbackStillDisarmsAndReleases() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let triggers = FakeArmingHook { chmod(scratch.root.path, 0o500) }
        defer { chmod(scratch.root.path, 0o700) }
        let outcome = await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: triggers)
        #expect(outcome == .ioError)
        #expect(!triggers.armed)
        #expect(scratch.state?.owner == ownerID)
        let stuck = try #require(scratch.state?.intent, "The intent could not be cleared, so it has to expire")
        scratch.conditions.now = stuck.expiresAt
        #expect(lease(from: scratch.participant().acquire(.global)) != nil, "The lock is free and the owner is admitted")
    }

    @Test func competingHandoffsNeverLoseAGeneration() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner("com.example.first")
        let targets = (0..<8).map { "com.example.target\($0)" }
        let outcomes = await withTaskGroup(of: HandoffOutcome.self) { group in
            for target in targets {
                group.addTask { await scratch.live(target).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let completed = outcomes.filter { if case .completed = $0 { true } else { false } }
        #expect(!completed.isEmpty)
        #expect(outcomes.allSatisfy { if case .completed = $0 { true } else { $0 == .busy || $0 == .superseded } })
        #expect(scratch.state?.generation == 1 + completed.count)
    }

    @Test func backToThePreviousOwnerIsANormalHandoff() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        #expect(await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .completed(generation: 2))
        #expect(await scratch.live(ownerID).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .completed(generation: 3))
        #expect(scratch.state == OwnershipState(owner: ownerID, generation: 3, previous: otherID, intent: nil))
    }

    @Test func aCrashedTargetsIntentExpiresAndNothingElseChanges() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let intent = OwnershipIntent(from: ownerID, to: otherID, now: scratch.conditions.now)
        let seeded = OwnershipState(owner: ownerID, generation: 1, previous: nil, intent: intent)
        try scratch.seed(seeded)
        let prior = scratch.participant()
        #expect(prior.status() == .transferring)
        #expect(refusal(from: prior.acquire(.global)) == .transferring)
        scratch.conditions.now = intent.expiresAt
        #expect(prior.status() == .owned)
        #expect(lease(from: prior.acquire(.global))?.owner == ownerID)
        #expect(scratch.state == seeded)
    }

    @Test func aTargetThatCrashedAfterTheCommitStaysOwner() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seed(OwnershipState(owner: otherID, generation: 2, previous: ownerID, intent: nil))
        #expect(scratch.participant().status() == .available)
        #expect(refusal(from: scratch.participant().acquire(.global)) == .notOwner(otherID))
    }

    @Test func sleepingPastAnIntentExpiresItWhileALeaseStaysExclusive() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let held = lease(from: scratch.participant().acquire(.global))
        let intent = OwnershipIntent(from: ownerID, to: otherID, now: scratch.conditions.now)
        try scratch.seed(OwnershipState(owner: ownerID, generation: 1, previous: nil, intent: intent))
        #expect(scratch.participant().status() == .transferring)
        scratch.conditions.now = scratch.conditions.now.addingTimeInterval(3_600)
        #expect(scratch.participant().status() == .owned)
        #expect(refusal(from: scratch.participant().acquire(.global)) == .busy)
        #expect(held?.revalidate() == true)
    }

    @Test func aCancelledOperationNeverCommitsEvenIfArmingSucceeds() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let before = scratch.state
        let triggers = GatedTriggers()
        let handoff = Task { await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: triggers) }
        try await waitUntil { triggers.isWaiting }
        handoff.cancel()
        triggers.open()
        #expect(await handoff.value == .cancelled)
        #expect(!triggers.armed)
        #expect(scratch.state == before)
    }

    @Test func anAlreadyCancelledOperationPublishesNothing() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let before = scratch.state
        let triggers = FakeTriggers()
        let handoff = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: triggers)
        }
        #expect(await handoff.value == .cancelled)
        #expect(triggers.armCalls == 0)
        #expect(scratch.state == before)
    }

    @Test func aParticipantRunsOneHandoffAtATimeThroughItsRollback() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let target = scratch.live(otherID)
        let triggers = GatedTriggers()
        let first = Task { await target.takeOwnership(userConfirmed: true, triggers: triggers) }
        try await waitUntil { triggers.isWaiting }
        #expect(await target.takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .busy)
        triggers.open()
        #expect(await first.value == .completed(generation: 2))
        #expect(await target.takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .alreadyOwner)
    }

    @Test func armingThatFinishesPastTheDeadlineRollsBack() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let before = scratch.state
        let triggers = GatedTriggers()
        let handoff = Task { await scratch.live(otherID, timings: quick).takeOwnership(userConfirmed: true, triggers: triggers) }
        try await waitUntil { triggers.isWaiting }
        try await Task.sleep(for: .milliseconds(300))
        triggers.open()
        #expect(await handoff.value == .triggerConflict)
        #expect(!triggers.armed)
        #expect(scratch.state == before)
    }

    @Test func losingEligibilityWhileArmingRollsBackAfterArming() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let conditions = scratch.conditions
        let triggers = FakeArmingHook { conditions.current.preferenceIsOn = false }
        let outcome = await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: triggers)
        #expect(outcome == .targetNotReady)
        #expect(!triggers.armed)
        #expect(scratch.state?.owner == ownerID)
    }

    @Test func anUnusableNotificationNameDoesNotUndoACommit() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let conditions = scratch.conditions
        let target = DictationOwnership(
            participant: otherID, root: scratch.root, isSandboxed: false,
            conditions: { conditions.current }, notificationName: "")
        let triggers = FakeTriggers()
        #expect(await target.takeOwnership(userConfirmed: true, triggers: triggers) == .completed(generation: 2))
        #expect(triggers.armed)
        #expect(lease(from: target.acquire(.global)) != nil, "The capture lock was released")
    }

    @Test func aTargetKilledWhileArmingLeavesTheOwnerAndAnIntentThatExpires() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let target = try scratch.client(
            "handoff-then-die", participant: otherID, extra: ["--die-at", "arm", "--notification", scratch.notificationName])
        await finish(target)
        #expect(target.terminationReason == .uncaughtSignal)
        let intent = try #require(scratch.state?.intent)
        #expect(scratch.state?.owner == ownerID)
        #expect(refusal(from: scratch.live(ownerID).acquire(.global)) == .transferring, "The lock is free, and the intent is live")
        scratch.conditions.now = intent.expiresAt
        #expect(lease(from: scratch.participant().acquire(.global)) != nil)
    }

    @Test func aTargetKilledAfterTheCommitStaysOwner() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let target = try scratch.client(
            "handoff-then-die", participant: otherID, extra: ["--die-at", "exit", "--notification", scratch.notificationName])
        await finish(target)
        #expect(target.terminationReason == .uncaughtSignal)
        #expect(scratch.state == OwnershipState(owner: otherID, generation: 2, previous: ownerID, intent: nil))
        #expect(refusal(from: scratch.live(ownerID).acquire(.global)) == .notOwner(otherID))
    }

    @Test func anUpgradeKeepsTheOwner() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(generation: 9)
        lease(from: scratch.participant().acquire(.global))?.release()
        let relaunched = scratch.participant()
        #expect(relaunched.status() == .owned)
        #expect(lease(from: relaunched.acquire(.global))?.generation == 9)
    }

    @Test func anUninstalledOwnerLeavesOthersAvailableAndTheFileAlone() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner("com.example.gone")
        let before = try Data(contentsOf: scratch.files.stateFile)
        #expect(scratch.participant(otherID).status() == .available)
        #expect(try Data(contentsOf: scratch.files.stateFile) == before)
    }

    @Test(arguments: [
        (SessionPhase.preparing, 0.0, true),
        (SessionPhase.practice, 0.0, true),
        (SessionPhase.listening, SessionPhase.listeningGrace - 1, false),
        (SessionPhase.listening, SessionPhase.listeningGrace, true),
        (SessionPhase.microphoneClosed, 1_000, false)
    ])
    func eachPhaseIsTreatedAsTheSpecSays(phase: SessionPhase, elapsed: TimeInterval, cancels: Bool) {
        #expect(phase.shouldCancel(secondsSinceIntentSeen: elapsed) == cancels)
    }
}

struct OtherChangeTests {
    @Test func turningOffInTheOwnerPublishesNobody() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(generation: 5)
        scratch.conditions.current.preferenceIsOn = false
        #expect(await scratch.live(ownerID).turnOff() == .changed(generation: 6))
        #expect(scratch.state == OwnershipState(owner: nil, generation: 6, previous: ownerID, intent: nil))
    }

    @Test func turningOffAfterLosingOwnershipChangesNothing() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(otherID, generation: 8)
        let before = try Data(contentsOf: scratch.files.stateFile)
        scratch.conditions.current.preferenceIsOn = false
        #expect(await scratch.live(ownerID).turnOff() == .noChange)
        #expect(try Data(contentsOf: scratch.files.stateFile) == before)
    }

    @Test func turningOffWithThePreferenceBackOnChangesNothing() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        #expect(await scratch.live(ownerID).turnOff() == .noChange)
        #expect(scratch.state?.owner == ownerID)
    }

    @Test func turningOffWhileSomethingHoldsTheLockReportsBusy() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        scratch.conditions.current.preferenceIsOn = false
        let held = lease(from: scratch.live(otherID).acquire(.practice))
        #expect(await scratch.live(ownerID, timings: quick).turnOff() == .busy)
        held?.release()
        #expect(await scratch.live(ownerID).turnOff() == .changed(generation: 2))
    }

    @Test func afterTurningOffNoOtherAppClaimsByItself() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        scratch.conditions.current.preferenceIsOn = false
        _ = await scratch.live(ownerID).turnOff()
        scratch.conditions.current.preferenceIsOn = true
        let other = scratch.live(otherID)
        #expect(other.status() == .available)
        #expect(other.claimAtFirstRun() == .noChange)
        #expect(scratch.state?.owner == nil)
    }

    @Test func turningOnWithNoOwnerRunsAHandoff() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let triggers = FakeTriggers()
        #expect(await scratch.live(ownerID).preferenceTurnedOn(triggers: triggers) == .completed(generation: 1))
        #expect(triggers.armed)
    }

    @Test func turningOnWithAnotherOwnerOnlyOffers() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(otherID)
        let outcome = await scratch.live(ownerID).preferenceTurnedOn(triggers: FakeTriggers())
        #expect(outcome == .notAvailable(.available))
        #expect(scratch.state?.owner == otherID)
    }

    @Test func turningOnDoesNotTakeOverAnOwnerThatAppearedMeanwhile() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let files = scratch.files
        // The state is read before the conditions, so this lands in between.
        let target = DictationOwnership(
            participant: ownerID, root: scratch.root, isSandboxed: false,
            conditions: {
                _ = files.write(OwnershipState(owner: otherID, generation: 1, previous: nil, intent: nil))
                return .ready
            },
            notificationName: scratch.notificationName)
        #expect(await target.preferenceTurnedOn(triggers: FakeTriggers()) == .notAvailable(.available))
        #expect(scratch.state?.owner == otherID)
    }

    @Test func turningOnWithACorruptFileReportsItsState() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try Data("{".utf8).write(to: scratch.files.stateFile)
        let outcome = await scratch.live(ownerID).preferenceTurnedOn(triggers: FakeTriggers())
        #expect(outcome == .notAvailable(.unavailable(.corruptState)))
    }

    @Test func aSandboxedProcessChangesAndCreatesNothing() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let garbage = Data("{".utf8)
        try garbage.write(to: scratch.files.stateFile)
        let target = DictationOwnership(participant: ownerID, root: scratch.root, isSandboxed: true, conditions: { .ready })
        #expect(await target.resetCorruptState() == .failed)
        #expect(await target.turnOff() == .failed)
        #expect(await target.relinquishForRemoval() == .failed)
        #expect(target.claimAtFirstRun() == .noChange)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path) == ["ownership.json"])
        #expect(try Data(contentsOf: scratch.files.stateFile) == garbage)
    }

    @Test func aLockFailureIsNotReportedAsBusy() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let target = scratch.root.appendingPathComponent("elsewhere")
        FileManager.default.createFile(atPath: target.path, contents: nil)
        try FileManager.default.createSymbolicLink(at: scratch.files.captureLock, withDestinationURL: target)
        scratch.conditions.current.preferenceIsOn = false
        #expect(await scratch.live(ownerID).turnOff() == .failed)
    }

    @Test func turningOnBeforeBeingReadyDoesNotPublish() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        scratch.conditions.current.missingForReadiness = "engine"
        let outcome = await scratch.live(ownerID).preferenceTurnedOn(triggers: FakeTriggers())
        #expect(outcome == .notAvailable(.preparing))
        #expect(scratch.state == .nobody)
    }

    @Test func removalRelinquishesEvenWithThePreferenceOn() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(generation: 2)
        #expect(await scratch.live(ownerID).relinquishForRemoval() == .changed(generation: 3))
        #expect(await scratch.live(ownerID).relinquishForRemoval() == .noChange)
    }

    @Test func resetRecoversACorruptFileOnlyOnce() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try Data("{".utf8).write(to: scratch.files.stateFile)
        #expect(await scratch.live(ownerID).resetCorruptState() == .changed(generation: 1))
        #expect(scratch.state == OwnershipState(owner: nil, generation: 1, previous: nil, intent: nil))
        #expect(await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .completed(generation: 2))
        #expect(await scratch.live(ownerID).resetCorruptState() == .noChange, "A late reset must not erase that claim")
        #expect(scratch.state?.owner == otherID)
    }

    @Test func aNewerFormatCannotBeReset() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let future = Data(#"{"version":2}"#.utf8)
        try future.write(to: scratch.files.stateFile)
        #expect(await scratch.live(ownerID).resetCorruptState() == .noChange)
        #expect(try Data(contentsOf: scratch.files.stateFile) == future)
    }
}

struct FirstRunTests {
    @Test func theFirstRunClaimLandsOnceWithNoStateFile() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        #expect(scratch.live(ownerID).claimAtFirstRun() == .changed(generation: 1))
        #expect(scratch.live(otherID).claimAtFirstRun() == .noChange)
        #expect(scratch.state?.owner == ownerID)
    }

    @Test func aDevBuildNeverClaims() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        #expect(scratch.live("\(ownerID).dev").claimAtFirstRun() == .noChange)
        #expect(!FileManager.default.fileExists(atPath: scratch.files.stateFile.path))
    }

    @Test func simultaneousClaimsLandOnce() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let outcomes = await withTaskGroup(of: OwnershipChange.self) { group in
            for index in 0..<8 {
                group.addTask { scratch.live("com.example.claimer\(index)").claimAtFirstRun() }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(outcomes.filter { if case .changed = $0 { true } else { false } }.count <= 1)
        #expect(outcomes.allSatisfy { if case .changed = $0 { true } else { $0 == .noChange || $0 == .busy } })
        #expect((scratch.state?.generation ?? 0) <= 1)
    }

    @Test func aClaimRacingAHandoffFromNobodyLeavesOneOwnerAndCountsEachChange() async throws {
        for _ in 0..<20 {
            let scratch = try Scratch()
            defer { scratch.cleanUp() }
            let handoff = Task { await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) }
            let claim = scratch.live(ownerID).claimAtFirstRun()
            let outcome = await handoff.value
            let changes = (claim == .changed(generation: 1) ? 1 : 0) + (outcome == .alreadyOwner ? 0 : 1)
            #expect(scratch.state?.owner == otherID, "A user's handoff lands last or alone")
            #expect(scratch.state?.generation == changes)
            #expect(scratch.state?.intent == nil)
        }
    }

    @Test func thePreferenceOffMeansNoClaim() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        scratch.conditions.current.preferenceIsOn = false
        #expect(scratch.live(ownerID).claimAtFirstRun() == .noChange)
    }

    @Test func aLiveIntentBlocksTheClaimAndARollbackAllowsIt() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let intent = OwnershipIntent(from: nil, to: otherID, now: Date())
        try scratch.seed(OwnershipState(owner: nil, generation: 0, previous: nil, intent: intent))
        #expect(scratch.live(ownerID).claimAtFirstRun() == .noChange)
        try scratch.seed(.nobody)
        #expect(scratch.live(ownerID).claimAtFirstRun() == .changed(generation: 1))
    }

    @Test func aBusyCaptureLockWaitsForTheNextReevaluation() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let held = lease(from: scratch.live(otherID).acquire(.practice))
        #expect(scratch.live(ownerID).claimAtFirstRun() == .busy)
        held?.release()
        #expect(scratch.live(ownerID).claimAtFirstRun() == .changed(generation: 1))
    }

    @Test func aDevBuildTakesOwnershipOnlyWhenConfirmedAndKeepsItAcrossARelaunch() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let dev = "\(ownerID).dev"
        #expect(await scratch.live(dev).takeOwnership(userConfirmed: false, triggers: FakeTriggers()) == .notConfirmed)
        #expect(refusal(from: scratch.live(dev).acquire(.global)) == .notOwner(ownerID))
        #expect(await scratch.live(dev).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .completed(generation: 2))
        #expect(scratch.live(dev).status() == .owned)
        let held = lease(from: scratch.live(dev).acquire(.global))
        #expect(refusal(from: scratch.live(ownerID).acquire(.practice)) == .busy, "One capture across both")
        held?.release()
    }
}

struct ObserverTests {
    private func observer(for ownership: DictationOwnership) -> (OwnershipObserver, Recorder) {
        let recorder = Recorder()
        return (OwnershipObserver(ownership: ownership) { recorder.add($0) }, recorder)
    }

    @Test func thePriorOwnerRecoversOnItsOwnTimerWithNoOtherEvent() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        // Created long enough ago that it expires in one to two seconds, after the first read.
        let created = Date().addingTimeInterval(2 - OwnershipIntent.lifetime)
        let intent = OwnershipIntent(from: ownerID, to: otherID, now: created)
        try scratch.seed(OwnershipState(owner: ownerID, generation: 1, previous: nil, intent: intent))
        let app = SyntheticApp(ownership: scratch.live(ownerID))
        await app.run()
        #expect(app.latest?.state == .transferring)
        #expect(!app.triggers.armed)
        try await waitUntil(seconds: 5) { app.latest?.state == .owned }
        #expect(app.triggers.armed, "It rearms with no other event")
        await app.shutDown()
    }

    @Test func aHolderSeesAnIntentWithinASecondWithNoNotification() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let (watch, recorder) = observer(for: scratch.live(ownerID))
        await watch.start()
        await watch.setHoldingLease(true)
        let intent = OwnershipIntent(from: ownerID, to: otherID, now: Date())
        try scratch.seed(OwnershipState(owner: ownerID, generation: 1, previous: nil, intent: intent))
        try await waitUntil(seconds: 1.8) { recorder.latest?.intent?.id == intent.id }
        await watch.stop()
    }

    @Test func aParticipantWithNoLeaseAndNoIntentDoesNotPoll() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let (watch, recorder) = observer(for: scratch.live(ownerID))
        await watch.start()
        try scratch.seedOwner(otherID)
        try await Task.sleep(for: .milliseconds(1_300))
        #expect(recorder.latest?.state == .owned, "With no hint it has not re-read yet")
        await watch.reevaluate()
        #expect(recorder.latest?.state == .available)
        await watch.stop()
    }

    @Test func aHandoffWakesTheOtherParticipantThroughTheNotification() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let (watch, recorder) = observer(for: scratch.live(ownerID))
        await watch.start()
        #expect(await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .completed(generation: 2))
        try await waitUntil(seconds: 3) { recorder.latest?.state == .available }
        await watch.stop()
    }

    @Test func aRollbackWakesThePriorOwnerThroughTheNotification() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let (watch, recorder) = observer(for: scratch.live(ownerID))
        await watch.start()
        let slow = OwnershipTimings(changeDeadline: .seconds(1), capturePoll: .milliseconds(2), armRetry: .milliseconds(5))
        let outcome = await scratch.live(otherID, timings: slow).takeOwnership(userConfirmed: true, triggers: FakeTriggers(refusals: .max))
        #expect(outcome == .triggerConflict)
        try await waitUntil(seconds: 3) { recorder.latest?.state == .owned && recorder.latest?.intent == nil }
        #expect(recorder.history.contains { $0.state == .transferring }, "It has to have seen the intent to prove recovery")
        await watch.stop()
    }

    @Test func nothingIsReportedAfterStop() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let (watch, recorder) = observer(for: scratch.live(ownerID))
        await watch.start()
        await watch.start()
        await watch.setHoldingLease(true)
        await watch.stop()
        let reports = recorder.history.count
        try scratch.seedOwner(otherID)
        await watch.reevaluate()
        await watch.setHoldingLease(true)
        scratch.live(otherID).postChange()
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(recorder.history.count == reports)
    }
}

struct NonCooperatingPeerTests {
    private let peer = KnownPeer(identifier: "com.example.peer", preferenceKey: "dictationOn")

    private func bundle(in scratch: Scratch, declaring value: Any?) throws -> URL {
        let url = scratch.root.appendingPathComponent("\(UUID().uuidString).app")
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": peer.identifier]
        if let value { info[ProtocolDeclaration.infoKey] = value }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }

    private func active(_ url: URL?, identifier: String? = nil, preference: Bool = true) -> String? {
        let app = RunningApp(identifier: identifier ?? peer.identifier, bundleURL: url)
        return NonCooperatingPeers(known: [peer], running: { [app] }, preferenceIsOn: { _ in preference }).activePeer()
    }

    @Test func anUndeclaredPeerWithItsPreferenceOnIsActive() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        #expect(active(try bundle(in: scratch, declaring: nil)) == peer.identifier)
    }

    @Test func aMissingBundleCountsAsUndeclared() {
        #expect(active(nil) == peer.identifier)
    }

    @Test func aPeerWithItsPreferenceOffIsNotActive() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        #expect(active(try bundle(in: scratch, declaring: nil), preference: false) == nil)
    }

    @Test(arguments: [0, 1, 2])
    func aDeclaredPeerIsNotActive(value: Int) throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        #expect(active(try bundle(in: scratch, declaring: value)) == nil)
    }

    @Test func anUnknownAppIsIgnored() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        #expect(active(try bundle(in: scratch, declaring: nil), identifier: "com.example.unrelated") == nil)
    }

    @Test func noPeerRunningMeansNotActive() {
        #expect(NonCooperatingPeers(known: [peer], running: { [] }, preferenceIsOn: { _ in true }).activePeer() == nil)
    }

    @Test func theDeclarationIsReadFromTheFileEachTime() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try bundle(in: scratch, declaring: nil)
        #expect(ProtocolDeclaration(bundleURL: url) == .absent)
        let plist = url.appendingPathComponent("Contents/Info.plist")
        try PropertyListSerialization.data(fromPropertyList: [ProtocolDeclaration.infoKey: 1], format: .xml, options: 0)
            .write(to: plist)
        #expect(ProtocolDeclaration(bundleURL: url) == .implements(version: 1))
    }

    @Test func aDeclarationOfTheWrongTypeCountsAsAbsent() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        #expect(ProtocolDeclaration(bundleURL: try bundle(in: scratch, declaring: "1")) == .absent)
        #expect(ProtocolDeclaration(bundleURL: try bundle(in: scratch, declaring: -1)) == .absent)
        #expect(ProtocolDeclaration(bundleURL: try bundle(in: scratch, declaring: true)) == .absent)
        #expect(ProtocolDeclaration(bundleURL: try bundle(in: scratch, declaring: 1.5)) == .absent)
    }

    // A path works as a domain, so the file stays in the scratch folder and out of the real preferences.
    @Test func aStoredPreferenceReadsAsThePeerReadsIt() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let cases: [(stored: Any?, expected: Bool)] = [
            (true, true), (false, false), ("YES", true), ("NO", false), (2, true), (0, false), (nil, false)
        ]
        for (index, entry) in cases.enumerated() {
            let domain = scratch.root.appendingPathComponent("peer\(index)")
            var info: [String: Any] = ["other": "value"]
            if let stored = entry.stored { info["dictationOn"] = stored }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: domain.appendingPathExtension("plist"))
            let peer = KnownPeer(identifier: domain.path, preferenceKey: "dictationOn")
            #expect(NonCooperatingPeers.storedPreference(of: peer) == entry.expected, "\(String(describing: entry.stored))")
        }
    }

    @Test func readingAMissingDomainCreatesNothing() throws {
        let domain = "com.example.dictation-ownership-test.\(UUID().uuidString)"
        #expect(!NonCooperatingPeers.storedPreference(of: KnownPeer(identifier: domain, preferenceKey: "dictationOn")))
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(domain).plist")
        #expect(!FileManager.default.fileExists(atPath: plist.path))
    }
}

struct ToggleTests {
    @Test func aHandoffLoopWithLiveClientsNeverOverlaps() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(generation: 0)
        let stop = scratch.root.deletingLastPathComponent().appendingPathComponent("stop")
        let arguments = ["--until-file", stop.path, "--hold-us", "100"]
        let clients = [
            try scratch.client("sessions", participant: ownerID, extra: arguments),
            try scratch.client("sessions", participant: otherID, extra: arguments)
        ]
        let timings = OwnershipTimings(changeDeadline: .seconds(5), capturePoll: .milliseconds(1), armRetry: .milliseconds(5))
        var expected = 0
        for round in 0..<100 {
            let target = round.isMultiple(of: 2) ? otherID : ownerID
            let outcome = await scratch.live(target, timings: timings).takeOwnership(userConfirmed: true, triggers: FakeTriggers())
            #expect(outcome == .completed(generation: expected + 1))
            expected += 1
            try await Task.sleep(for: .milliseconds(1))
        }
        FileManager.default.createFile(atPath: stop.path, contents: nil)
        for client in clients { await finishClean(client) }

        let events = try scratch.events()
        #expect(violations(in: events).isEmpty)
        #expect(scratch.state?.generation == expected)
        for client in clients {
            #expect(events.contains("enter \(client.processIdentifier)"), "Each client has to have run while it owned")
        }
    }
}

/// A minimal app on top of the protocol, connecting the observer to triggers, a session and delivery.
final class SyntheticApp: Sendable {
    private struct Session {
        let token: SessionAttempts.Token
        var phase: SessionPhase
        let text: String
        var intentSeen: Date?
    }

    let ownership: DictationOwnership
    let triggers = FakeTriggers()
    private let attempts: SessionAttempts
    private let session = Mutex<Session?>(nil)
    private let pastedTexts = Mutex<[String]>([])
    private let keptTexts = Mutex<[String]>([])
    private let observer = Mutex<OwnershipObserver?>(nil)
    private let recorder = Recorder()

    init(ownership: DictationOwnership) {
        self.ownership = ownership
        attempts = SessionAttempts(ownership: ownership)
    }

    var latest: OwnershipObserver.Snapshot? { recorder.latest }
    var pasted: [String] { pastedTexts.withLock { $0 } }
    var kept: [String] { keptTexts.withLock { $0 } }
    var isInSession: Bool { session.withLock { $0 != nil } }

    func run() async {
        let created = OwnershipObserver(ownership: ownership) { [weak self] snapshot in self?.handle(snapshot) }
        observer.withLock { $0 = created }
        await created.start()
    }

    func shutDown() async {
        await observer.withLock { $0 }?.stop()
    }

    func begin(_ phase: SessionPhase, text: String) async -> Bool {
        let started = attempts.start(phase == .practice ? .practice : .global)
        guard case .admitted = started.admission else { return false }
        session.withLock { $0 = Session(token: started.token, phase: phase, text: text) }
        await observer.withLock { $0 }?.setHoldingLease(true)
        return true
    }

    /// A Stop reaches only this attempt's lease, and delivery revalidates first.
    func deliver() async {
        guard let current = session.withLock({ $0 }) else { return }
        if attempts.lease(for: current.token)?.revalidate() == true {
            pastedTexts.withLock { $0.append(current.text) }
        } else {
            keptTexts.withLock { $0.append(current.text) }
        }
        await end(current.token)
    }

    private func handle(_ snapshot: OwnershipObserver.Snapshot) {
        recorder.add(snapshot)
        triggers.setArmed(snapshot.state.armsTriggers)
        guard snapshot.intent != nil else { return }
        session.withLock { current in
            if current?.intentSeen == nil { current?.intentSeen = Date() }
        }
        cancelIfDue()
        if session.withLock({ $0?.phase }) == .listening {
            DispatchQueue.global().asyncAfter(deadline: .now() + SessionPhase.listeningGrace) { [weak self] in
                self?.cancelIfDue()
            }
        }
    }

    private func cancelIfDue() {
        guard let current = session.withLock({ $0 }), let seen = current.intentSeen,
              current.phase.shouldCancel(secondsSinceIntentSeen: Date().timeIntervalSince(seen)) else { return }
        keptTexts.withLock { $0.append(current.text) }
        Task { await end(current.token) }
    }

    private func end(_ token: SessionAttempts.Token) async {
        session.withLock { $0 = nil }
        attempts.finish(token)
        await observer.withLock { $0 }?.setHoldingLease(false)
    }
}

struct SessionFlowTests {
    private func app(_ id: String, in scratch: Scratch) async -> SyntheticApp {
        let app = SyntheticApp(ownership: scratch.live(id))
        await app.run()
        return app
    }

    private func handoff(_ scratch: Scratch) async -> HandoffOutcome {
        await scratch.live(otherID).takeOwnership(userConfirmed: true, triggers: FakeTriggers())
    }

    @Test func aPreparingSessionIsCancelledAndTheHandoffCompletes() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let prior = await app(ownerID, in: scratch)
        #expect(await prior.begin(.preparing, text: "synthetic words"))
        #expect(await handoff(scratch) == .completed(generation: 2))
        try await waitUntil { !prior.isInSession && prior.latest?.state == .available }
        #expect(prior.kept == ["synthetic words"])
        await prior.deliver()
        #expect(prior.pasted.isEmpty, "A cancelled session never pastes later")
        #expect(!prior.triggers.armed)
        await prior.shutDown()
    }

    @Test func aListeningSessionGetsItsGraceThenIsCancelledWithItsTextKept() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let prior = await app(ownerID, in: scratch)
        #expect(await prior.begin(.listening, text: "synthetic words"))
        let started = ContinuousClock.now
        #expect(await handoff(scratch) == .completed(generation: 2))
        let elapsed = started.duration(to: .now)
        #expect(elapsed >= .seconds(SessionPhase.listeningGrace - 1), "It was not cut off at once")
        #expect(elapsed < .seconds(SessionPhase.listeningGrace + 3))
        #expect(prior.kept == ["synthetic words"])
        #expect(prior.pasted.isEmpty)
        await prior.shutDown()
    }

    @Test func aSessionPastTheMicrophoneDeliversAndThenTheHandoffCompletes() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let prior = await app(ownerID, in: scratch)
        #expect(await prior.begin(.microphoneClosed, text: "synthetic words"))
        let pending = Task { await handoff(scratch) }
        try await waitUntil { prior.latest?.intent != nil }
        try await Task.sleep(for: .milliseconds(100))
        #expect(prior.isInSession, "It is not cancelled")
        await prior.deliver()
        #expect(prior.pasted == ["synthetic words"], "A Stop after the handoff began still ends its own session")
        #expect(await pending.value == .completed(generation: 2))
        await prior.shutDown()
    }

    @Test func aLongDeliveryEndsInTimeoutAndIsNotInterrupted() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let prior = await app(ownerID, in: scratch)
        #expect(await prior.begin(.microphoneClosed, text: "synthetic words"))
        #expect(await scratch.live(otherID, timings: quick).takeOwnership(userConfirmed: true, triggers: FakeTriggers()) == .timedOut)
        await prior.deliver()
        #expect(prior.pasted == ["synthetic words"])
        #expect(scratch.state?.owner == ownerID)
        await prior.shutDown()
    }

    @Test func practiceInAThirdParticipantIsCancelledForAHandoffItIsNotNamedIn() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let third = await app("com.example.third", in: scratch)
        #expect(await third.begin(.practice, text: "synthetic words"))
        #expect(await handoff(scratch) == .completed(generation: 2))
        #expect(third.kept == ["synthetic words"])
        await third.shutDown()
    }

    @Test func thePriorOwnerDisarmsAndRearmsAroundAFailedHandoff() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let prior = await app(ownerID, in: scratch)
        #expect(prior.triggers.armed)
        let slow = OwnershipTimings(changeDeadline: .seconds(1), capturePoll: .milliseconds(2), armRetry: .milliseconds(5))
        let target = FakeTriggers(refusals: .max)
        let pending = Task { await scratch.live(otherID, timings: slow).takeOwnership(userConfirmed: true, triggers: target) }
        try await waitUntil(seconds: 1) { !prior.triggers.armed }
        #expect(await pending.value == .triggerConflict)
        try await waitUntil { prior.triggers.armed }
        await prior.shutDown()
    }
}

/// Runs a step during the handoff's arming, to change the world at the moment that matters.
final class FakeArmingHook: OwnershipTriggers {
    private let step: @Sendable () -> Void
    private let isArmed = Mutex(false)

    init(step: @escaping @Sendable () -> Void) {
        self.step = step
    }

    var armed: Bool { isArmed.withLock { $0 } }

    func arm() async -> Bool {
        step()
        isArmed.withLock { $0 = true }
        return true
    }

    func disarm() async {
        isArmed.withLock { $0 = false }
    }
}

/// Holds arming open until a test says so, and ignores cancellation as a real controller might.
final class GatedTriggers: OwnershipTriggers {
    private let state = Mutex((waiting: false, open: false, armed: false))

    var isWaiting: Bool { state.withLock { $0.waiting } }
    var armed: Bool { state.withLock { $0.armed } }

    func open() {
        state.withLock { $0.open = true }
    }

    func arm() async -> Bool {
        state.withLock { $0.waiting = true }
        while !state.withLock({ $0.open }) {
            usleep(1_000)
            await Task.yield()
        }
        state.withLock { $0.armed = true }
        return true
    }

    func disarm() async {
        state.withLock { $0.armed = false }
    }
}

final class Recorder: Sendable {
    private let snapshots = Mutex<[OwnershipObserver.Snapshot]>([])

    func add(_ snapshot: OwnershipObserver.Snapshot) {
        snapshots.withLock { $0.append(snapshot) }
    }

    var latest: OwnershipObserver.Snapshot? { snapshots.withLock { $0.last } }
    var history: [OwnershipObserver.Snapshot] { snapshots.withLock { $0 } }
}

func waitUntil(
    seconds: Double = 2,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}
