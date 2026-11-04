import DictationKit
import XCTest

/// Pure text assembly for system-wide dictation.
final class DictationAssemblerTests: XCTestCase {
    func testJoinsConfirmedAndPartial() {
        XCTAssertEqual(
            DictationAssembler.text(confirmed: "hola equipo,", partial: "revisemos el sprint"),
            "hola equipo, revisemos el sprint")
    }

    func testTrimsAndDropsEmptyPieces() {
        XCTAssertEqual(DictationAssembler.text(confirmed: "  hola  ", partial: "   "), "hola")
        XCTAssertEqual(DictationAssembler.text(confirmed: "", partial: "solo parcial"), "solo parcial")
        XCTAssertEqual(DictationAssembler.text(confirmed: "", partial: ""), "")
    }

    func testLexicalContentGateKeepsWordsAndRejectsNoiseArtifacts() {
        XCTAssertTrue(DictationAssembler.hasLexicalContent("sí"))
        XCTAssertTrue(DictationAssembler.hasLexicalContent("reunión a las 3"))
        XCTAssertTrue(DictationAssembler.hasLexicalContent("ok!"))
        XCTAssertFalse(DictationAssembler.hasLexicalContent(""))
        XCTAssertFalse(DictationAssembler.hasLexicalContent("."))
        XCTAssertFalse(DictationAssembler.hasLexicalContent("…"))
        XCTAssertFalse(DictationAssembler.hasLexicalContent("¿? ,,, —"))
    }
}
