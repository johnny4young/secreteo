import SwiftUI

/// What the one-line capsule shows: the newest words, since those are the ones
/// being spoken. Earlier words are elided from the front at a word boundary.
enum DictationPanelTranscript {
    /// More than the capsule's line holds, so the fade always has words to cover.
    static let visibleCharacters = 120

    struct Visible: Equatable {
        var confirmed: String
        /// Includes its leading separator, styled with the volatile tail.
        var partial: String
    }

    static func visible(confirmed: String, partial: String, limit: Int = visibleCharacters) -> Visible {
        let joined = partial.isEmpty ? "" : " " + partial
        let full = confirmed + joined
        guard limit > 0, full.count > limit else { return Visible(confirmed: confirmed, partial: joined) }
        var start = full.index(full.endIndex, offsetBy: -limit)
        if let space = full[start...].firstIndex(where: \.isWhitespace),
           full.distance(from: space, to: full.endIndex) > limit / 2 {
            start = full.index(after: space)
        }
        let boundary = full.index(full.startIndex, offsetBy: confirmed.count)
        guard start < boundary else { return Visible(confirmed: "…", partial: String(full[start...])) }
        return Visible(confirmed: "…" + full[start..<boundary], partial: String(full[boundary...]))
    }
}

/// Confirmed words stand upright; the engine's tail is a whisper in italic serif until it is confirmed.
struct DictationCapsuleTranscript: View {
    let confirmed: String
    let partial: String
    /// VoiceOver keeps the whole dictation; the capsule only shows its end.
    let spoken: String
    /// Nil once the microphone has closed, so the stop tail's captions land without a frame of animation.
    let settle: Animation?

    static let fadeWidth: CGFloat = 36
    static let provisionalOpacity = 0.78

    var body: some View {
        // A line that fits starts at the face; a longer one anchors right so the newest words stay in view.
        ViewThatFits(in: .horizontal) {
            line
            Color.clear
                .overlay(alignment: .trailing) { line }
                .clipped()
                .mask(alignment: .leading) {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.fadeWidth)
                        Color.black
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var line: some View {
        let visible = DictationPanelTranscript.visible(confirmed: confirmed, partial: partial)
        let settled = Text(visible.confirmed)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(SecreteoPalette.capsuleText.color)
        let provisional = Text(visible.partial)
            .font(.secreteoSerif(20, italic: true))
            .foregroundStyle(SecreteoPalette.capsuleProvisionalText.color.opacity(Self.provisionalOpacity))
        return Text("\(settled)\(provisional)")
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.opacity)
            .animation(settle, value: visible)
            .accessibilityIdentifier("dictation-panel-transcript")
            .accessibilityLabel(spoken)
    }
}
