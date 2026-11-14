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
}
