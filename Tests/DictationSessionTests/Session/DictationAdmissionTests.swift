import AppKit
import DictationOwnership
import Foundation
import DictationKit
import LiveSpeech
import SpeechCore
import Testing

@testable import DictationSession

// The controller harness overrides process-wide NSArgumentDomain.
@Suite(.serialized, .exclusiveArgumentDomain, .timeLimit(.minutes(1)))
@MainActor
struct DictationAdmissionTests {
    @MainActor
    private final class Port {
        var refuses = false
        var kinds: [DictationAdmissionKind] = []
        var released = 0
        var settle: () async -> Void = {}
        var held: Int { kinds.count - released }

        var admission: DictationAdmission {
            DictationAdmission(
                acquire: { kind in
                    guard !self.refuses else { return .failure(.dictationOff) }
                    self.kinds.append(kind)
                    return .success(DictationLease(settle: { await self.settle() }, end: { self.released += 1 }))
                },
                isEligible: { !self.refuses })
        }
    }

    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        _ = await TestPolling.until(condition)
        try #require(condition())
    }

    private func dictate(
        _ harness: DictationControllerHarness, _ dependencies: DictationSessionDependencies
    ) async throws {
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)
    }

    private func dependencies(_ harness: DictationControllerHarness, _ port: Port) -> DictationSessionDependencies {
        var dependencies = harness.dependencies
        dependencies.admission = port.admission
        return dependencies
    }

    @Test
    func thePreferenceAdmitsGlobalWorkAndPracticeAlwaysRuns() throws {
        let suite = "dictation-admission-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let admission = DictationAdmission.preference(in: defaults)

        #expect(throws: DictationAdmissionRefusal.dictationOff) { try admission.acquire(.global).get() }
        #expect(!admission.isEligible())
        #expect(throws: Never.self) { try admission.acquire(.practice).get() }
        #expect(defaults.object(forKey: DictationController.defaultsKey) == nil, "A refusal writes nothing")

        defaults.set(true, forKey: DictationController.defaultsKey)
        #expect(throws: Never.self) { try admission.acquire(.global).get() }
        #expect(admission.isEligible())
    }

    @Test
    func aRefusedStartOpensNothing() async {
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        let port = Port()
        port.refuses = true

        harness.controller.toggle(using: dependencies(harness, port))

        #expect(harness.controller.phase == .idle)
        #expect(harness.loads == 0)
        let starts = await harness.microphone.starts
        #expect(starts == 0)
        #expect(harness.insertions.isEmpty)
    }

    @Test
    func aReleaseAfterARefusedPressDoesNothing() {
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        let port = Port()
        port.refuses = true
        let dependencies = dependencies(harness, port)

        harness.controller.handleHotkeyPress(using: dependencies, at: harness.now)
        harness.controller.handleHotkeyRelease(at: harness.now.addingTimeInterval(5))

        #expect(harness.controller.phase == .idle)
        #expect(harness.insertions.isEmpty)
    }

    @Test
    func theLeaseLastsThroughDelivery() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        let port = Port()
        var dependencies = dependencies(harness, port)
        var heldWhileDelivering: [Int] = []
        dependencies.captureDestination = {
            CapturedDictationDestination(name: "Receiver", canRetry: false) { _ in
                heldWhileDelivering.append(port.held)
                return .verified
            }
        }

        try await dictate(harness, dependencies)

        try await eventually { heldWhileDelivering == [1] && port.held == 0 }
        #expect(port.kinds == [.global])
    }

    @Test
    func aRefusedModifierPressOwnsNothing() {
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        let port = Port()
        port.refuses = true
        let dependencies = dependencies(harness, port)

        harness.controller.handleModifier(.press) { harness.controller.toggle(using: dependencies) }

        #expect(!harness.controller.modifierTrigger.ownsSession)
        #expect(harness.controller.phase == .idle)
    }

    @Test
    func theLeaseOutlastsTheClipboardRestoreWithoutDelayingTheResult() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        let port = Port()
        let restore = PreparationGate()
        port.settle = { await restore.wait() }

        try await dictate(harness, dependencies(harness, port))

        try await eventually { restore.started && harness.insertions.count == 1 }
        #expect(!harness.controller.isActive)
        #expect(port.held == 1)
        restore.release()
        try await eventually { port.held == 0 }
    }

    @Test
    func aCancelledCallerCannotCutTheRestoreShort() async throws {
        let restore = PreparationGate()
        var settleWasCancelled = false
        var released = false
        let lease = DictationLease(
            settle: {
                await restore.wait()
                settleWasCancelled = Task.isCancelled
            },
            end: { released = true })
        let release = Task { await lease.releaseAfterDelivery() }
        try await eventually { restore.started }

        release.cancel()
        restore.release()
        await release.value

        #expect(!settleWasCancelled)
        #expect(released)
    }

    @Test
    func theLeaseEndsOnlyAfterTheRealClipboardIsBack() async throws {
        let board = NSPasteboard(name: .init("com.johnny4young.secreteo.admission.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("mine", forType: .string)
        let clipboard = DictationClipboard.shared
        let loan = try #require(clipboard.borrow("dictated", on: board))
        clipboard.restoreLater(loan, on: board, after: .milliseconds(50))
        var contentsAtRelease: String?
        let lease = DictationLease(
            settle: { _ = await clipboard.waitForRestoration(on: board) },
            end: { contentsAtRelease = board.string(forType: .string) })

        await lease.releaseAfterDelivery()

        #expect(contentsAtRelease == "mine")
    }

    @Test
    func aCancelledSessionReleasesItsLease() async throws {
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        let port = Port()
        let dependencies = dependencies(harness, port)
        harness.controller.toggle(using: dependencies)
        try await eventually { harness.controller.partialText == harness.text }
        #expect(port.held == 1)

        harness.controller.cancel()

        try await eventually { port.held == 0 }
        #expect(harness.insertions.isEmpty)
    }

    @Test
    func aMissingPermissionReleasesTheLease() {
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        let port = Port()
        var dependencies = dependencies(harness, port)
        dependencies.canInsert = { false }

        harness.controller.toggle(using: dependencies)

        #expect(port.kinds == [.global])
        #expect(port.held == 0)
        harness.controller.cancel()
    }

    @Test
    func aRefusedRetryKeepsTheWordsAndAnAdmittedOneDelivers() async throws {
        let harness = DictationControllerHarness(text: "No borres estas notas.")
        defer { harness.controller.cancel() }
        let port = Port()
        var dependencies = dependencies(harness, port)
        var accepts = false
        var delivered: [String] = []
        dependencies.captureDestination = {
            CapturedDictationDestination(name: "Receiver", canRetry: true) { text in
                guard accepts else { return .refused(.targetChanged) }
                delivered.append(text)
                return .verified
            }
        }
        try await dictate(harness, dependencies)
        try await eventually { harness.controller.phase == .recovery(.targetChanged) }
        try await eventually { port.held == 0 }
        accepts = true
        port.refuses = true

        harness.controller.retryUndeliveredText()

        #expect(harness.controller.phase == .recovery(.targetChanged))
        #expect(harness.controller.recoveryText == harness.text)
        #expect(!harness.controller.isRetryingDelivery)
        #expect(delivered.isEmpty)

        port.refuses = false
        harness.controller.retryUndeliveredText()

        try await eventually { delivered == [harness.text] && port.held == 0 }
    }

    @Test
    func aRefusedPasteLastKeepsTheTextAndAnAdmittedOneReleases() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        let port = Port()
        let dependencies = dependencies(harness, port)
        try await dictate(harness, dependencies)
        try await eventually { harness.insertions.count == 1 && !harness.controller.isActive && port.held == 0 }
        port.refuses = true

        harness.controller.pasteLastDictation(using: dependencies)

        #expect(!harness.controller.isRetryingDelivery)
        #expect(harness.insertions.count == 1)
        #expect(harness.controller.hasPastableText)

        port.refuses = false
        harness.controller.pasteLastDictation(using: dependencies)

        try await eventually { harness.insertions.count == 2 && port.held == 0 }
    }

    @Test
    func aReplayHoldsItsLeaseThroughTheClipboardRestore() async throws {
        let harness = DictationControllerHarness(text: "So we ship it tomorrow.")
        defer { harness.controller.cancel() }
        let port = Port()
        let dependencies = dependencies(harness, port)
        try await dictate(harness, dependencies)
        try await eventually { harness.insertions.count == 1 && !harness.controller.isActive && port.held == 0 }
        let restore = PreparationGate()
        port.settle = { await restore.wait() }

        harness.controller.pasteLastDictation(using: dependencies)

        try await eventually { harness.insertions.count == 2 && restore.started }
        #expect(port.held == 1)
        restore.release()
        try await eventually { port.held == 0 }
    }

    // MARK: Rewrite

    @MainActor
    private final class RewriteRecorder {
        var captures = 0
        var insertions: [String] = []
        var heldWhileCapturing: [Int] = []
        var heldWhileReplacing: [Int] = []
    }

}
