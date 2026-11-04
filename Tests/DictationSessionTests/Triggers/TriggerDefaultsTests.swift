import Carbon.HIToolbox
import XCTest
@testable import DictationSession

final class TriggerDefaultsTests: XCTestCase {
    @MainActor
    func testTheDefaultShortcutIsNotTheOneThePeerAppUses() {
        let peerModifiers = UInt32(optionKey | cmdKey)

        let setting = HotkeySetting.default

        XCTAssertFalse(setting.keyCode == UInt32(kVK_ANSI_D) && setting.modifiers == peerModifiers)
        XCTAssertEqual(setting.label, HotkeySetting.modifierLabel(setting.modifiers) + "D")
    }

    func testAHeldMouseButtonEndsWhenTheTapIsLost() {
        var hold = MousePTTHold()

        hold.press()

        XCTAssertTrue(hold.tapLost())
        XCTAssertFalse(hold.tapLost(), "A lost tap ends one hold once")
    }

    func testAReleasedMouseButtonHasNothingToEndWhenTheTapIsLost() {
        var hold = MousePTTHold()
        hold.press()

        hold.release()

        XCTAssertFalse(hold.tapLost())
    }
}
