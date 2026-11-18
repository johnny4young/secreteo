import SwiftUI

/// The dark card an outcome opens into when it leaves words to act on, as tall as those words.
struct DictationOutcomeCard<Actions: View>: View {
    let face: SecreteoGlyphFace
    let title: String
    let reason: String
    var notice: String?
    let words: String
    let titleIdentifier: String
    let reasonIdentifier: String
    let textIdentifier: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                SecreteoGlyph(face, ink: SecreteoPalette.capsuleSecondaryText.color)
                    .frame(width: 22, height: 20)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                // The reason sits beside the title while it fits on that line, and under it otherwise.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        heading.fixedSize()
                        explanation.lineLimit(1).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        heading.lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        explanation.lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("dictation-panel-polish-notice")
            }
            if !words.isEmpty {
                DictationOutcomeWords(text: words, identifier: textIdentifier)
                    .padding(.top, 11)
            }
            HStack(spacing: 8) { actions }
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 17)
        .frame(width: DictationPanelLayout.width, alignment: .leading)
        .background { DictationLacquer(tint: 0.92) }
        .clipShape(outline)
        .overlay { DictationRimStroke(style: DictationCapsuleRim(face: face), outline: outline) }
        .accessibilityElement(children: .contain)
    }

    private var heading: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SecreteoPalette.capsuleText.color)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(titleIdentifier)
    }

    private var explanation: some View {
        Text(reason)
            .font(.system(size: 12))
            .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
            .accessibilityIdentifier(reasonIdentifier)
    }

    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: DictationPanelLayout.cardRadius, style: .continuous)
    }
}

/// The complete output stays reachable even when Copy fails: it scrolls past a few lines and can be selected.
private struct DictationOutcomeWords: View {
    let text: String
    let identifier: String
    @State private var contentHeight = DictationPanelLayout.wordsFontSize * 1.25
    @State private var continuesBelow = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(.secreteoSerif(DictationPanelLayout.wordsFontSize))
                .lineSpacing(3)
                .foregroundStyle(SecreteoPalette.capsuleText.color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(identifier)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: Bool.self) {
            DictationPanelLayout.wordsContinueBelow(
                offset: $0.contentOffset.y, visible: $0.containerSize.height, content: $0.contentSize.height)
        } action: { continuesBelow = $1 }
        .frame(height: DictationPanelLayout.wordsHeight(forContent: contentHeight))
        // Words that continue below fade out instead of ending on half a line.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.86),
                    .init(color: continuesBelow ? .clear : .black, location: 1)
                ],
                startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The card's buttons: one copper primary at most, the rest quiet.
struct DictationCardButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet, bare }

    var kind = Kind.quiet
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background { fill.clipShape(shape) }
            .overlay { if kind == .quiet { shape.strokeBorder(.white.opacity(0.13)) } }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }

    private var ink: Color {
        switch kind {
        case .primary: SecreteoPalette.capsulePrimaryText.color
        case .quiet: SecreteoPalette.capsuleText.color
        case .bare: SecreteoPalette.capsuleSecondaryText.color
        }
    }

    @ViewBuilder private var fill: some View {
        switch kind {
        case .primary:
            LinearGradient(
                colors: [SecreteoPalette.capsulePrimaryTop.color, SecreteoPalette.capsulePrimaryBottom.color],
                startPoint: .top, endPoint: .bottom)
        case .quiet: Color.white.opacity(0.09)
        case .bare: Color.clear
        }
    }
}
