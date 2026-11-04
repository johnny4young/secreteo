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
        _ = await TestPolling.until { harness.controller.partialText == harness.text }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)
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
        _ = await TestPolling.until { !first.controller.isActive }
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
        _ = await TestPolling.until { command.controller.phase == .delivering }

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
        _ = await TestPolling.until { first.controller.isPolishing }

        first.controller.cancel()
        let next = DictationControllerHarness(text: "next words", controller: first.controller)
        var nextDependencies = next.dependencies
        nextDependencies.registerCancelKey = register
        first.controller.toggle(using: nextDependencies)
        _ = await TestPolling.until { first.controller.partialText == next.text }

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
        _ = await TestPolling.until { harness.controller.partialText == text }

        await harness.microphone.fail(CaptureBroke())
        _ = await TestPolling.until {
            if case .failed = harness.controller.phase { return true }
            return false
        }
        harness.controller.copyPendingText()

        XCTAssertTrue(harness.insertions.isEmpty)
        XCTAssertEqual(harness.controller.recoveryText, text)
        XCTAssertEqual(harness.controller.lastText.current, text)
        XCTAssertEqual(copied, [text])
    }

    func testAFailureBeforeAnyWordsKeepsNothing() async {
        let harness = DictationControllerHarness(text: "words that never arrive")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.authorizeMicrophone = { false }

        harness.controller.toggle(using: dependencies)
        _ = await TestPolling.until {
            if case .failed = harness.controller.phase { return true }
            return false
        }

        XCTAssertEqual(harness.controller.recoveryText, "")
        XCTAssertNil(harness.controller.lastText.current)
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
        _ = await TestPolling.until { harness.insertions == [text] && !harness.controller.isActive }
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
        _ = await TestPolling.until { harness.controller.partialText == text }

        last.clear()

        XCTAssertEqual(harness.controller.partialText, text)
    }

    func testClosingANoticeDuringAReplayLeavesPasteLastWorking() async {
        let text = "synthetic words"
        let harness = DictationControllerHarness(text: text)
        defer { harness.controller.cancel() }
        await finish(harness, harness.dependencies)
        _ = await TestPolling.until { harness.insertions == [text] && !harness.controller.isActive }

        var release: CheckedContinuation<Void, Never>?
        var holding = harness.dependencies
        holding.captureDestination = {
            CapturedDictationDestination(name: "Receiver", canRetry: true) { _ in
                await withCheckedContinuation { release = $0 }
                return .dispatched
            }
        }
        harness.controller.pasteLastDictation(using: holding)
        _ = await TestPolling.until { release != nil }
        harness.controller.dismissFeedback()
        release?.resume()
        let freed = await TestPolling.until { harness.controller.retryDeliveryTask == nil }
        XCTAssertTrue(freed)

        harness.controller.pasteLastDictation(using: harness.dependencies)
        let pasted = await TestPolling.until { harness.insertions == [text, text] }

        XCTAssertTrue(pasted)
    }
}
