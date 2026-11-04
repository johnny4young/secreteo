import AppKit
import DictationKit
import XCTest
@testable import DictationSession

@MainActor
final class DeliveryFixesTests: XCTestCase {
    private func makeBoard(holding text: String = "Original") -> NSPasteboard {
        let board = NSPasteboard(name: .init("com.johnny4young.secreteo.delivery-fixes.\(UUID().uuidString)"))
        board.clearContents()
        board.setString(text, forType: .string)
        return board
    }

    func testASentenceStartKeepsSpellingsACapitalWouldBreak() {
        let caretCase = DictationCaretCase(protectedWords: ["secreteo"])
        let kept = ["macOS is fine", "iPhone works", "secreteo runs", "www.example.com works", "me@example.com works",
                    "src/main.swift fails", "snake_case fails"]

        for text in kept {
            XCTAssertEqual(caretCase.adapt(text, after: "Done. ", atFieldStart: false), text)
        }
        XCTAssertEqual(caretCase.adapt("then we left.", after: "Done. ", atFieldStart: false), "Then we left.")
    }

    func testLiveProtectsReplacementWordsWithoutTheirPunctuation() throws {
        let suite = "com.johnny4young.secreteo.delivery-fixes.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DictationCaretCase.defaultsKey)
        defaults.set(DictationTextRules.encode([.init(trigger: "mac", replacement: "macOS,")]),
                     forKey: DictationController.replacementsKey)

        let caretCase = try XCTUnwrap(DictationCaretCase.live(defaults))

        XCTAssertEqual(caretCase.protectedWords, ["macOS"])
    }

    func testALateCopyAfterTheTimeoutStillGivesTheClipboardBack() async {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        let clipboard = DictationClipboard()

        let copied = await clipboard.copySelection(on: board, timeout: .milliseconds(20), lateWindow: .seconds(30)) { true }
        board.clearContents()
        board.setString("Late selection", forType: .string)

        XCTAssertNil(copied)
        let restored = await TestPolling.until { board.string(forType: .string) == "Original" }
        XCTAssertTrue(restored)
    }

    func testABorrowIsRefusedWhileACopyIsOnItsWay() async {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        let clipboard = DictationClipboard()

        let copied = await clipboard.copySelection(on: board, timeout: .milliseconds(20), lateWindow: .milliseconds(100)) { true }
        let refused = clipboard.borrow("Too early", on: board)
        let waited = await clipboard.waitForRestoration(on: board)
        let accepted = clipboard.borrow("Now", on: board)

        XCTAssertNil(copied)
        XCTAssertNil(refused)
        XCTAssertTrue(waited)
        XCTAssertNotNil(accepted)
        if let accepted { clipboard.restore(accepted, on: board) }
    }

    func testAnOverdueRestoreDuringAMutationStillRestores() async throws {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        let clipboard = DictationClipboard(restorationMargin: .zero)
        let loan = try XCTUnwrap(clipboard.borrow("Own text", on: board))
        clipboard.restoreLater(loan, on: board, after: .zero)

        clipboard.isMutating = true
        let waiter = Task { await clipboard.waitForRestoration(on: board) }
        await Task.yield()
        await Task.yield()
        clipboard.isMutating = false
        _ = await waiter.value

        let restored = await TestPolling.until { board.string(forType: .string) == "Original" }
        XCTAssertTrue(restored)
        XCTAssertEqual(clipboard.pendingLoanCount, 0)
    }

    func testAnEditOutsideTheInsertionIsRefused() {
        let text = "No borres"
        let length = text.utf16.count

        XCTAssertEqual(DictationInsertion.editedText(text, replacing: NSRange(location: 3, length: length - 3), with: "x"), "No x")
        XCTAssertEqual(DictationInsertion.editedText(text, replacing: NSRange(location: length, length: 0), with: "!"), text + "!")
        for range in [NSRange(location: length, length: 1), NSRange(location: length + 1, length: 0),
                      NSRange(location: NSNotFound, length: 0), NSRange(location: -1, length: 1)] {
            XCTAssertNil(DictationInsertion.editedText(text, replacing: range, with: "x"))
        }
    }

    func testOnlyExactLayoutNamesKeepTheQwertyShortcutPositions() {
        for sourceID in ["com.apple.keylayout.US", "com.apple.keylayout.ABC", "com.apple.keylayout.ABC-India",
                         "com.apple.keylayout.British-PC", "com.apple.keylayout.DVORAK-QWERTYCMD"] {
            XCTAssertTrue(TextInserter.usesQwertyCommandPositions(sourceID: sourceID), sourceID)
        }
        for sourceID in ["com.apple.keylayout.Russian", "com.apple.keylayout.Austrian", "org.example.keylayout.USDvorak",
                         "com.apple.keylayout.Dvorak"] {
            XCTAssertFalse(TextInserter.usesQwertyCommandPositions(sourceID: sourceID), sourceID)
        }
    }
}
