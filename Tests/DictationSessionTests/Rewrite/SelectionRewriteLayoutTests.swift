import AppKit
import Testing

@testable import DictationSession

@MainActor
struct SelectionRewriteLayoutTests {
    private typealias Layout = SelectionRewriteLayout

    @Test
    func theQuoteIsClampedToAFewLines() {
        let font = NSFont.systemFont(ofSize: 20)
        #expect(Layout.quoteLines(for: "", font: font) == 1)
        #expect(Layout.quoteLines(for: "ship it", font: font) == 1)
        let two = String(repeating: "word ", count: 14)
        #expect(Layout.quoteLines(for: two, font: font) == 2)
        #expect(Layout.quoteLines(for: String(repeating: "word ", count: 400), font: font) == Layout.maximumQuoteLines)
        #expect(Layout.previewLines(for: String(repeating: "word ", count: 400), font: font) == Layout.maximumPreviewLines)
        #expect(Layout.quoteHeight(lines: 1) < Layout.quoteHeight(lines: 2))
        #expect(Layout.quoteHeight(lines: 9) == Layout.quoteHeight(lines: Layout.maximumQuoteLines))
    }

    @Test
    func theCardGrowsOnlyWithWhatItShows() {
        let plain = Layout.Content(quoteLines: 2)
        let choosing = Layout.height(for: .choosing, content: plain)
        #expect(Layout.height(for: .rewriting, content: plain) == choosing, "rewriting never moves the card")
        var noticed = plain
        noticed.showsNotice = true
        #expect(Layout.height(for: .choosing, content: noticed) == choosing + Layout.spacing + Layout.noticeHeight)
        var instructed = plain
        instructed.showsInstruction = true
        #expect(
            Layout.height(for: .choosing, content: instructed) == choosing + Layout.spacing + Layout.instructionHeight)
        #expect(Layout.height(for: .choosing, content: Layout.Content(quoteLines: 3)) > choosing)

        let bare = Layout.height(for: .failed("no"), content: Layout.Content())
        #expect(bare == Layout.height(for: .capturing, content: plain))
        #expect(bare == Layout.height(for: .replaced, content: plain))
        #expect(
            Layout.height(for: .failed("no"), content: Layout.Content(hasResult: true))
                == bare + Layout.actionsSpacing + Layout.buttonHeight,
            "a failed replace keeps Copy")
        let preview = Layout.height(for: .preview("x"), content: plain)
        #expect(Layout.height(for: .preview("x"), content: Layout.Content(previewLines: 4)) > preview)
        #expect(
            Layout.height(for: .preview("x"), content: Layout.Content(previewLines: 40))
                == Layout.height(for: .preview("x"), content: Layout.Content(previewLines: Layout.maximumPreviewLines)),
            "a long rewrite scrolls instead of growing the card")
    }

    @Test
    func theFaceAndTheRimFollowThePhase() {
        #expect(Layout.face(for: .capturing) == .loading)
        #expect(Layout.face(for: .choosing) == .polishing)
        #expect(Layout.face(for: .listening) == .listening)
        #expect(Layout.face(for: .preview("x")) == .polishing)
        #expect(Layout.face(for: .replaced) == .inserted)
        #expect(Layout.face(for: .failed("no")) == .notSent)
        #expect(Layout.rim(for: .choosing) == .rewrite)
        #expect(Layout.rim(for: .listening) == .voice)
        #expect(Layout.rim(for: .failed("no")) == .notSent)
        #expect(DictationCapsuleRim.rewrite.glows)
        #expect(Layout.isBusy(.rewriting) && !Layout.isBusy(.choosing) && !Layout.isBusy(.preview("x")))
    }

    @Test
    func theCardStepsAboveTheCapsuleOnlyWhileTheInstructionIsSpoken() {
        #expect(Layout.lift(for: .listening) > DictationPanelLayout.capsuleHeight(showsNotice: true))
        for phase: SelectionRewriteController.Phase in [.capturing, .choosing, .rewriting, .preview("x"), .replaced] {
            #expect(Layout.lift(for: phase) == 0)
        }
    }

    @Test
    func chipsThatDoNotFitGoBehindTheOverflow() {
        #expect(Layout.visibleChips(widths: [60, 70, 80], overflowWidth: 50, available: 300, spacing: 8) == 3)
        #expect(Layout.visibleChips(widths: [60, 70, 80], overflowWidth: 50, available: 226, spacing: 8) == 3)
        #expect(Layout.visibleChips(widths: [60, 70, 80], overflowWidth: 50, available: 225, spacing: 8) == 2)
        #expect(Layout.visibleChips(widths: [60, 70, 80], overflowWidth: 50, available: 150, spacing: 8) == 1)
        #expect(Layout.visibleChips(widths: [200], overflowWidth: 50, available: 100, spacing: 8) == 1, "Polish stays")
        #expect(Layout.visibleChips(widths: [], overflowWidth: 50) == 0)

        let long = Layout.chipWidth(for: String(repeating: "A long recipe name ", count: 4))
        #expect(long == Layout.maximumChipLabelWidth + Layout.chipPadding * 2)
        #expect(Layout.chipWidth(for: "Polish") < long)
    }
}
