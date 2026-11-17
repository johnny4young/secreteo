import CoreGraphics
import XCTest

@testable import DictationSession

final class AccessibilityGrantGuideTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    private let size = CGSize(width: 300, height: 80)

    func testTheGuideClosesWhenSystemSettingsLeavesOrTimeRunsOut() {
        let early = Duration.seconds(5)
        XCTAssertFalse(AccessibilityGrantGuide.shouldClose(settingsOnScreen: false, sawSettings: false, elapsed: early))
        XCTAssertFalse(AccessibilityGrantGuide.shouldClose(settingsOnScreen: true, sawSettings: true, elapsed: early))
        XCTAssertTrue(AccessibilityGrantGuide.shouldClose(settingsOnScreen: false, sawSettings: true, elapsed: early))
        XCTAssertTrue(AccessibilityGrantGuide.shouldClose(
            settingsOnScreen: true, sawSettings: true, elapsed: AccessibilityGrantGuide.timeLimit))
    }

    func testTheGuideSitsBesideSystemSettings() {
        let settings = CGRect(x: 200, y: 200, width: 700, height: 500)
        XCTAssertEqual(AccessibilityGrantGuide.origin(for: size, beside: settings, in: screen), CGPoint(x: 912, y: 410))
    }

    func testWithNoRoomOnTheRightItMovesLeftThenBelow() {
        let right = CGRect(x: 700, y: 200, width: 700, height: 500)
        XCTAssertEqual(AccessibilityGrantGuide.origin(for: size, beside: right, in: screen), CGPoint(x: 388, y: 410))
        let wide = CGRect(x: 100, y: 300, width: 1_240, height: 500)
        XCTAssertEqual(AccessibilityGrantGuide.origin(for: size, beside: wide, in: screen), CGPoint(x: 570, y: 208))
    }

    func testWithoutSystemSettingsItStaysOnScreen() {
        XCTAssertEqual(AccessibilityGrantGuide.origin(for: size, beside: nil, in: screen), CGPoint(x: 570, y: 180))
        let low = CGRect(x: 200, y: -400, width: 700, height: 420)
        XCTAssertEqual(AccessibilityGrantGuide.origin(for: size, beside: low, in: screen).y, 0)
    }
}
