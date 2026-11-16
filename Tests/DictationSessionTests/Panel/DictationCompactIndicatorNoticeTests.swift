import XCTest

@testable import DictationSession

@MainActor
extension DictationControllerTests {
    func testAMicrophoneNoticeOpensTheFullStrip() async {
        isolateArgumentDomain()
        let harness = DictationControllerHarness(text: "Send the report.")
        defer { harness.controller.cancel() }
        harness.set(true, forKey: DictationCompactIndicator.defaultsKey)

        harness.controller.toggle(using: harness.dependencies)
        let listening = await TestPolling.until { harness.controller.phase == .listening }
        XCTAssertTrue(listening)
        XCTAssertTrue(DictationCompactIndicator.applies(to: harness.controller), "the preferred microphone shrinks")
        harness.controller.cancel()

        var fallback = harness.dependencies
        fallback.makeMicrophone = { [microphone = harness.microphone] in
            var input = DictationSessionDependencies.Microphone(
                source: ControlledMicrophoneSession(microphone), warmUp: {})
            input.usesSystemFallback = true
            return input
        }
        harness.controller.toggle(using: fallback)
        let fellBack = await TestPolling.until { harness.controller.phase == .listening }
        XCTAssertTrue(fellBack)
        XCTAssertNotNil(harness.controller.microphoneNotice)
        XCTAssertTrue(DictationCompactIndicator.applies(to: harness.controller.phase), "only the notice keeps it full")
        XCTAssertFalse(DictationCompactIndicator.applies(to: harness.controller), "the notice needs the full strip")
    }

    func testAClickOnTheIndicatorOpensTheCapsuleForThatDictationOnly() async {
        isolateArgumentDomain()
        let harness = DictationControllerHarness(text: "Send the report.")
        defer { harness.controller.cancel() }
        harness.set(true, forKey: DictationCompactIndicator.defaultsKey)

        harness.controller.expandCompactIndicator()
        XCTAssertFalse(harness.controller.compactIndicatorExpanded, "nothing to open while idle")

        harness.controller.toggle(using: harness.dependencies)
        let listening = await TestPolling.until { harness.controller.phase == .listening }
        XCTAssertTrue(listening)
        XCTAssertEqual(DictationPanelLayout.size(for: harness.controller), NSSize(width: 38, height: 32))
        harness.controller.expandCompactIndicator()
        XCTAssertFalse(DictationCompactIndicator.applies(to: harness.controller))
        XCTAssertEqual(DictationPanelLayout.size(for: harness.controller).width, DictationPanelLayout.width)
        XCTAssertNil(DictationCompactIndicator.dismissal(for: harness.controller))
        harness.controller.cancel()

        harness.controller.toggle(using: harness.dependencies)
        let again = await TestPolling.until { harness.controller.phase == .listening }
        XCTAssertTrue(again)
        XCTAssertTrue(DictationCompactIndicator.applies(to: harness.controller), "the next dictation is small again")
    }
}
