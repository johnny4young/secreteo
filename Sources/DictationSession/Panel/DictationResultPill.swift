import SwiftUI

/// The capsule after a verified insertion: it contracts to its words, holds and fades.
struct DictationResultPill: View {
    let controller: DictationController
    let words: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var faded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DictationPanelLayout.noticeSpacing) {
            pill
            if let notice = controller.polishNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dictation-panel-polish-notice")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(SecreteoPalette.lacquer.color.opacity(0.94), in: RoundedRectangle(cornerRadius: 11))
            }
        }
        .frame(width: DictationPanelLayout.width, alignment: .leading)
        .opacity(faded || (reduceMotion && !settled) ? 0 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: DictationPanelLayout.resultContraction)) { settled = true }
        }
        .task(id: fades) {
            faded = false
            guard fades else { return }
            try? await Task.sleep(for: DictationPanelLayout.resultHold)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { faded = true }
        }
    }

    private var fades: Bool {
        DictationPanelLayout.resultFades(
            showsNotice: controller.polishNotice != nil, offersCorrection: controller.learnableCorrection != nil)
    }

    private var pill: some View {
        HStack(spacing: 8) {
            SecreteoGlyph(.inserted, ink: SecreteoPalette.capsuleText.color)
                .frame(width: 28, height: 26)
            Text(controller.correctionSummary ?? insertedTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SecreteoPalette.capsuleText.color)
                .lineLimit(1)
                .accessibilityIdentifier("dictation-panel-delivery-status")
                // Read right after the title and from its place, never from an empty spot.
                .overlay(alignment: .leading) { if !controller.historySaveFailed { kept(visible: false) } }
            if controller.historySaveFailed { kept(visible: true).fixedSize() }
            if let learnable = controller.learnableCorrection {
                Button { controller.learnCorrection() } label: {
                    Text(L10n.format("Always write “%@”", learnable.rule.replacement))
                        .lineLimit(1)
                        .modifier(DictationCapsuleChip(ink: SecreteoPalette.capsuleAccent.color))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(L10n.format(
                    "Adds “%@” → “%@” to your text replacements.", learnable.rule.trigger, learnable.rule.replacement))
                .accessibilityIdentifier("dictation-panel-learn-correction")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, controller.learnableCorrection == nil ? 22 : 14)
        // Reduce Motion skips the contraction: the pill cross-fades in at its own width.
        .frame(maxWidth: settled || reduceMotion ? nil : .infinity, alignment: .leading)
        .frame(height: DictationPanelLayout.capsuleHeight)
        .background { DictationLacquer() }
        .clipShape(Capsule())
        .overlay { DictationRimStroke(style: .verified, outline: Capsule(), end: 0.16) }
    }

    /// What Secreteo kept is read aloud on every pill and drawn only when saving failed.
    private func kept(visible: Bool) -> some View {
        Text(controller.deliveryPrivacyLine)
            .font(.system(size: visible ? 12 : 15, weight: visible ? .regular : .medium))
            .foregroundStyle(visible ? SecreteoPalette.capsuleNotSent.color : .clear)
            .lineLimit(1)
            .frame(maxWidth: visible ? nil : .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityIdentifier("dictation-panel-delivery-detail")
    }

    private var insertedTitle: String {
        if let target = controller.targetApp {
            return L10n.format("%d words in %@", words, target)
        }
        return L10n.format("%d words inserted.", words)
    }
}
