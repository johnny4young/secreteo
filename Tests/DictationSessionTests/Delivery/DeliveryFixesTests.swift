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
        let kept = ["macOS is fine", "iPhone works", "secreteo runs", "www.example.com works", "www.example.com. Works",
                    "me@example.com works", "src/main.swift fails", "snake_case fails"]

        for text in kept {
            XCTAssertEqual(caretCase.adapt(text, after: "Done. ", atFieldStart: false), text)
        }
        XCTAssertEqual(caretCase.adapt("then we left.", after: "Done. ", atFieldStart: false), "Then we left.")
        XCTAssertEqual(caretCase.adapt("well... ok", after: "Done. ", atFieldStart: false), "Well... ok")
        XCTAssertEqual(caretCase.adapt("\"hello.\" ok", after: "Done. ", atFieldStart: false), "\"Hello.\" ok")
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

    func testALaterOwnerDuringTheCopiedReadIsNotReplaced() async throws {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        let clipboard = DictationClipboard()
        let provider = PublishingProvider(board: board)

        let copied = await clipboard.copySelection(on: board, timeout: .seconds(30)) {
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [.string])
            board.clearContents()
            return board.writeObjects([item])
        }

        XCTAssertEqual(board.string(forType: .string), "Later owner", "Read back: \(copied ?? "nothing")")
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
        var started = false
        let waiter = Task {
            started = true
            return await clipboard.waitForRestoration(on: board)
        }
        _ = await TestPolling.until { started }
        clipboard.isMutating = false
        _ = await waiter.value

        let restored = await TestPolling.until { board.string(forType: .string) == "Original" }
        XCTAssertTrue(restored)
        XCTAssertEqual(clipboard.pendingLoanCount, 0)
    }

    func testAWaiterOnALoanAlsoWaitsForACopyThatStartsMeanwhile() async throws {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        let clipboard = DictationClipboard()
        let loan = try XCTUnwrap(clipboard.borrow("Own text", on: board))
        clipboard.restoreLater(loan, on: board, after: .seconds(30))
        var started = false
        let waiter = Task {
            started = true
            return await clipboard.waitForRestoration(on: board)
        }
        _ = await TestPolling.until { started }

        var posted = false
        // One main actor turn from the restore to the post, so the waiter cannot run between them.
        let copy = Task {
            clipboard.restore(loan, on: board)
            return await clipboard.copySelection(on: board, timeout: .milliseconds(20), lateWindow: .milliseconds(200)) {
                posted = true
                return true
            }
        }
        _ = await TestPolling.until { posted }
        _ = await waiter.value
        let accepted = clipboard.borrow("Next", on: board)

        XCTAssertNotNil(accepted)
        if let accepted { clipboard.restore(accepted, on: board) }
        _ = await copy.value
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

/// Publishes another owner's text from inside the read of the copied string.
private final class PublishingProvider: NSObject, NSPasteboardItemDataProvider {
    private let board: NSPasteboard

    init(board: NSPasteboard) {
        self.board = board
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString("Selection", forType: type)
        board.clearContents()
        board.setString("Later owner", forType: .string)
    }
}
