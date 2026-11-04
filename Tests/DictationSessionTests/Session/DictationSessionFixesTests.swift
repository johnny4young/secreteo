import DictationKit
import Foundation
import XCTest

@testable import DictationSession

@MainActor
final class DictationSessionFixesTests: XCTestCase {
    private struct CaptureBroke: Error {}

    private final class FakeCancelKey: GlobalHotkeyRegistration {
        var unregistered = false
        func unregister() { unregistered = true }
    }

    private func finish(_ harness: DictationControllerHarness, _ dependencies: DictationSessionDependencies) async {
        harness.controller.toggle(using: dependencies)
        let heard = await TestPolling.until { harness.controller.partialText == harness.text }
        XCTAssertTrue(heard)
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)
    }

    private func hasFailed(_ harness: DictationControllerHarness) async -> Bool {
        await TestPolling.until {
            if case .failed = harness.controller.phase { return true }
            return false
        }
    }

    private func correcting(
        _ harness: DictationControllerHarness, receiver: DictationFixtureReceiver
    ) -> DictationSessionDependencies {
        harness.defaults.set(true, forKey: DictationCorrections.defaultsKey)
        var dependencies = harness.dependencies
        dependencies.captureDestination = {
            var destination = CapturedDictationDestination(name: "Receiver", canRetry: true) { receiver.insert($0) }
            destination.lastInsertion = { receiver.last }
            return destination
        }
        return dependencies
    }

    func testASessionCancelledDuringTheSpeechVerdictCorrectsNothing() async {
        let inserted = "ship it on friday"
        let receiver = DictationFixtureReceiver()
        let first = DictationControllerHarness(text: inserted)
        defer { first.controller.cancel() }
        await finish(first, correcting(first, receiver: receiver))
        let delivered = await TestPolling.until { !first.controller.isActive }
        XCTAssertTrue(delivered)
        XCTAssertEqual(receiver.text, inserted)

        let command = DictationControllerHarness(text: "change friday to monday", controller: first.controller)
        var dependencies = correcting(command, receiver: receiver)
        dependencies.makeSpeechGate = {
            DictationSpeechGate(load: {
                try await Task.sleep(for: .seconds(30))
                return { _ in false }
            })
        }
        var ended = false
        dependencies.admission = DictationAdmission(
            acquire: { _ in .success(DictationLease(end: { ended = true })) }, isEligible: { true })
        await finish(command, dependencies)
        let delivering = await TestPolling.until { command.controller.phase == .delivering }
        XCTAssertTrue(delivering)

        command.controller.cancel()
        let settled = await TestPolling.until { ended }

        XCTAssertTrue(settled)
        XCTAssertEqual(receiver.text, inserted)
    }

    func testAnOldTransformLeavesTheNewSessionsEscapeAlone() async {
        let first = DictationControllerHarness(text: "so we ship it tomorrow")
        defer { first.controller.cancel() }
        first.defaults.set(DictationTextMode.polish.rawValue, forKey: DictationTextPreferences.modeKey)
        var keys: [FakeCancelKey] = []
        let register: (@escaping () -> Void) -> (any GlobalHotkeyRegistration)? = { _ in
            let key = FakeCancelKey()
            keys.append(key)
            return key
        }
        var polishing = first.dependencies
        polishing.registerCancelKey = register
        polishing.polishDictation = { _, _, _ in
            try? await Task.sleep(for: .seconds(30))
            return .kept(.failed)
        }
        await finish(first, polishing)
        let isPolishing = await TestPolling.until { first.controller.isPolishing }
        XCTAssertTrue(isPolishing)

        first.controller.cancel()
        let next = DictationControllerHarness(text: "next words", controller: first.controller)
        var nextDependencies = next.dependencies
        nextDependencies.registerCancelKey = register
        first.controller.toggle(using: nextDependencies)
        let listening = await TestPolling.until { first.controller.partialText == next.text }

        XCTAssertTrue(listening)
        XCTAssertEqual(keys.last?.unregistered, false)
    }

    func testACaptureFailureKeepsTheWordsForCopyAndPasteLast() async {
        let text = "No borres estas notas"
        let harness = DictationControllerHarness(text: text)
        defer { harness.controller.cancel() }
        var copied: [String] = []
        var dependencies = harness.dependencies
        dependencies.copyText = {
            copied.append($0)
            return true
        }
        harness.controller.toggle(using: dependencies)
        let heard = await TestPolling.until { harness.controller.partialText == text }
        XCTAssertTrue(heard)

        await harness.microphone.fail(CaptureBroke())
        let failed = await hasFailed(harness)
        XCTAssertTrue(failed)
        harness.controller.copyPendingText()

        XCTAssertTrue(harness.insertions.isEmpty)
        XCTAssertEqual(harness.controller.recoveryText, text)
        XCTAssertEqual(harness.controller.lastText.current, text)
        XCTAssertEqual(copied, [text])
    }

    func testAFailureThatKeptWordsCanBeClosedAndPasteLastStillHasThem() async {
        let text = "No borres estas notas"
        let harness = DictationControllerHarness(text: text)
        defer { harness.controller.cancel() }
        harness.controller.toggle(using: harness.dependencies)
        let heard = await TestPolling.until { harness.controller.partialText == text }
        XCTAssertTrue(heard)
        await harness.microphone.fail(CaptureBroke())
        let failed = await hasFailed(harness)
        XCTAssertTrue(failed)

        harness.controller.dismissFeedback()

        XCTAssertEqual(harness.controller.phase, .idle)
        XCTAssertEqual(harness.controller.recoveryText, "")
        XCTAssertEqual(harness.controller.lastText.current, text)
    }

    func testAFailureWithNoWordsIsNotDismissedAsIfItHadThem() async {
        let harness = DictationControllerHarness(text: "words that never arrive")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.authorizeMicrophone = { false }
        harness.controller.toggle(using: dependencies)
        let failed = await hasFailed(harness)
        XCTAssertTrue(failed)

        harness.controller.dismissFeedback()

        let stillFailed = await hasFailed(harness)
        XCTAssertTrue(stillFailed)
    }

    func testACaptureFailureBeforeAnyWordsKeepsNothing() async {
        let harness = DictationControllerHarness(text: "")
        defer { harness.controller.cancel() }
        harness.controller.toggle(using: harness.dependencies)
        let listening = await TestPolling.until { harness.controller.phase == .listening }
        XCTAssertTrue(listening)

        await harness.microphone.fail(CaptureBroke())
        let failed = await hasFailed(harness)

        XCTAssertTrue(failed)
        XCTAssertEqual(harness.controller.recoveryText, "")
        XCTAssertNil(harness.controller.lastText.current)
    }

    func testAnInternalSessionsWordsNeverReachPasteLast() async {
        let text = "make it shorter"
        let harness = DictationControllerHarness(text: text)
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.deliversInternally = true
        harness.controller.toggle(using: dependencies)
        let heard = await TestPolling.until { harness.controller.partialText == text }
        XCTAssertTrue(heard)

        await harness.microphone.fail(CaptureBroke())
        let failed = await hasFailed(harness)

        XCTAssertTrue(failed)
        XCTAssertEqual(harness.controller.recoveryText, "")
        XCTAssertNil(harness.controller.lastText.current)
    }

    func testAnEngineFailureWithWordsStaysUntilTheUserActs() async {
        struct EngineBroke: Error {}
        let text = "No borres estas notas"
        let harness = DictationControllerHarness(text: text)
        defer { harness.controller.cancel() }
        var scheduledDismissal = false
        var dependencies = harness.dependencies
        dependencies.waitForFeedbackDismissal = { _ in scheduledDismissal = true }
        harness.controller.toggle(using: dependencies)
        let heard = await TestPolling.until { harness.controller.partialText == text }
        XCTAssertTrue(heard)

        harness.transcriptOutput?.finish(throwing: EngineBroke())
        let failed = await hasFailed(harness)
        await Task.yield()

        XCTAssertTrue(failed)
        XCTAssertFalse(scheduledDismissal)
        XCTAssertEqual(harness.controller.recoveryText, text)
    }

    func testClearingTheLastTextClearsTheSessionsCopies() async {
        let text = "synthetic words"
        let last = DictationLastText(observesSystem: false)
        let harness = DictationControllerHarness(
            text: text, controller: DictationController(presentsPanel: false, lastText: last))
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.beginHistory = { { _ in true } }
        await finish(harness, dependencies)
        let delivered = await TestPolling.until { harness.insertions == [text] && !harness.controller.isActive }
        XCTAssertTrue(delivered)
        XCTAssertEqual(harness.controller.confirmedText, text)
        XCTAssertEqual(harness.controller.history?.hasDraft, true)

        last.clear()

        XCTAssertEqual(harness.controller.confirmedText, "")
        XCTAssertEqual(harness.controller.partialText, "")
        XCTAssertEqual(harness.controller.history?.hasDraft, false)
    }

    func testClearingTheLastTextLeavesALiveSessionsWords() async {
        let text = "synthetic words"
        let last = DictationLastText(observesSystem: false)
        let harness = DictationControllerHarness(
            text: text, controller: DictationController(presentsPanel: false, lastText: last))
        defer { harness.controller.cancel() }
        harness.controller.toggle(using: harness.dependencies)
        let heard = await TestPolling.until { harness.controller.partialText == text }
        XCTAssertTrue(heard)

        last.clear()

        XCTAssertEqual(harness.controller.partialText, text)
    }

    func testClosingANoticeDuringAReplayLeavesPasteLastWorking() async {
        let text = "synthetic words"
        let harness = DictationControllerHarness(text: text)
        defer { harness.controller.cancel() }
        await finish(harness, harness.dependencies)
        let delivered = await TestPolling.until { harness.insertions == [text] && !harness.controller.isActive }
        XCTAssertTrue(delivered)

        var release: CheckedContinuation<Void, Never>?
        var held = harness.dependencies
        held.captureDestination = {
            CapturedDictationDestination(name: "Receiver", canRetry: true) { _ in
                await withCheckedContinuation { release = $0 }
                return .dispatched
            }
        }
        harness.controller.pasteLastDictation(using: held)
        let holding = await TestPolling.until { release != nil }
        XCTAssertTrue(holding)
        harness.controller.dismissFeedback()
        release?.resume()
        let freed = await TestPolling.until { harness.controller.retryDeliveryTask == nil }
        XCTAssertTrue(freed)

        harness.controller.pasteLastDictation(using: harness.dependencies)
        let pasted = await TestPolling.until { harness.insertions == [text, text] }

        XCTAssertTrue(pasted)
    }
}
