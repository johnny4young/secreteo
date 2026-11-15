import SwiftUI

/// Where setup stands, as the product's parentheses around one mark per step.
struct OnboardingProgress: View {
    let step: Int
    let count: Int

    var body: some View {
        HStack(spacing: 9) {
            bracket("(")
            ForEach(0..<count, id: \.self) { index in
                if index == step {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SecreteoDesign.amber)
                        .frame(width: 26, height: 8)
                        .shadow(color: SecreteoDesign.amber.opacity(0.7), radius: 5)
                } else {
                    Circle()
                        .fill(index < step ? SecreteoDesign.accent : SecreteoDesign.tertiaryText.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            bracket(")")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Step %d of %d", step + 1, count))
        .accessibilityIdentifier("onboarding-progress")
    }

    private func bracket(_ mark: String) -> some View {
        Text(verbatim: mark)
            .font(.secreteoSerif(24))
            .foregroundStyle(SecreteoDesign.tertiaryText)
            // The serif's parenthesis hangs below the marks it holds.
            .offset(y: -2)
    }
}

/// A serif title whose last word leans, in copper.
struct OnboardingTitle: View {
    let title: String
    let identifier: String

    var body: some View {
        let parts = Self.split(title)
        let lead = Text(parts.lead).font(.secreteoSerif(46)).foregroundStyle(SecreteoDesign.text)
        let emphasis = Text(parts.emphasis)
            .font(.secreteoSerif(46, italic: true))
            .foregroundStyle(SecreteoDesign.accent)
        Text("\(lead)\(emphasis)")
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    /// The lead keeps its trailing space, so the two parts join back into the title.
    nonisolated static func split(_ title: String) -> (lead: String, emphasis: String) {
        guard let space = title.lastIndex(of: " ") else { return ("", title) }
        let cut = title.index(after: space)
        return (String(title[..<cut]), String(title[cut...]))
    }
}

/// Copper for the screen's one primary action, a card for the rest.
struct OnboardingButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind = Kind.secondary
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        Face(kind: kind, isCompact: isCompact, configuration: configuration)
    }

    private struct Face: View {
        let kind: Kind
        let isCompact: Bool
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 10)
            configuration.label
                .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                .foregroundStyle(kind == .primary ? SecreteoDesign.onAccent : SecreteoDesign.text)
                .padding(.horizontal, isCompact ? 14 : 18)
                .padding(.vertical, isCompact ? 6 : 8)
                .background(kind == .primary ? SecreteoDesign.accent : SecreteoDesign.card, in: shape)
                .overlay { if kind == .secondary { shape.strokeBorder(SecreteoDesign.hairline.opacity(1.6)) } }
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .contentShape(shape)
        }
    }
}

extension View {
    /// A white card on the paper window, with a hairline instead of a shadow.
    func onboardingCard(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return background(SecreteoDesign.card, in: shape).overlay { shape.strokeBorder(SecreteoDesign.hairline) }
    }
}
