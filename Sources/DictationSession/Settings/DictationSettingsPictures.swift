import SwiftUI

/// The modifier row of a keyboard, with the key that starts dictation lit.
struct DictationHoldKeyStrip: View {
    let key: ModifierKeySetting

    var body: some View {
        SettingsKeyCaps(keys: ["fn", "⌃", "⌥", "⌘", " ", "⌘", "⌥"], highlighted: highlighted)
    }

    private var highlighted: Int? {
        switch key {
        case .off: nil
        case .function: 0
        case .rightCommand: 5
        case .rightOption: 6
        }
    }
}

/// Speech, then the silence that is waited out, then the stop.
struct DictationPauseDiagram: View {
    var body: some View {
        Canvas { context, size in
            let middle = size.height / 2
            var wave = Path()
            wave.move(to: CGPoint(x: 1, y: middle))
            for step in 0..<5 {
                let x = 1 + CGFloat(step) * 7
                wave.addQuadCurve(
                    to: CGPoint(x: x + 7, y: middle),
                    control: CGPoint(x: x + 3.5, y: middle + (step.isMultiple(of: 2) ? -9 : 9)))
            }
            let round = StrokeStyle(lineWidth: 1.7, lineCap: .round)
            context.stroke(wave, with: .color(SecreteoDesign.ember), style: round)
            var silence = Path()
            silence.move(to: CGPoint(x: 42, y: middle))
            silence.addLine(to: CGPoint(x: size.width - 24, y: middle))
            context.stroke(
                silence, with: .color(SecreteoDesign.tertiaryText),
                style: StrokeStyle(lineWidth: 1.7, lineCap: .round, dash: [0.5, 5]))
            let stop = CGRect(x: size.width - 14, y: middle - 6.5, width: 13, height: 13)
            context.fill(Path(roundedRect: stop, cornerRadius: 3.5), with: .color(SecreteoDesign.accent))
        }
        .frame(width: 118, height: 22)
        .accessibilityHidden(true)
    }
}

/// The input level while a dictation is running; at rest it is only the meter's shape.
struct DictationMicrophoneMeter: View {
    let controller: DictationController

    private static let shape: [CGFloat] = [0.3, 0.5, 0.75, 0.45, 0.6, 1, 0.55, 0.35, 0.7, 0.4]
    private static let bars = 16

    var body: some View {
        let amplitude = controller.isActive ? DictationWaveformShape.amplitude(for: controller.micLevel) : 0
        let lit = controller.isActive ? max(1, Int((amplitude * Double(Self.bars)).rounded())) : 0
        HStack(spacing: 2) {
            ForEach(0..<Self.bars, id: \.self) { index in
                let height = index < lit ? 4 + 12 * Self.shape[index % Self.shape.count] : 3
                Capsule()
                    .fill(index < lit ? SecreteoDesign.ember : SecreteoDesign.keyEdge)
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// The two ways a dictation shows, chosen by picture.
struct DictationIndicatorChoice: View {
    @Binding var isCompact: Bool

    var body: some View {
        HStack(spacing: 10) {
            card(selected: !isCompact, caption: Text("Capsule with your words")) { isCompact = false } picture: {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [SecreteoDesign.amber, SecreteoDesign.amber.opacity(0.2), SecreteoDesign.ember],
                            startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1.2)
                    .background(SecreteoPalette.lacquer.color, in: Capsule())
                    .frame(width: 148, height: 20)
                    .overlay {
                        HStack(spacing: 5) {
                            Capsule().fill(SecreteoPalette.capsuleText.color).frame(width: 66, height: 3)
                            Capsule().fill(SecreteoPalette.capsuleSecondaryText.color.opacity(0.6))
                                .frame(width: 22, height: 3)
                        }
                    }
            }
            .accessibilityIdentifier("settings-dictation-indicator-capsule")
            card(selected: isCompact, caption: Text("Only a small indicator")) { isCompact = true } picture: {
                SecreteoGlyph(.listening, ink: SecreteoPalette.capsuleText.color)
                    .frame(width: 26, height: 24)
            }
            .accessibilityIdentifier("settings-dictation-compact")
        }
        .modifier(SettingsArrowKeys(radius: 12) { isCompact = $0 > 0 })
    }

    private func card<Picture: View>(
        selected: Bool, caption: Text, choose: @escaping () -> Void, @ViewBuilder picture: () -> Picture
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        return Button(action: choose) {
            picture()
                .frame(maxWidth: .infinity, minHeight: 72)
                .overlay(alignment: .bottomLeading) {
                    caption
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
                        .padding(.leading, 9)
                        .padding(.bottom, 6)
                }
                .background(
                    RadialGradient(
                        colors: [SecreteoDesign.ember.opacity(0.4), .clear], center: .init(x: 0.3, y: 0),
                        startRadius: 0, endRadius: 150))
                .background(Color(nsColor: SecreteoColor.make(SecreteoPalette.window.dark)))
                .clipShape(shape)
                .overlay(shape.strokeBorder(selected ? SecreteoDesign.accent : SecreteoDesign.hairline, lineWidth: 2))
                .padding(3)
                .background(selected ? SecreteoDesign.accentWash : .clear, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A look the small indicator can add, with its picture; it waits while the capsule is chosen.
struct DictationIndicatorOption<Picture: View>: View {
    private let title: Text
    private let identifier: String
    @Binding private var isOn: Bool
    private let isAvailable: Bool
    private let picture: Picture

    init(
        _ title: Text, identifier: String, isOn: Binding<Bool>, isAvailable: Bool,
        @ViewBuilder picture: () -> Picture
    ) {
        self.title = title
        self.identifier = identifier
        _isOn = isOn
        self.isAvailable = isAvailable
        self.picture = picture()
    }

    var body: some View {
        SettingsSwitch(title, identifier: identifier, isOn: $isOn) {
            picture.accessibilityHidden(true)
        }
        .padding(.leading, 17)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.45)
    }
}

/// What Polish does to a sentence: the words heard, then the words typed.
struct DictationPolishPreview: View {
    var body: some View {
        HStack(spacing: 14) {
            column(Text("Heard")) {
                Text(heard)
                    .font(.secreteoSerif(17, italic: true))
                    .foregroundStyle(SecreteoDesign.secondaryText)
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(SecreteoDesign.accent)
                .accessibilityHidden(true)
            column(Text("Typed")) {
                Text("I will send the report tomorrow before noon.")
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-dictation-polish-preview")
    }

    private func column<Words: View>(_ title: Text, @ViewBuilder words: () -> Words) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(SecreteoDesign.tertiaryText)
            words()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heard: AttributedString {
        var filler = AttributeContainer()
        filler.strikethroughStyle = .single
        filler.strikethroughColor = SecreteoPalette.notSent.nsColor
        filler.foregroundColor = SecreteoDesign.tertiaryText
        var words = AttributedString(L10n.text("um,"), attributes: filler)
        words += AttributedString(" " + L10n.text("I will send the report tomorrow") + " ")
        words += AttributedString(L10n.text("you know,"), attributes: filler)
        words += AttributedString(" " + L10n.text("before noon"))
        return words
    }
}
