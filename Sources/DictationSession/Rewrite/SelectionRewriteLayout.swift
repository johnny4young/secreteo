import AppKit

/// One size authority for the rewrite card: AppKit sizes the panel from the same numbers
/// SwiftUI lays out with, so the card never moves after a re-show.
enum SelectionRewriteLayout {
    static let width: CGFloat = 520
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 17
    static let contentWidth = width - horizontalPadding * 2
    static let headerHeight: CGFloat = 24
    /// A lone header may wrap a failure onto a second line.
    static let loneHeaderHeight: CGFloat = 32
    static let quoteSize = DictationPanelLayout.wordsFontSize
    static let quoteLineSpacing: CGFloat = 3
    static let maximumQuoteLines = 3
    static let noticeHeight: CGFloat = 30
    static let instructionHeight: CGFloat = 20
    static let liveHeight: CGFloat = 26
    static let chipHeight: CGFloat = 28
    static let chipSpacing: CGFloat = 8
    static let chipPadding: CGFloat = 11
    static let maximumChipLabelWidth: CGFloat = 128
    /// The height of the card family's buttons.
    static let buttonHeight: CGFloat = 28
    static let maximumPreviewLines = 5
    static let spacing: CGFloat = 10
    static let actionsSpacing: CGFloat = 14

    /// What the card shows beyond its phase.
    struct Content: Equatable {
        var quoteLines = 1
        var previewLines = 1
        var showsNotice = false
        var showsInstruction = false
        var hasResult = false
    }

    static func face(for phase: SelectionRewriteController.Phase) -> SecreteoGlyphFace {
        switch phase {
        case .idle: .ready
        case .capturing: .loading
        case .listening: .listening
        case .choosing, .rewriting, .preview, .replacing: .polishing
        case .replaced: .inserted
        case .failed: .notSent
        }
    }

    static func rim(for phase: SelectionRewriteController.Phase) -> DictationCapsuleRim {
        switch phase {
        case .capturing: .loading
        case .listening: .voice
        case .failed: .notSent
        case .idle, .choosing, .rewriting, .preview, .replacing, .replaced: .rewrite
        }
    }

    static func isBusy(_ phase: SelectionRewriteController.Phase) -> Bool {
        [.capturing, .rewriting, .replacing].contains(phase)
    }

    static func height(for phase: SelectionRewriteController.Phase, content: Content) -> CGFloat {
        let frame = verticalPadding * 2
        let actions = actionsSpacing + buttonHeight
        switch phase {
        case .choosing, .rewriting:
            return frame + headerHeight + spacing + quoteHeight(lines: content.quoteLines)
                + (content.showsNotice ? spacing + noticeHeight : 0)
                + (content.showsInstruction ? spacing + instructionHeight : 0)
                + spacing + chipHeight + actions
        case .listening:
            return frame + headerHeight + spacing + quoteHeight(lines: content.quoteLines)
                + spacing + liveHeight + actions
        case .preview:
            return frame + headerHeight + spacing
                + textHeight(lines: content.previewLines, maximum: maximumPreviewLines) + actions
        case .failed where content.hasResult:
            return frame + loneHeaderHeight + actions
        case .idle, .capturing, .replacing, .replaced, .failed:
            return frame + loneHeaderHeight
        }
    }

    static func quoteHeight(lines: Int) -> CGFloat {
        textHeight(lines: lines, maximum: maximumQuoteLines)
    }

    static func textHeight(lines: Int, maximum: Int) -> CGFloat {
        let lines = CGFloat(min(max(lines, 1), maximum))
        return (lines * quoteLineHeight + (lines - 1) * quoteLineSpacing).rounded(.up)
    }

    static var quoteFont: NSFont {
        NSFont(name: SecreteoSerif.regularName, size: quoteSize)
            ?? NSFont.systemFont(ofSize: quoteSize).fontDescriptor.withDesign(.serif)
                .flatMap { NSFont(descriptor: $0, size: quoteSize) }
            ?? NSFont.systemFont(ofSize: quoteSize)
    }

    static let quoteLineHeight = NSLayoutManager().defaultLineHeight(for: quoteFont)

    /// How many lines the quoted selection takes, clamped so a long one never pushes the actions away.
    static func quoteLines(for text: String, width: CGFloat = contentWidth, font: NSFont = quoteFont) -> Int {
        lines(for: text, maximum: maximumQuoteLines, width: width, font: font)
    }

    /// A longer rewrite scrolls inside the same card.
    static func previewLines(for text: String, width: CGFloat = contentWidth, font: NSFont = quoteFont) -> Int {
        lines(for: text, maximum: maximumPreviewLines, width: width, font: font)
    }

    private static func lines(for text: String, maximum: Int, width: CGFloat, font: NSFont) -> Int {
        guard !text.isEmpty, width > 0 else { return 1 }
        let bounds = NSAttributedString(string: text, attributes: [.font: font]).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let lines = Int((bounds.height / NSLayoutManager().defaultLineHeight(for: font)).rounded())
        return min(max(lines, 1), maximum)
    }

    static func chipWidth(for label: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let text = (label as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        return min(text, maximumChipLabelWidth) + chipPadding * 2
    }

    /// How many chips sit on the one row; the rest go behind the overflow chip.
    static func visibleChips(
        widths: [CGFloat], overflowWidth: CGFloat, available: CGFloat = contentWidth, spacing: CGFloat = chipSpacing
    ) -> Int {
        let total = widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0))
        guard total > available else { return widths.count }
        var used = overflowWidth
        var count = 0
        for width in widths {
            guard used + width + spacing <= available else { break }
            used += width + spacing
            count += 1
        }
        return max(count, 1)
    }
}
