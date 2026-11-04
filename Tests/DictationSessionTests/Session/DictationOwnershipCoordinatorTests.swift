import AppKit
import DictationOwnership
import Foundation
import DictationKit
import Synchronization
import LiveSpeech
import SpeechCore
import Testing

@testable import DictationSession

/// The protocol's app acceptance rows, against the real locks in a scratch folder.
@Suite(.serialized, .exclusiveArgumentDomain, .timeLimit(.minutes(1)))
@MainActor
struct DictationOwnershipCoordinatorTests {
    private static let secreteo = "com.johnny4young.secreteo"
    private static let other = "com.example.other"

    @MainActor
    private final class Scratch {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("secreteo-ownership-\(UUID().uuidString)", isDirectory: true)
        var settle: () async -> Void = {}
        var lastOwnership: DictationOwnership?

        func participant(_ identifier: String) -> DictationOwnership {
            DictationOwnership(
                participant: identifier, root: root,
                conditions: {
                    ParticipantConditions(preferenceIsOn: true, missingForReadiness: nil, legacyPeerIsActive: false)
                },
                notificationName: "com.johnny4young.secreteo.ownership-tests.\(root.lastPathComponent)")
        }

        /// Secreteo as the owner.
        func coordinator() -> DictationOwnershipCoordinator {
            let ownership = participant(DictationOwnershipCoordinatorTests.secreteo)
            lastOwnership = ownership
            // Secreteo never claims on its own, so these tests set up the owner themselves.
            _ = ownership.claimAtFirstRun()
            let coordinator = DictationOwnershipCoordinator(ownership: ownership) { [self] in await settle() }
            coordinator.start()
            return coordinator
        }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    private final class Preference: Sendable {
        let isOn = Mutex(false)
    }

    private struct Triggers: OwnershipTriggers {
        func arm() async -> Bool { true }
        func disarm() async {}
    }

    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        _ = await TestPolling.until(condition)
        try #require(condition())
    }

    private func acquire(_ coordinator: DictationOwnershipCoordinator) throws -> DictationLease {
        try coordinator.admission.acquire(.global).get()
    }

    /// Leaves `lease` waiting on the clipboard, which is what a new session may share.
    private func waitOnClipboard(
        _ lease: DictationLease, scratch: Scratch
    ) async throws -> (gate: PreparationGate, finished: Task<Void, Never>) {
        let gate = PreparationGate()
        scratch.settle = { await gate.wait() }
        let finished = Task { await lease.releaseAfterDelivery() }
        try await eventually { gate.started }
        return (gate, finished)
    }

    @Test
    func aLockFileReplacedDuringTheRestoreRefusesTheJoin() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let first = try acquire(coordinator)
        let (gate, finished) = try await waitOnClipboard(first, scratch: scratch)
        let lock = scratch.root.appendingPathComponent("capture.lock")
        try FileManager.default.removeItem(at: lock)
        try Data().write(to: lock)

        #expect(throws: DictationAdmissionRefusal.unavailable(.ioError)) { try acquire(coordinator) }

        gate.release()
        await finished.value
    }

    @Test
    func watchingContinuesUntilTheLastRelease() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let first = try acquire(coordinator)
        let (gate, finished) = try await waitOnClipboard(first, scratch: scratch)
        let second = try acquire(coordinator)
        gate.release()
        await finished.value

        #expect(coordinator.holdsLease)

        second.release()

        #expect(!coordinator.holdsLease)
    }

    @Test
    func theUserCanTakeOwnershipFromAnotherOwner() async throws {
        let scratch = Scratch()
        _ = scratch.participant(Self.other).claimAtFirstRun()
        let coordinator = DictationOwnershipCoordinator(ownership: scratch.participant(Self.secreteo)) {}
        coordinator.start()
        #expect(coordinator.state == .available)

        let outcome = await coordinator.takeOwnership(arm: { true }, disarm: {})

        #expect(outcome == .completed(generation: 2))
        #expect(coordinator.state == .owned)
    }

    @Test
    func turningOnReportsWhyItDidNotBecomeTheOwner() async throws {
        let scratch = Scratch()
        let quick = OwnershipTimings(changeDeadline: .milliseconds(100), capturePoll: .milliseconds(2), armRetry: .milliseconds(5))
        let ownership = DictationOwnership(
            participant: Self.secreteo, root: scratch.root,
            conditions: {
                ParticipantConditions(preferenceIsOn: true, missingForReadiness: nil, legacyPeerIsActive: false)
            },
            notificationName: "com.johnny4young.secreteo.ownership-tests.\(scratch.root.lastPathComponent)",
            timings: quick)
        let coordinator = DictationOwnershipCoordinator(ownership: ownership) {}
        coordinator.start()

        let outcome = await coordinator.preferenceChanged(isOn: true, arm: { false }, disarm: {})

        #expect(outcome == .triggerConflict)
        #expect(coordinator.state == .available)
    }

    @Test
    func aFirstRunNeverClaimsEvenWithThePreferenceOn() throws {
        let scratch = Scratch()
        let ownership = scratch.participant(Self.secreteo)
        let coordinator = DictationOwnershipCoordinator(ownership: ownership) {}

        coordinator.start()
        coordinator.reevaluate()

        #expect(coordinator.state == .available)
        #expect(!coordinator.armsTriggers)
        #expect(!coordinator.admission.isEligible())
        guard case .failure(.notOwner) = coordinator.admission.acquire(.global) else {
            Issue.record("A first run must not be admitted")
            return
        }
    }

    @Test
    func anotherAppIsRefusedWhileThisOneHoldsItsLease() throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let lease = try acquire(coordinator)
        defer { lease.release() }

        guard case .refused(.busy) = scratch.participant(Self.other).acquire(.practice) else {
            Issue.record("The other app got in")
            return
        }
    }

    @Test
    func aNonOwnerIsRefusedAndArmsNothing() async throws {
        let scratch = Scratch()
        let other = scratch.participant(Self.other)
        #expect(await other.takeOwnership(userConfirmed: true, triggers: Triggers()) == .completed(generation: 1))

        let coordinator = scratch.coordinator()

        #expect(coordinator.state == .available)
        #expect(!coordinator.armsTriggers)
        #expect(!coordinator.admission.isEligible())
        #expect(throws: DictationAdmissionRefusal.notOwner) { try coordinator.admission.acquire(.global).get() }
        #expect(throws: Never.self) {
            try coordinator.admission.acquire(.practice).get().release()
        }
    }

    @Test
    func aNewSessionDuringCaptureOrDeliveryIsRefusedBusy() throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let working = try acquire(coordinator)
        defer { working.release() }

        #expect(throws: DictationAdmissionRefusal.busy) { try acquire(coordinator) }
    }

    @Test
    func aNewSessionDuringTheRestoreSharesTheLease() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let first = try acquire(coordinator)
        let (gate, finished) = try await waitOnClipboard(first, scratch: scratch)

        let second = try acquire(coordinator)

        #expect(second.revalidate())
        #expect(throws: DictationAdmissionRefusal.busy) { try acquire(coordinator) }
        second.release()
        gate.release()
        await finished.value
    }

    @Test
    func anEarlyReleaseKeepsTheLockUntilTheLastSessionEnds() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let other = scratch.participant(Self.other)
        let first = try acquire(coordinator)
        let (gate, finished) = try await waitOnClipboard(first, scratch: scratch)
        let second = try acquire(coordinator)

        gate.release()
        await finished.value

        guard case .refused(.busy) = other.acquire(.practice) else {
            Issue.record("The lock was freed under the second session")
            return
        }

        second.release()

        guard case .admitted(let lease) = other.acquire(.practice) else {
            Issue.record("The lock was not free after the last session")
            return
        }
        lease.release()
    }

    @Test
    func practiceIsRefusedDuringAGlobalRestore() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let first = try acquire(coordinator)
        let (gate, finished) = try await waitOnClipboard(first, scratch: scratch)

        #expect(throws: DictationAdmissionRefusal.busy) { try coordinator.admission.acquire(.practice).get() }

        gate.release()
        await finished.value
    }

    @Test
    func aRefusedJoinLeavesTheLockWithTheEarlierSession() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let first = try acquire(coordinator)
        let (gate, finished) = try await waitOnClipboard(first, scratch: scratch)
        let other = scratch.participant(Self.other)
        let handoff = Task { await other.takeOwnership(userConfirmed: true, triggers: Triggers()) }
        try await eventually { ownershipStatus(scratch) == .transferring }

        #expect(throws: DictationAdmissionRefusal.transferring) { try acquire(coordinator) }

        guard case .refused(.busy) = other.acquire(.practice) else {
            Issue.record("A refused join gave up the earlier session's lock")
            return
        }
        gate.release()
        await finished.value
        _ = await handoff.value
    }

    @Test
    func aPracticeLeaseIsNeverShared() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let practice = try coordinator.admission.acquire(.practice).get()
        let (gate, finished) = try await waitOnClipboard(practice, scratch: scratch)

        #expect(throws: DictationAdmissionRefusal.busy) { try acquire(coordinator) }
        #expect(throws: DictationAdmissionRefusal.busy) { try coordinator.admission.acquire(.practice).get() }

        gate.release()
        await finished.value
    }

    @Test
    func aLiveIntentRefusesANewSessionAndTheHandoffCompletesAfterTheRestore() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let first = try acquire(coordinator)
        let (gate, finished) = try await waitOnClipboard(first, scratch: scratch)
        let other = scratch.participant(Self.other)
        let handoff = Task { await other.takeOwnership(userConfirmed: true, triggers: Triggers()) }
        try await eventually { ownershipStatus(scratch) == .transferring }

        #expect(throws: DictationAdmissionRefusal.transferring) { try acquire(coordinator) }

        gate.release()
        await finished.value
        #expect(await handoff.value == .completed(generation: 2))
        #expect(!first.revalidate())
    }

    private func ownershipStatus(_ scratch: Scratch) -> ParticipantState? {
        scratch.lastOwnership?.status()
    }

    @Test
    func aHandoffThereAndBackChangesTheGeneration() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let read = try acquire(coordinator)
        read.release()
        let other = scratch.participant(Self.other)
        #expect(await other.takeOwnership(userConfirmed: true, triggers: Triggers()) == .completed(generation: 2))
        let secreteo = try #require(scratch.lastOwnership)
        #expect(await secreteo.takeOwnership(userConfirmed: true, triggers: Triggers()) == .completed(generation: 3))
        coordinator.reevaluate()

        let replace = try acquire(coordinator)
        defer { replace.release() }

        #expect(replace.generation != read.generation)
        #expect(replace.revalidate())
    }

    // MARK: Sessions

    @Test
    func anIntentCancelsASessionStillPreparing() async throws {
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        var dependencies = harness.dependencies
        dependencies.authorizeMicrophone = { try? await Task.sleep(for: .seconds(3_600)); return false }
        harness.controller.toggle(using: dependencies)
        #expect(harness.controller.phase == .preparing)

        harness.controller.ownershipIntentSeen()

        #expect(harness.controller.phase == .idle)
        #expect(harness.insertions.isEmpty)
    }

    @Test
    func aListeningSessionKeepsItsWordsWhenTheGraceEnds() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.handoffGrace = .milliseconds(50)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)

        harness.controller.ownershipIntentSeen()

        #expect(harness.controller.phase == .listening, "It keeps listening during the grace")
        try await eventually { harness.controller.phase == .recovery(.ownershipChanged) }
        #expect(harness.controller.recoveryText == harness.text)
        #expect(harness.insertions.isEmpty)
    }

    @Test
    func aSessionFinishedInsideTheGraceDeliversNormally() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.handoffGrace = .seconds(3_600)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.ownershipIntentSeen()

        harness.controller.toggle(using: dependencies)

        try await eventually { harness.insertions == [harness.text] }
    }

    @Test
    func anIntentThatGoesAwayEndsTheGrace() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.handoffGrace = .milliseconds(50)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.ownershipIntentSeen()

        harness.controller.ownershipIntentCleared()
        try await Task.sleep(for: .milliseconds(150))

        #expect(harness.controller.phase == .listening)
        #expect(!harness.controller.yieldsToHandoff)
    }

    @Test
    func anIntentAfterTheMicrophoneClosedLetsTheSessionFinish() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.handoffGrace = .milliseconds(1)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)

        harness.controller.ownershipIntentSeen()

        try await eventually { harness.insertions == [harness.text] }
    }

    @Test
    func aGraceEndingAfterTheUserFinishedLetsTheSessionFinish() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.handoffGrace = .milliseconds(20)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.ownershipIntentSeen()

        harness.controller.toggle(using: dependencies)

        try await eventually { harness.insertions == [harness.text] }
    }

    @Test
    func yieldedWordsSkipPolishSoTheLeaseEndsSoon() async throws {
        let harness = DictationControllerHarness(text: "so we ship it tomorrow")
        defer { harness.controller.cancel() }
        harness.set(DictationTextMode.polish.rawValue, forKey: DictationTextPreferences.modeKey)
        var dependencies = harness.dependencies
        var polished = 0
        dependencies.polishDictation = { text, _, _ in
            polished += 1
            return .polished(text)
        }
        dependencies.handoffGrace = .milliseconds(20)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)

        harness.controller.ownershipIntentSeen()

        try await eventually { harness.controller.phase == .recovery(.ownershipChanged) }
        #expect(polished == 0)
    }

    private final class KeyRegistration: GlobalHotkeyRegistration {
        let onUnregister: () -> Void
        init(onUnregister: @escaping () -> Void) { self.onUnregister = onUnregister }
        func unregister() { onUnregister() }
    }

    @Test
    func aPressRightAfterCancelIsRefusedUntilStopHasDrained() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        var dependencies = harness.dependencies
        dependencies.admission = coordinator.admission
        let stop = StopGate()
        await harness.microphone.holdStop { await stop.wait() }
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.controller.cancel()

        harness.controller.toggle(using: dependencies)

        #expect(harness.controller.phase == .idle)
        #expect(coordinator.holdsLease)
        stop.open()
        try await eventually { !coordinator.holdsLease }
        harness.controller.toggle(using: dependencies)
        #expect(harness.controller.phase != .idle)
        await harness.microphone.holdStop {}
        harness.controller.cancel()
        try await eventually { !coordinator.holdsLease }
    }

    private final class StopGate: Sendable {
        private let opened = Mutex(false)

        func open() { opened.withLock { $0 = true } }

        func wait() async {
            while !opened.withLock({ $0 }) {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    @Test
    func anOwnerChangeBeforeDeliveryKeepsTheWordsInRecovery() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.admission = DictationAdmission(
            acquire: { _ in .success(DictationLease(revalidate: { false })) }, isEligible: { true })

        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)

        try await eventually { harness.controller.phase == .recovery(.ownershipChanged) }
        #expect(harness.controller.recoveryText == harness.text)
        #expect(harness.insertions.isEmpty)
    }

    @Test
    func anOwnerChangeBeforeAReplayKeepsTheWordsInRecovery() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        var isOwner = true
        var dependencies = harness.dependencies
        dependencies.admission = DictationAdmission(
            acquire: { _ in .success(DictationLease(revalidate: { isOwner })) }, isEligible: { true })
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.insertions.count == 1 && !harness.controller.isActive }
        isOwner = false

        harness.controller.pasteLastDictation(using: dependencies)

        try await eventually { harness.controller.phase == .recovery(.ownershipChanged) }
        #expect(harness.insertions.count == 1)
    }

}
