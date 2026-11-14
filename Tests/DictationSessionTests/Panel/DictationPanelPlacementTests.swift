import AppKit
import XCTest

@testable import DictationSession

@MainActor
final class DictationPanelPlacementTests: XCTestCase {
    func testAReusedPanelStaysWhereItWasMovedUntilTheNextDictationOpensAtItsAnchor() throws {
        // The menu bar screen: `NSScreen.main` follows the key window and can change mid-test.
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Placement needs a display") }
        let visible = screen.visibleFrame
        let first = DictationPanelAnchor.pointer(NSPoint(x: visible.minX + 300, y: visible.midY))
        let second = DictationPanelAnchor.pointer(NSPoint(x: visible.maxX - 300, y: visible.midY))
        let harness = DictationControllerHarness(text: "Send the report.")
        let panels = DictationPanelController()
        defer {
            panels.close()
            harness.controller.cancel()
        }
        var dependencies = harness.dependencies
        // Holds each dictation in `.preparing`; cancel ends the wait.
        dependencies.authorizeMicrophone = {
            try? await Task.sleep(for: .seconds(3_600))
            return false
        }

        dependencies.locatePanelAnchor = { first }
        harness.controller.toggle(using: dependencies)
        XCTAssertEqual(harness.controller.phase, .preparing)
        // Another controller in this process may still hold a panel with the same identifier.
        let earlier = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        panels.show(controller: harness.controller)
        let panel = try XCTUnwrap(NSApplication.shared.windows.first {
            $0.accessibilityIdentifier() == "dictation-panel" && !earlier.contains(ObjectIdentifier($0))
        })
        assertOrigin(of: panel, near: first, in: screen)

        let moved = NSPoint(x: visible.midX, y: visible.minY + 100)
        panel.setFrameOrigin(moved)
        harness.controller.cancel()
        XCTAssertNotEqual(harness.controller.phase, .preparing)
        panels.show(controller: harness.controller)
        XCTAssertEqual(panel.frame.origin.x, moved.x, accuracy: 1, "an open panel stays where the user put it")
        XCTAssertEqual(panel.frame.origin.y, moved.y, accuracy: 1)

        dependencies.locatePanelAnchor = { second }
        harness.controller.toggle(using: dependencies)
        XCTAssertEqual(harness.controller.phase, .preparing)
        panels.show(controller: harness.controller)
        assertOrigin(of: panel, near: second, in: screen)
    }

    /// The window server keeps frames on whole points.
    private func assertOrigin(
        of panel: NSWindow, near anchor: DictationPanelAnchor, in screen: NSScreen, line: UInt = #line
    ) {
        let expected = DictationPanelAnchor.origin(for: panel.frame.size, near: anchor, in: screen.visibleFrame)
        XCTAssertEqual(panel.frame.origin.x, expected.x, accuracy: 1, line: line)
        XCTAssertEqual(panel.frame.origin.y, expected.y, accuracy: 1, line: line)
    }
}
