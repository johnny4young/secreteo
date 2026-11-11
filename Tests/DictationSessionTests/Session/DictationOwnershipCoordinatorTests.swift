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
        func coordinator(pendingWrites: DictationPendingWrites? = nil) -> DictationOwnershipCoordinator {
            let ownership = participant(DictationOwnershipCoordinatorTests.secreteo)
            lastOwnership = ownership
            // Secreteo never claims on its own, so these tests set up the owner themselves.
            _ = ownership.claimAtFirstRun()
            let coordinator = DictationOwnershipCoordinator(ownership: ownership, pendingWrites: pendingWrites) {
                [self] in await settle()
            }
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

    /// The composition as a disposable launch builds it: it claims its scratch owner and starts nothing.
    private func disposableFeature(_ defaults: UserDefaults) throws -> DictationFeature {
        try DictationFeature(usesTemporaryStore: true, arguments: ["-use-temp-store"], defaults: defaults)
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
    func aTurnOffThatMetABusyLockIsRetriedWithNoOtherEvent() async throws {
        struct AlwaysArms: OwnershipTriggers {
            func arm() async -> Bool { true }
            func disarm() async {}
        }
        let scratch = Scratch()
        let preference = Preference()
        preference.isOn.withLock { $0 = true }
        let ownership = DictationOwnership(
            participant: Self.secreteo, root: scratch.root,
            conditions: {
                ParticipantConditions(
                    preferenceIsOn: preference.isOn.withLock { $0 }, missingForReadiness: nil, legacyPeerIsActive: false)
            },
            notificationName: "com.johnny4young.secreteo.ownership-tests.\(scratch.root.lastPathComponent)",
            timings: OwnershipTimings(changeDeadline: .milliseconds(50), capturePoll: .milliseconds(2), armRetry: .milliseconds(5)))
        _ = ownership.claimAtFirstRun()
        let coordinator = DictationOwnershipCoordinator(ownership: ownership, turnOffRetry: .milliseconds(10)) {}
        coordinator.start()
        let other = scratch.participant(Self.other)
        guard case .admitted(let held) = other.acquire(.practice) else {
            Issue.record("The other app could not take the lock")
            return
        }

        preference.isOn.withLock { $0 = false }
        await coordinator.preferenceChanged(isOn: false, arm: { true }, disarm: {})
        #expect(coordinator.state == .off)
        // Longer than the attempt in flight, so only a retry can finish the turn off.
        try await Task.sleep(for: .milliseconds(200))
        held.release()

        let tookOver = await TestPolling.untilAsync {
            if case .completed = await other.preferenceTurnedOn(triggers: AlwaysArms()) { return true }
            return false
        }
        #expect(tookOver)
    }

    @Test
    func theLiveCoordinatorOffersOwnershipOnlyWhenReady() throws {
        let suite = "secreteo-ownership-readiness-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DictationController.defaultsKey)
        let missing = Mutex<String?>("microphone")
        let coordinator = DictationOwnershipCoordinator.live(
            defaults: defaults, usesTemporaryStore: true, missingForReadiness: { missing.withLock { $0 } })

        coordinator.start()
        #expect(coordinator.state == .preparing)

        missing.withLock { $0 = nil }
        coordinator.reevaluate()
        #expect(coordinator.state == .available)
    }

    @Test
    func aSeededLegacyPeerRefusesOnlyAsTheRealOneWould() throws {
        let suite = "secreteo-ownership-legacy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DictationController.defaultsKey)

        let coordinator = DictationOwnershipCoordinator.live(
            defaults: defaults, usesTemporaryStore: true, missingForReadiness: { nil }, seedsLegacyPeer: true)
        coordinator.start()

        #expect(coordinator.state == .unavailable(.legacyPeerActive))
        #expect(!coordinator.armsTriggers)
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
    func anActivationBeforeLaunchFinishesPublishesNothing() {
        let scratch = Scratch()
        let ownership = scratch.participant(Self.secreteo)
        _ = ownership.claimAtFirstRun()
        let coordinator = DictationOwnershipCoordinator(ownership: ownership) {}
        var changes = 0
        coordinator.onStateChange = { _ in changes += 1 }

        coordinator.reevaluate()

        #expect(coordinator.state == .off)
        #expect(changes == 0)
        coordinator.start()
        #expect(coordinator.state == .owned)
        #expect(changes == 1)
    }

    @Test
    func turningThePreferenceOnTakesOwnershipFromNobody() async {
        let scratch = Scratch()
        let preference = Preference()
        let ownership = DictationOwnership(
            participant: "com.johnny4young.secreteo.dev", root: scratch.root,
            conditions: {
                ParticipantConditions(
                    preferenceIsOn: preference.isOn.withLock { $0 }, missingForReadiness: nil, legacyPeerIsActive: false)
            },
            notificationName: "com.johnny4young.secreteo.ownership-tests.\(scratch.root.lastPathComponent)")
        let coordinator = DictationOwnershipCoordinator(ownership: ownership) {}
        coordinator.start()
        #expect(coordinator.state == .off)
        preference.isOn.withLock { $0 = true }
        var armed = 0

        await coordinator.preferenceChanged(isOn: true, arm: { armed += 1; return true }, disarm: {})

        #expect(coordinator.state == .owned)
        #expect(armed > 0)

        preference.isOn.withLock { $0 = false }
        await coordinator.preferenceChanged(isOn: false, arm: { true }, disarm: {})

        #expect(coordinator.state == .off)
        #expect(!coordinator.armsTriggers)
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

    @Test
    func onlyTheOwnerArmsTheShortcut() throws {
        let suite = "secreteo-ownership-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DictationController.defaultsKey)
        let feature = try disposableFeature(defaults)
        #expect(!feature.dictationTriggersMayArm)

        feature.start()

        #expect(feature.dictationTriggersMayArm)
    }

    @Test
    func aWorkspaceChangeIsAHintToLookAgain() throws {
        let scratch = Scratch()
        _ = scratch.participant(Self.secreteo).claimAtFirstRun()
        let peer = Preference()
        peer.isOn.withLock { $0 = true }
        let ownership = DictationOwnership(
            participant: Self.secreteo, root: scratch.root,
            conditions: {
                ParticipantConditions(
                    preferenceIsOn: true, missingForReadiness: nil, legacyPeerIsActive: peer.isOn.withLock { $0 })
            },
            notificationName: "com.johnny4young.secreteo.ownership-tests.\(scratch.root.lastPathComponent)")
        let coordinator = DictationOwnershipCoordinator(ownership: ownership) {}
        coordinator.start()
        #expect(coordinator.state == .unavailable(.legacyPeerActive))
        peer.isOn.withLock { $0 = false }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        #expect(coordinator.state == .owned)
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
    func anIntentCancelsAPracticeSessionAtOnce() async throws {
        let harness = DictationControllerHarness(text: "Hola")
        let practice = DictationPracticeField()
        practice.show(UUID(), isKey: true)
        harness.controller.toggle(using: practice.route(harness.dependencies, appIsActive: true))
        _ = await TestPolling.until { harness.controller.partialText == "Hola" }

        harness.controller.ownershipIntentSeen()

        #expect(harness.controller.phase == .idle)
        #expect(practice.text.isEmpty)
    }

    @Test
    func anIntentCancelsAPracticeSessionEvenWhileItDelivers() async throws {
        let harness = DictationControllerHarness(text: "Hola")
        let practice = DictationPracticeField()
        practice.show(UUID(), isKey: true)
        var dependencies = practice.route(harness.dependencies, appIsActive: true)
        let delivery = PreparationGate()
        dependencies.captureDestination = {
            CapturedDictationDestination(name: "Practice", canRetry: false) { _ in
                await delivery.wait()
                return .verified
            }
        }
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == "Hola" }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.phase == .delivering && delivery.started }

        harness.controller.ownershipIntentSeen()

        #expect(harness.controller.phase == .idle)
        delivery.release()
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

    @Test
    func aSpokenInstructionKeepsItsWordsWhenTheGraceEnds() async throws {
        let port = DictationAdmission.open
        let controller = SelectionRewriteController(presentsPanel: false)
        defer { controller.cancel() }
        controller.start(using: rewriteDependencies(admission: port))
        try await eventually { controller.phase == .choosing }
        let harness = DictationControllerHarness(text: "make it formal")
        defer { harness.controller.cancel() }
        var dependencies = controller.instructionDependencies(harness.dependencies)
        dependencies.handoffGrace = .milliseconds(20)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)

        harness.controller.ownershipIntentSeen()

        try await eventually { harness.controller.phase == .recovery(.ownershipChanged) }
        #expect(harness.controller.recoveryText == harness.text)
        #expect(controller.spokenInstruction == nil)
    }

    @Test
    func aPreviewGivesUpItsGlobalKeysWhenOwnershipIsLost() async throws {
        var keys: [UInt32: () -> Void] = [:]
        var dependencies = rewriteDependencies(admission: .open)
        dependencies.registerKey = { keyCode, onPress in
            keys[keyCode] = onPress
            return KeyRegistration { keys[keyCode] = nil }
        }
        let controller = SelectionRewriteController(presentsPanel: false)
        defer { controller.cancel() }
        controller.start(using: dependencies)
        try await eventually { controller.phase == .choosing }
        controller.choose(nil)
        try await eventually { controller.phase == .preview("SO WE SHIP IT TOMORROW") }
        #expect(!keys.isEmpty)

        controller.releaseGlobalKeys()

        #expect(keys.isEmpty)
        #expect(controller.result == "SO WE SHIP IT TOMORROW")
    }

    @Test
    func aPreviewFromBeforeAResetCannotReplace() async throws {
        var inserted: [String] = []
        var dependencies = rewriteDependencies(admission: .open)
        dependencies.capture = {
            .success(CapturedSelection(
                text: "so we ship it tomorrow", source: .accessibility, applicationName: "Receiver",
                revalidate: { nil },
                destination: CapturedDictationDestination(name: "Receiver", canRetry: false) { text in
                    inserted.append(text)
                    return .verified
                }))
        }
        let controller = SelectionRewriteController(presentsPanel: false)
        defer { controller.cancel() }
        controller.start(using: dependencies)
        try await eventually { controller.phase == .choosing }
        controller.choose(nil)
        try await eventually { controller.phase == .preview("SO WE SHIP IT TOMORROW") }

        controller.revokeReplace()
        controller.replace()

        guard case .failed = controller.phase else {
            Issue.record("A replace went through after the state was reset")
            return
        }
        #expect(inserted.isEmpty)
    }

    private final class KeyRegistration: GlobalHotkeyRegistration {
        let onUnregister: () -> Void
        init(onUnregister: @escaping () -> Void) { self.onUnregister = onUnregister }
        func unregister() { onUnregister() }
    }

    private func rewriteDependencies(admission: DictationAdmission) -> SelectionRewriteController.Dependencies {
        SelectionRewriteController.Dependencies(
            admission: admission,
            capture: {
                .success(CapturedSelection(
                    text: "so we ship it tomorrow", source: .accessibility, applicationName: "Receiver",
                    revalidate: { nil },
                    destination: CapturedDictationDestination(name: "Receiver", canRetry: false) { _ in .verified }))
            },
            polish: { text, _, _ in .polished(text.uppercased()) },
            recipes: { [] }, protectedTerms: { [] }, copyText: { _ in true },
            wait: { _ in try await Task.sleep(for: .seconds(3_600)) })
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

    @Test
    func sleepKeepsTheLeaseUntilNativeStopDrains() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let notifications = NotificationCenter()
        let lastText = DictationLastText(
            workspaceNotifications: notifications, distributedNotifications: NotificationCenter())
        let controller = DictationController(presentsPanel: false, lastText: lastText)
        let harness = DictationControllerHarness(text: "No borres estas notas.", controller: controller)
        var dependencies = harness.dependencies
        dependencies.admission = coordinator.admission
        let stop = StopGate()
        defer { stop.open(); controller.cancel() }
        await harness.microphone.holdStop { await stop.wait() }
        controller.toggle(using: dependencies)
        try await eventually { controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        controller.toggle(using: dependencies)
        let stopping = await TestPolling.untilAsync { await harness.microphone.stops > 0 }
        #expect(stopping)

        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)

        #expect(!controller.isActive)
        #expect(controller.recoveryText == harness.text)
        #expect(coordinator.holdsLease)
        #expect(coordinator.admission.refusalNow() == .busy)
        #expect(harness.insertions.isEmpty)
        stop.open()
        try await eventually { !coordinator.holdsLease }
        #expect(harness.insertions.isEmpty)
    }

    @Test
    func anIdleUpdateBlocksNewWorkUntilItsCycleFinishes() throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        var resumed = 0

        #expect(!coordinator.postponeUpdateRelaunch { resumed += 1 })

        #expect(resumed == 0)
        #expect(coordinator.admission.refusalNow() == .busy)
        #expect(coordinator.admission.refusalNow(for: .practice) == .busy)
        #expect(!coordinator.admission.isEligible())
        coordinator.finishUpdateCycle()
        coordinator.finishUpdateCycle()
        #expect(coordinator.admission.isEligible())
        let lease = try acquire(coordinator)
        lease.release()
    }

    @Test
    func anUpdateWaitsForClipboardRestorationAndKeepsAdmissionClosedWhileResuming() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let lease = try acquire(coordinator)
        let (gate, finished) = try await waitOnClipboard(lease, scratch: scratch)
        defer { gate.release(); coordinator.finishUpdateCycle() }
        var resumed = 0
        var refusedDuringResume: DictationAdmissionRefusal?

        #expect(coordinator.postponeUpdateRelaunch {
            resumed += 1
            refusedDuringResume = coordinator.admission.refusalNow()
        })

        #expect(lease.revalidate())
        #expect(resumed == 0)
        #expect(coordinator.admission.refusalNow() == .busy)
        #expect(coordinator.admission.refusalNow(for: .practice) == .busy)
        gate.release()
        await finished.value
        #expect(resumed == 1)
        #expect(refusedDuringResume == .busy)
        #expect(coordinator.admission.refusalNow() == .busy)
        lease.release()
        #expect(resumed == 1)
        coordinator.finishUpdateCycle()
        #expect(coordinator.admission.refusalNow() == nil)
    }

    @Test(arguments: [false, true])
    func anUpdateWaitsForEverySharedHolder(newestFirst: Bool) async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let first = try acquire(coordinator)
        let firstRestore = try await waitOnClipboard(first, scratch: scratch)
        let second = try acquire(coordinator)
        let secondRestore = try await waitOnClipboard(second, scratch: scratch)
        defer {
            firstRestore.gate.release()
            secondRestore.gate.release()
            coordinator.finishUpdateCycle()
        }
        var resumed = 0
        #expect(coordinator.postponeUpdateRelaunch { resumed += 1 })

        let earlier = newestFirst ? secondRestore : firstRestore
        let later = newestFirst ? firstRestore : secondRestore
        earlier.gate.release()
        await earlier.finished.value

        #expect(resumed == 0)
        #expect(coordinator.holdsLease)
        later.gate.release()
        await later.finished.value
        #expect(resumed == 1)
        #expect(!coordinator.holdsLease)
    }

    @Test
    func aFinishedUpdateCycleDropsItsCallbackBeforeANewCycle() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let lease = try acquire(coordinator)
        var obsolete = 0
        var current = 0
        #expect(coordinator.postponeUpdateRelaunch { obsolete += 1 })

        coordinator.finishUpdateCycle()
        coordinator.finishUpdateCycle()
        #expect(coordinator.postponeUpdateRelaunch { current += 1 })
        await lease.releaseAfterDelivery()

        #expect(obsolete == 0)
        #expect(current == 1)
        coordinator.finishUpdateCycle()
        #expect(coordinator.admission.refusalNow() == nil)
    }

    @Test
    func abortingAnUpdateDoesNotResumeOnALateLeaseRelease() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let lease = try acquire(coordinator)
        var resumed = 0
        #expect(coordinator.postponeUpdateRelaunch { resumed += 1 })

        coordinator.finishUpdateCycle()
        await lease.releaseAfterDelivery()

        #expect(resumed == 0)
        #expect(coordinator.admission.refusalNow() == nil)
    }

    @Test
    func anUpdateLetsTheCurrentDictationFinishAndWaitsForItsNativeStop() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        var dependencies = harness.dependencies
        dependencies.admission = coordinator.admission
        let stop = StopGate()
        defer { stop.open(); harness.controller.cancel(); coordinator.finishUpdateCycle() }
        await harness.microphone.holdStop { await stop.wait() }
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        var resumed = 0

        #expect(coordinator.postponeUpdateRelaunch { resumed += 1 })
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)

        let stopping = await TestPolling.untilAsync { await harness.microphone.stops > 0 }
        #expect(stopping)
        #expect(resumed == 0)
        #expect(coordinator.holdsLease)
        #expect(harness.insertions.isEmpty)
        stop.open()
        try await eventually { resumed == 1 }
        #expect(harness.insertions == [harness.text])
        #expect(!coordinator.holdsLease)
        #expect(coordinator.admission.refusalNow() == .busy)
    }

    enum RecoveryResolution: CaseIterable { case copy, discard }

    @Test(arguments: RecoveryResolution.allCases)
    func anUpdateWaitsUntilUndeliveredWordsAreResolved(_ resolution: RecoveryResolution) async throws {
        let scratch = Scratch()
        let pendingWrites = DictationPendingWrites()
        let coordinator = scratch.coordinator(pendingWrites: pendingWrites)
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        var dependencies = harness.dependencies
        dependencies.admission = coordinator.admission
        dependencies.pendingWrites = pendingWrites
        dependencies.captureDestination = { .unavailable(name: nil, result: .targetChanged) }
        dependencies.copyText = { _ in true }
        defer { harness.controller.cancel(); coordinator.finishUpdateCycle() }
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        var resumed = 0

        #expect(coordinator.postponeUpdateRelaunch { resumed += 1 })
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)

        try await eventually { harness.controller.phase == .recovery(.targetChanged) && !coordinator.holdsLease }
        await Task.yield()
        #expect(resumed == 0)
        #expect(harness.controller.recoveryText == harness.text)
        harness.controller.retryUndeliveredText()
        #expect(resumed == 0)
        switch resolution {
        case .copy:
            harness.controller.copyPendingText()
            #expect(harness.controller.copyStatus == .copied)
        case .discard:
            harness.controller.cancel()
        }
        try await eventually { resumed == 1 }
        harness.controller.cancel()
        #expect(resumed == 1)
    }

    @Test
    func theFeatureRoutesUpdateCallbacksToItsAdmissionCoordinator() async throws {
        let suite = "update-feature-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let feature = try disposableFeature(defaults)
        let admission = feature.dictationAdmission
        let lease = try admission.acquire(.practice).get()
        var resumed = 0

        #expect(feature.postponeUpdateRelaunch { resumed += 1 })
        #expect(admission.refusalNow(for: .practice) == .busy)
        await lease.releaseAfterDelivery()

        #expect(resumed == 1)
        feature.finishUpdateCycle()
        #expect(admission.refusalNow(for: .practice) == nil)
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
    func aHeldTriggerKeepsItsWordsWhenAHandoffDisarmsIt() async throws {
        let suite = "secreteo-ownership-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let feature = try disposableFeature(defaults)
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.handoffGrace = .seconds(3_600)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.modifierTrigger.ownsSession = true
        harness.controller.ownershipIntentSeen()

        harness.controller.syncModifierPTT(services: feature)

        try await eventually { harness.controller.phase == .recovery(.ownershipChanged) }
        #expect(harness.controller.recoveryText == harness.text)
        #expect(harness.insertions.isEmpty)
    }

    @Test
    func aHeldTriggerStillCancelsWhenItIsDisabledWithNoHandoff() async throws {
        let suite = "secreteo-ownership-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let feature = try disposableFeature(defaults)
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        harness.controller.toggle(using: harness.dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.controller.modifierTrigger.ownsSession = true

        harness.controller.syncModifierPTT(services: feature)

        #expect(harness.controller.phase == .idle)
    }

    private func previewRewrite(
        admission: DictationAdmission, insertions: @escaping (String) -> Void
    ) async throws -> SelectionRewriteController {
        let controller = SelectionRewriteController(presentsPanel: false)
        controller.start(using: SelectionRewriteController.Dependencies(
            admission: admission,
            capture: {
                .success(CapturedSelection(
                    text: "so we ship it tomorrow", source: .accessibility, applicationName: "Receiver",
                    revalidate: { nil },
                    destination: CapturedDictationDestination(name: "Receiver", canRetry: false) { text in
                        insertions(text)
                        return .verified
                    }))
            },
            polish: { text, _, _ in .polished(text.uppercased()) },
            recipes: { [] }, protectedTerms: { [] }, copyText: { _ in true },
            wait: { _ in try await Task.sleep(for: .seconds(3_600)) }))
        try await eventually { controller.phase == .choosing }
        controller.choose(nil)
        try await eventually { controller.phase == .preview("SO WE SHIP IT TOMORROW") }
        return controller
    }

    @Test
    func aHandoffCompletesWithARewritePreviewOpenAndTheReplaceIsRefused() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        var inserted: [String] = []
        let rewrite = try await previewRewrite(admission: coordinator.admission) { inserted.append($0) }
        defer { rewrite.cancel() }

        let outcome = await scratch.participant(Self.other).takeOwnership(userConfirmed: true, triggers: Triggers())

        #expect(outcome == .completed(generation: 2))
        rewrite.replace()
        guard case .failed = rewrite.phase else {
            Issue.record("A replace went through for a former owner")
            return
        }
        #expect(inserted.isEmpty)
        #expect(rewrite.result == "SO WE SHIP IT TOMORROW")
    }

    @Test
    func aHandoffThereAndBackWithARewritePreviewOpenRefusesTheReplace() async throws {
        let scratch = Scratch()
        let coordinator = scratch.coordinator()
        var inserted: [String] = []
        let rewrite = try await previewRewrite(admission: coordinator.admission) { inserted.append($0) }
        defer { rewrite.cancel() }
        let secreteo = try #require(scratch.lastOwnership)
        #expect(await scratch.participant(Self.other)
            .takeOwnership(userConfirmed: true, triggers: Triggers()) == .completed(generation: 2))
        #expect(await secreteo.takeOwnership(userConfirmed: true, triggers: Triggers()) == .completed(generation: 3))

        rewrite.replace()

        guard case .failed = rewrite.phase else {
            Issue.record("A replace went through across a handoff there and back")
            return
        }
        #expect(inserted.isEmpty)
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


    @Test
    func aRewriteReplaceIsRefusedAfterAHandoffThereAndBack() async throws {
        var generation = 1
        var insertions: [String] = []
        let dependencies = SelectionRewriteController.Dependencies(
            admission: DictationAdmission(
                acquire: { _ in .success(DictationLease(generation: generation)) }, isEligible: { true }),
            capture: {
                .success(CapturedSelection(
                    text: "so we ship it tomorrow", source: .accessibility, applicationName: "Receiver",
                    revalidate: { nil },
                    destination: CapturedDictationDestination(name: "Receiver", canRetry: false) { text in
                        insertions.append(text)
                        return .verified
                    }))
            },
            polish: { text, _, _ in .polished(text.uppercased()) },
            recipes: { [] }, protectedTerms: { [] }, copyText: { _ in true },
            wait: { _ in try await Task.sleep(for: .seconds(3_600)) })
        let controller = SelectionRewriteController(presentsPanel: false)
        defer { controller.cancel() }
        controller.start(using: dependencies)
        try await eventually { controller.phase == .choosing }
        controller.choose(nil)
        try await eventually { controller.phase == .preview("SO WE SHIP IT TOMORROW") }
        generation = 3

        controller.replace()

        guard case .failed = controller.phase else {
            Issue.record("A replace went through after the owner changed")
            return
        }
        #expect(insertions.isEmpty)
        #expect(controller.result == "SO WE SHIP IT TOMORROW")
    }
}
