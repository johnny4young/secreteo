import XCTest

@testable import DictationSession

@MainActor
extension DictationControllerTests {
    func testAMicrophoneNoticeOpensTheFullStrip() async {
        let harness = DictationControllerHarness(text: "Send the report.")
        defer {
            harness.controller.cancel()
            harness.defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        }
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
        let noticed = await TestPolling.until { harness.controller.microphoneNotice != nil }
        XCTAssertTrue(noticed)
        XCTAssertFalse(DictationCompactIndicator.applies(to: harness.controller), "the notice needs the full strip")
    }
}
