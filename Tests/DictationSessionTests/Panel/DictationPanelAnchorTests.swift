import AppKit
import XCTest

@testable import DictationSession

final class DictationPanelAnchorTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)
    private let size = NSSize(width: 176, height: 32)

    func testTheStripOpensJustBelowTheCaret() {
        let caret = NSRect(x: 600, y: 500, width: 2, height: 18)
        let origin = DictationPanelAnchor.origin(for: size, near: .caret(caret), in: visible)
        XCTAssertEqual(origin, NSPoint(x: 584, y: 500 - 8 - 32))
    }

    func testNearTheBottomItOpensAboveAndAtTheEdgeItStaysOnScreen() {
        let low = NSRect(x: 1_420, y: 50, width: 2, height: 18)
        let origin = DictationPanelAnchor.origin(for: size, near: .caret(low), in: visible)
        XCTAssertEqual(origin.y, 50 + 18 + 8, "no room below, so above the caret")
        XCTAssertEqual(origin.x, visible.maxX - size.width, "never past the right edge")

        let corner = DictationPanelAnchor.origin(for: size, near: .pointer(NSPoint(x: -30, y: 2_000)), in: visible)
        XCTAssertTrue(visible.contains(NSRect(origin: corner, size: size)), "always fully visible")
    }

    func testAPanelUnderItsCaretGrowsDownwardAndOneAboveItGrowsUpward() {
        let capsule = NSSize(width: 520, height: 56), card = NSSize(width: 520, height: 96)
        let caret = NSRect(x: 600, y: 500, width: 2, height: 18)
        XCTAssertEqual(DictationPanelAnchor.pinnedEdge(for: capsule, near: .caret(caret), in: visible), .top)
        let below = NSRect(
            origin: DictationPanelAnchor.origin(for: capsule, near: .caret(caret), in: visible), size: capsule)
        let grown = DictationPanelAnchor.origin(resizing: below, to: card, pinned: .top, in: visible)
        XCTAssertEqual(grown.y + card.height, below.maxY, "the top edge stays under the caret")
        XCTAssertLessThan(grown.y + card.height, caret.minY, "it never rises over the line being written")
        XCTAssertEqual(grown.x, below.minX)

        let low = NSRect(x: 600, y: 60, width: 2, height: 18)
        XCTAssertEqual(DictationPanelAnchor.pinnedEdge(for: capsule, near: .caret(low), in: visible), .bottom)
        let above = NSRect(
            origin: DictationPanelAnchor.origin(for: capsule, near: .caret(low), in: visible), size: capsule)
        let raised = DictationPanelAnchor.origin(resizing: above, to: card, pinned: .bottom, in: visible)
        XCTAssertEqual(raised.y, above.minY, "above the caret the bottom edge stays")
        XCTAssertGreaterThanOrEqual(raised.y, low.maxY)
    }

    func testResizingKeepsAPanelOnScreenAndWhereTheUserPutIt() {
        let capsule = NSSize(width: 520, height: 56), card = NSSize(width: 520, height: 288)
        let nearBottom = NSRect(x: 100, y: visible.minY + 100, width: 520, height: 56)
        let clamped = DictationPanelAnchor.origin(resizing: nearBottom, to: card, pinned: .top, in: visible)
        XCTAssertEqual(clamped.y, visible.minY, "a tall card stops at the bottom of the screen")

        // Dragged half off the right edge: a height change must not pull it back.
        let dragged = NSRect(x: visible.maxX - 260, y: 400, width: 520, height: 96)
        let same = DictationPanelAnchor.origin(resizing: dragged, to: capsule, pinned: .bottom, in: visible)
        XCTAssertEqual(same, dragged.origin)

        let compact = NSRect(x: 700, y: 400, width: 176, height: 32)
        let widened = DictationPanelAnchor.origin(resizing: compact, to: capsule, pinned: .top, in: visible)
        XCTAssertEqual(widened.x + capsule.width / 2, compact.midX, "the compact indicator grows around its center")
        XCTAssertEqual(widened.y + capsule.height, compact.maxY)

        let aside = NSRect(x: 700, y: 400, width: 30, height: 24)
        let grown = DictationPanelAnchor.origin(
            resizing: aside, to: card, pinned: .top, in: visible, keepsLeading: true)
        XCTAssertEqual(grown.x, aside.minX, "under a caret it grows into its card from the caret")
        XCTAssertEqual(grown.y + card.height, aside.maxY)
    }

    func testThePointerLeavesRoomForTheCursorGlyph() {
        let origin = DictationPanelAnchor.origin(for: size, near: .pointer(NSPoint(x: 300, y: 400)), in: visible)
        XCTAssertEqual(origin, NSPoint(x: 284, y: 400 - 20 - 8 - 32))
    }

    func testASlotHangsTheStripFromItsTopEdgeSoItGrowsAwayFromTheWordsAbove() {
        let slot = NSRect(x: 400, y: 300, width: 448, height: 56)
        let capsule = NSSize(width: 520, height: 56)
        let origin = DictationPanelAnchor.origin(for: capsule, near: .slot(slot), in: visible)
        XCTAssertEqual(origin, NSPoint(x: 624 - 260, y: 300))
        XCTAssertEqual(DictationPanelAnchor.pinnedEdge(for: capsule, near: .slot(slot), in: visible), .top)

        // The notice under the capsule, the pill with four lines of words, and a card.
        let frame = NSRect(origin: origin, size: capsule)
        for height in [DictationPanelLayout.capsuleHeight(showsNotice: true), 174, 288] {
            let size = NSSize(width: 520, height: height)
            let grown = DictationPanelAnchor.origin(resizing: frame, to: size, pinned: .top, in: visible)
            XCTAssertEqual(grown.y + height, slot.maxY, "\(height) pt never rises over the words")
            let moved = DictationPanelAnchor.origin(for: size, near: .slot(slot), in: visible)
            XCTAssertEqual(moved.y + height, slot.maxY, "and stays under them when the window moves")
        }

        let offScreen = NSRect(x: -200, y: 0, width: 448, height: 56)
        let clamped = DictationPanelAnchor.origin(for: size, near: .slot(offScreen), in: visible)
        XCTAssertTrue(visible.contains(NSRect(origin: clamped, size: size)))
    }

    func testAccessibilityGeometryFlipsToCocoaCoordinates() {
        let rect = DictationPanelAnchor.cocoaRect(
            fromAccessibility: CGRect(x: 100, y: 200, width: 2, height: 18), primaryScreenHeight: 900)
        XCTAssertEqual(rect, NSRect(x: 100, y: 900 - 218, width: 2, height: 18))
    }
}

@MainActor
extension DictationControllerTests {
    func testTheStripAnchorIsReadWithTheDestination() async {
        let harness = DictationControllerHarness(text: "Send the report.")
        defer { harness.controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.locatePanelAnchor = { .pointer(NSPoint(x: 300, y: 400)) }
        harness.controller.toggle(using: dependencies)
        XCTAssertEqual(harness.controller.panelAnchor, .pointer(NSPoint(x: 300, y: 400)))
        harness.controller.cancel()

        harness.controller.toggle(using: harness.dependencies)
        XCTAssertNil(harness.controller.panelAnchor, "a new dictation never keeps the last one's anchor")
    }

    func testAPanelInAWindowsSlotFollowsTheWindowAndEndsWithIt() async {
        let harness = DictationControllerHarness(text: "Send the report.")
        defer { harness.controller.cancel() }
        let first = NSRect(x: 200, y: 300, width: 448, height: 56)
        let second = first.offsetBy(dx: 120, dy: -80)
        var dependencies = harness.dependencies
        dependencies.locatePanelAnchor = { .slot(first) }
        harness.controller.toggle(using: dependencies)
        XCTAssertFalse(harness.controller.sessionIsPractice, "A dictation into another app is not the field's")

        harness.controller.panelSlotMoved(to: second)
        XCTAssertEqual(harness.controller.panelAnchor, .slot(second))
        harness.controller.panelSlotClosed()
        XCTAssertEqual(harness.controller.phase, .idle, "Without its window the dictation ends")
        harness.controller.panelSlotMoved(to: first)
        XCTAssertEqual(harness.controller.panelAnchor, .slot(second), "Nothing is left to move")

        dependencies.locatePanelAnchor = { .pointer(NSPoint(x: 300, y: 400)) }
        dependencies.admissionKind = .practice
        harness.controller.toggle(using: dependencies)
        XCTAssertTrue(harness.controller.sessionIsPractice)
        harness.controller.panelSlotMoved(to: second)
        XCTAssertEqual(harness.controller.panelAnchor, .pointer(NSPoint(x: 300, y: 400)), "Only a slot follows")
        harness.controller.panelSlotClosed()
        XCTAssertNotEqual(harness.controller.phase, .idle, "A panel by the pointer has no window to lose")
    }
}
