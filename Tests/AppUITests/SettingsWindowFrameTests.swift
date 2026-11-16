import AppKit
@testable import AppUI
import DictationSession
import Testing

struct SettingsWindowFrameTests {
    private let visible = NSRect(x: 0, y: 80, width: 1_440, height: 800)

    @Test func theTopEdgeStaysWhileTheWindowFitsOnTheScreen() {
        let frame = NSRect(x: 400, y: 500, width: SettingsMetrics.width, height: 300)
        let grown = SettingsWindowController.fitted(frame, height: 500, in: visible)
        #expect(grown == NSRect(x: 400, y: 300, width: SettingsMetrics.width, height: 500))
        let shrunk = SettingsWindowController.fitted(grown, height: 260, in: visible)
        #expect(shrunk.maxY == frame.maxY)
        #expect(shrunk.height == 260)
    }

    @Test func aWindowNearTheBottomMovesUpInsteadOfGrowingBehindTheDock() {
        let frame = NSRect(x: 400, y: 120, width: SettingsMetrics.width, height: 270)
        let grown = SettingsWindowController.fitted(frame, height: 680, in: visible)
        #expect(grown.minY == visible.minY)
        #expect(grown.height == 680)
        #expect(visible.contains(grown))
    }

    @Test func aTabTallerThanTheScreenIsCappedSoItScrolls() {
        let frame = NSRect(x: 400, y: 300, width: SettingsMetrics.width, height: 400)
        let grown = SettingsWindowController.fitted(frame, height: 1_200, in: visible)
        #expect(grown.height == visible.height)
        #expect(grown.minY == visible.minY)
        #expect(grown.maxY == visible.maxY)
    }

    @Test func aWindowAboveTheVisibleFrameComesBackDown() {
        let frame = NSRect(x: 400, y: 700, width: SettingsMetrics.width, height: 300)
        let fitted = SettingsWindowController.fitted(frame, height: 300, in: visible)
        #expect(fitted.maxY == visible.maxY)
    }

    @Test func withoutAScreenOnlyTheHeightChanges() {
        let frame = NSRect(x: 400, y: 500, width: SettingsMetrics.width, height: 300)
        #expect(SettingsWindowController.fitted(frame, height: 900, in: nil)
            == NSRect(x: 400, y: -100, width: SettingsMetrics.width, height: 900))
    }
}
