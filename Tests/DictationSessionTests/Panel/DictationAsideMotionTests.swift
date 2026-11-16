import AppKit
import Foundation
import SwiftUI
import Testing

@testable import DictationSession

/// The small indicator follows the capsule's rule: once the microphone closes, nothing animates.
// The controller harness overrides process-wide NSArgumentDomain, so the suite is serialized.
@Suite(.serialized, .exclusiveArgumentDomain, .timeLimit(.minutes(1)))
@MainActor
struct DictationAsideMotionTests {
    @Test
    func theSmallIndicatorAnimatesNothingAndStopsItsClockAtStop() async throws {
        let harness = DictationControllerHarness(text: "no borres estas notas")
        defer { harness.controller.cancel() }
        let tail = ControlledTestSleep()
        harness.waitForStopTail = { try await tail.wait(for: $0) }
        harness.set(true, forKey: DictationCompactIndicator.defaultsKey)

        harness.controller.toggle(using: harness.dependencies)
        try #require(await TestPolling.until { harness.controller.partialText == harness.text })
        #expect(DictationCompactIndicator.applies(to: harness.controller))
        var open = DictationWaveform.animates(for: harness.controller)
        #expect(DictationCapsuleMotion.indicatorChange(microphoneIsOpen: open, duration: 0.2) != nil)

        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: harness.dependencies)
        #expect(await tail.waitUntilCallCount(1))
        open = DictationWaveform.animates(for: harness.controller)
        #expect(!open)
        #expect(
            DictationCapsuleMotion.indicatorChange(
                microphoneIsOpen: open, duration: DictationCompactIndicator.faceChange) == nil,
            "the face changes unanimated")
        #expect(
            DictationCapsuleMotion.indicatorChange(
                microphoneIsOpen: open, duration: DictationCompactIndicator.growth) == nil,
            "a card takes its place unanimated")

        let start = Date(timeIntervalSince1970: 1_000)
        let stop = start.addingTimeInterval(7)
        #expect(DictationCompactIndicator.time(start: start, tick: stop, stoppedAt: nil) == "0:07")
        #expect(
            DictationCompactIndicator.time(start: start, tick: stop.addingTimeInterval(30), stoppedAt: stop) == "0:07",
            "the time does not count through the delivery")
        _ = await tail.resumeCall(at: 0)
    }

    @Test
    func anOptionSwitchedMidDictationResizesTheIndicator() async throws {
        let harness = DictationControllerHarness(text: "no borres estas notas")
        defer { harness.controller.cancel() }
        harness.set(true, forKey: DictationCompactIndicator.defaultsKey)
        harness.controller.toggle(using: harness.dependencies)
        try #require(await TestPolling.until { harness.controller.partialText == harness.text })
        #expect(DictationPanelLayout.size(for: harness.controller) == NSSize(width: 38, height: 32))

        harness.set(true, forKey: DictationCompactIndicator.elapsedTimeKey)
        #expect(DictationPanelLayout.size(for: harness.controller) == NSSize(width: 76, height: 32))
        harness.set(true, forKey: DictationCompactIndicator.backdropKey)
        #expect(DictationPanelLayout.size(for: harness.controller) == NSSize(width: 76, height: 38))
        #expect(
            DictationPanelLayout.size(for: harness.controller, options: .init(showsBackdrop: true))
                == NSSize(width: 38, height: 38), "the panel's view passes the values it observes")

        let suite = "indicator-signal-\(UUID().uuidString)"
        let scratch = try #require(UserDefaults(suiteName: suite))
        defer { scratch.removePersistentDomain(forName: suite) }
        let revision = DictationPreferenceSignal.shared.revision
        DictationFeature.store([DictationCompactIndicator.backdropKey: true], in: scratch, temporary: false)
        #expect(DictationPreferenceSignal.shared.revision == revision + 1, "the open panel hears every saved value")

        // The window resizes from its corner, so the glyph stays on the caret.
        let visible = NSRect(x: 0, y: 40, width: 1_440, height: 820)
        let before = NSRect(x: 396, y: 466, width: 38, height: 32)
        let wider = DictationPanelAnchor.origin(
            resizing: before, to: NSSize(width: 76, height: 38), pinned: .top, in: visible, keepsLeading: true)
        #expect(wider == NSPoint(x: 396, y: 460))
    }
}
