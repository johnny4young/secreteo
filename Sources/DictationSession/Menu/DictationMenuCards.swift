import DictationKit
import SwiftUI

/// The last dictation, shown only while Paste Last can still deliver it.
struct DictationMenuLastCard: View {
    let dictation: DictationFeature
    let entry: DictationLastText.Entry
    let inTargetApp: @MainActor (@escaping @MainActor () -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(DictationMenuFormat.eyebrow(app: entry.app))
                    .lineLimit(1)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(DictationMenuFormat.age(of: entry.storedAt, now: context.date))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(DictationMenuStyle.eyebrow)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(SecreteoDesign.tertiaryText)
            Text(entry.text)
                .font(.secreteoSerif(18))
                .foregroundStyle(SecreteoDesign.text)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("menu-last-dictation-text")
            Divider()
            Button {
                inTargetApp { dictation.pasteLast() }
            } label: {
                HStack {
                    Text("Paste Last Dictation")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SecreteoDesign.accent)
                    Spacer(minLength: 8)
                    if let shortcut = dictation.pasteLastShortcutLabel {
                        Text(shortcut)
                            .font(DictationMenuStyle.shortcut)
                            .foregroundStyle(SecreteoDesign.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DictationMenuPressStyle())
            .accessibilityLabel(L10n.text("Paste Last Dictation"))
            .accessibilityIdentifier("menu-bar-paste-last")
            if dictation.canPasteUnpolished {
                alternate(L10n.text("Paste Without Polish"), identifier: "menu-bar-paste-unpolished")
            }
            if dictation.canPasteOriginal {
                alternate(L10n.text("Paste the Original"), identifier: "menu-bar-paste-original")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(SecreteoPalette.card.color, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(SecreteoDesign.text.opacity(0.09))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-last-dictation")
    }

    private func alternate(_ title: String, identifier: String) -> some View {
        Button {
            inTargetApp { dictation.pasteLast(alternate: true) }
        } label: {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(SecreteoDesign.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(DictationMenuPressStyle())
        .accessibilityIdentifier(identifier)
    }
}

/// Today's words over the last seven days, with today's bar in amber.
struct DictationMenuToday: View {
    let today: DictationStatsTotals
    let days: [DictationStatsDay]

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Today")
                    .font(DictationMenuStyle.eyebrow)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(SecreteoDesign.tertiaryText)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(today.words.formatted(.number.locale(AppLanguage.current.locale)))
                        .font(.secreteoSerif(38))
                        .monospacedDigit()
                        .foregroundStyle(SecreteoDesign.text)
                    Text(today.words == 1 ? L10n.text("word") : L10n.text("words"))
                        .font(.secreteoSerif(20, italic: true))
                        .foregroundStyle(SecreteoDesign.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("menu-today-words")
                Text(DictationMenuFormat.detail(today))
                    .font(.system(size: 11))
                    .foregroundStyle(SecreteoDesign.secondaryText)
                    .accessibilityIdentifier("menu-today-detail")
            }
            Spacer(minLength: 0)
            bars
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-today")
    }

    private var bars: some View {
        let heights = DictationMenuFormat.bars(days)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(index == heights.count - 1 ? SecreteoDesign.amber : SecreteoDesign.accent.opacity(0.65))
                    .frame(width: 8, height: max(3, 36 * height))
            }
        }
        .frame(height: 36, alignment: .bottom)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }
}
