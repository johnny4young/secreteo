import Foundation
import Testing

@testable import DictationSession

/// The meter redraws every frame, and a slow window server blocks the main thread on each
/// one, so it must stop the moment Stop is pressed and leave the main thread to delivery.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct DictationMeterTests {
    @Test
    func theMeterFollowsTheOpenMicrophoneAndFreezesAtStop() async throws {
        let harness = DictationControllerHarness(text: "no borres estas notas")
        defer { harness.controller.cancel() }
        let tail = ControlledTestSleep()
        harness.waitForStopTail = { try await tail.wait(for: $0) }
        #expect(!DictationWaveform.animates(for: harness.controller))

        harness.controller.toggle(using: harness.dependencies)
        try #require(await TestPolling.until { harness.controller.partialText == harness.text })
        #expect(DictationWaveform.animates(for: harness.controller))

        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: harness.dependencies)
        #expect(await tail.waitUntilCallCount(1))
        #expect(harness.controller.phase == .listening, "the stop tail is still capturing")
        #expect(!DictationWaveform.animates(for: harness.controller))
        _ = await tail.resumeCall(at: 0)
    }
}
