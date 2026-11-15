import AppKit
import XCTest

@testable import DictationSession

@MainActor
final class DictationPanelOutcomeSizeTests: XCTestCase {
    func testARecoveryCardIsAsTallAsItsWordsAndGrowsFromItsPinnedEdge() async throws {
        guard NSScreen.screens.first != nil else { throw XCTSkip("A panel needs a display") }
        let short = try await cardHeight(for: "Send the report.")
        let long = try await cardHeight(
            for: Array(repeating: "Send the report before Friday.", count: 2).joined(separator: " "))
        let endless = try await cardHeight(
            for: Array(repeating: "Send the report before Friday.", count: 80).joined(separator: " "))
        XCTAssertGreaterThan(short, DictationPanelLayout.capsuleHeight)
        XCTAssertGreaterThan(long, short, "more words, a taller card")
        XCTAssertGreaterThan(endless, long)
        XCTAssertLessThan(endless, 288, "past a few lines the words scroll")
    }

    private func cardHeight(for text: String) async throws -> CGFloat {
        let harness = DictationControllerHarness(text: text)
        let panels = DictationPanelController()
        defer {
            panels.close()
            harness.controller.cancel()
        }
        var dependencies = harness.dependencies
        dependencies.captureDestination = {
            CapturedDictationDestination(name: "Original app", canRetry: true) { _ in .refused(.targetChanged) }
        }
        harness.controller.toggle(using: dependencies)
        let heard = await TestPolling.until { harness.controller.partialText == text }
        XCTAssertTrue(heard)
        let earlier = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        panels.show(controller: harness.controller)
        let panel = try XCTUnwrap(NSApplication.shared.windows.first {
            $0.accessibilityIdentifier() == "dictation-panel" && !earlier.contains(ObjectIdentifier($0))
        })
        XCTAssertEqual(panel.frame.height, DictationPanelLayout.capsuleHeight)
        let capsule = panel.frame

        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)
        let refused = await TestPolling.until { harness.controller.phase == .recovery(.targetChanged) }
        XCTAssertTrue(refused)
        panels.show(controller: harness.controller)
        // The words are measured after the card, so the height counts once it stops changing.
        var last = CGFloat.zero
        var unchanged = 0
        let settled = await TestPolling.until {
            unchanged = panel.frame.height == last ? unchanged + 1 : 0
            last = panel.frame.height
            return last > DictationPanelLayout.capsuleHeight && unchanged >= 40
        }
        XCTAssertTrue(settled, "the card's measured height reaches the panel")
        XCTAssertEqual(panel.frame.width, DictationPanelLayout.width)
        XCTAssertEqual(panel.frame.minX, capsule.minX, accuracy: 1)
        XCTAssertTrue(
            abs(panel.frame.maxY - capsule.maxY) <= 1 || abs(panel.frame.minY - capsule.minY) <= 1,
            "one horizontal edge stays where the capsule had it")
        return panel.frame.height
    }
}
