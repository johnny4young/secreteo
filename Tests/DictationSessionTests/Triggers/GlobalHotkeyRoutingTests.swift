import Carbon.HIToolbox
import XCTest
@testable import DictationSession

final class GlobalHotkeyRoutingTests: XCTestCase {
    func testOnlyTheOwningRegistrationHandlesItsKey() {
        let dictation = EventHotKeyID(signature: OSType(0x5343_5254), id: 1)
        let escape = EventHotKeyID(signature: OSType(0x5343_5254), id: 2)
        let foreign = EventHotKeyID(signature: OSType(0x4142_4344), id: 1)

        XCTAssertTrue(GlobalHotkey.routes(dictation, to: dictation))
        XCTAssertFalse(GlobalHotkey.routes(escape, to: dictation), "Escape must not toggle dictation")
        XCTAssertFalse(GlobalHotkey.routes(dictation, to: escape), "The dictation shortcut must not cancel")
        XCTAssertFalse(GlobalHotkey.routes(foreign, to: dictation), "Another signature is never ours")
    }
}
