import SwiftUI

/// The dictation half of the menu: the state, the one primary action, the last
/// dictation while it can still be pasted, and today's count.
public struct DictationMenuDashboard: View {
    private let dictation: DictationFeature
    private let openSettings: () -> Void
    /// Runs an action whose words go to the app with focus.
    private let inTargetApp: @MainActor (@escaping @MainActor () -> Void) -> Void

    public init(
        dictation: DictationFeature, openSettings: @escaping () -> Void,
        inTargetApp: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void
    ) {
        self.dictation = dictation
        self.openSettings = openSettings
        self.inTargetApp = inTargetApp
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            primaryAction
            if let entry = dictation.lastDictation {
                DictationMenuLastCard(dictation: dictation, entry: entry, inTargetApp: inTargetApp)
            }
            if dictation.stats.isEnabled, dictation.stats.week.totals.dictations > 0,
               let today = dictation.stats.today {
                DictationMenuToday(today: today, days: dictation.stats.week.days)
            }
        }
        .task { await dictation.stats.refreshWeek() }
    }

    private var header: some View {
        let owns = dictation.menuState == .ready || dictation.menuState == .live
        return HStack(spacing: 12) {
            SecreteoGlyph(
                dictation.statusFace,
                ink: (owns ? SecreteoPalette.capsuleText : SecreteoPalette.capsuleSecondaryText).color)
                .frame(width: 26, height: 24)
                .frame(width: 44, height: 44)
                .background(DictationMenuStyle.well, in: Circle())
                .overlay { Circle().strokeBorder(DictationMenuStyle.rim) }
                .shadow(color: SecreteoDesign.amber.opacity(owns ? 0.45 : 0), radius: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(dictation.menuTitle)
                    .font(.secreteoSerif(30))
                    .foregroundStyle(SecreteoDesign.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Without this the well's height counts as too little room and shrinks the title.
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("menu-state-title")
                if let detail = dictation.menuDetail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(SecreteoDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("menu-state-detail")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-state")
    }

    /// The key caps, as VoiceOver reads them.
    private var triggers: String {
        [dictation.holdKeyLabel.map { "\(L10n.text("hold")) \($0)" }, dictation.dictationShortcutLabel]
            .compactMap { $0 }.joined(separator: ", ")
    }

    @ViewBuilder private var primaryAction: some View {
        switch dictation.menuState {
        case .ready, .live:
            Button {
                inTargetApp { dictation.toggleDictation() }
            } label: {
                DictationMenuCapsuleLabel(
                    title: dictation.isActive ? L10n.text("Stop Dictating") : L10n.text("Dictate"), showsGlyph: true,
                    holdKey: dictation.holdKeyLabel, shortcut: dictation.dictationShortcutLabel)
            }
            .buttonStyle(DictationMenuPressStyle())
            .accessibilityLabel(dictation.isActive ? L10n.text("Stop Dictating") : L10n.text("Dictate"))
            .accessibilityValue(triggers)
            .accessibilityIdentifier("menu-bar-dictate")
        case .standingBy:
            Button(action: dictation.takeOwnership) {
                Text("Use Secreteo for Dictation")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SecreteoPalette.capsuleInk.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(SecreteoPalette.capsuleAccent.color, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(DictationMenuPressStyle())
            .accessibilityIdentifier("menu-bar-take-ownership")
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DictationMenuStyle.capsule, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(DictationMenuStyle.rim) }
        case .setUp, .notReady:
            // Another app or a damaged state has its own instruction in Settings, not a setup step.
            let step = dictation.unavailableMessage == nil ? dictation.setupStep : nil
            Button {
                if let step { dictation.perform(step, openSettings: openSettings) } else { openSettings() }
            } label: {
                DictationMenuCapsuleLabel(
                    title: step?.title ?? L10n.text("Set Up Dictation…"), showsGlyph: false, holdKey: nil,
                    shortcut: nil,
                    progress: step == .downloadingModel ? .some(dictation.modelDownloadFraction) : nil)
            }
            .buttonStyle(DictationMenuPressStyle())
            .disabled(step == .downloadingModel)
            .accessibilityIdentifier("menu-bar-set-up-dictation")
        }
    }
}

enum DictationMenuStyle {
    static let capsule = LinearGradient(
        colors: [SecreteoPalette.capsuleHighlight.color, SecreteoPalette.lacquer.color],
        startPoint: .top, endPoint: .bottom)
    static let well = RadialGradient(
        colors: [SecreteoPalette.capsuleHighlight.color, SecreteoPalette.lacquer.color],
        center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 24)
    /// Keeps the dark surfaces apart from a dark window.
    static let rim = SecreteoPalette.capsuleText.color.opacity(0.12)
    static let eyebrow = Font.system(size: 9.5, weight: .medium, design: .monospaced)
    static let shortcut = Font.system(size: 11.5, design: .monospaced)
}

struct DictationMenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// The always-dark capsule: the action on the left, its real triggers as key caps on the right.
private struct DictationMenuCapsuleLabel: View {
    let title: String
    let showsGlyph: Bool
    let holdKey: String?
    let shortcut: String?
    /// Set while a download runs; an inner nil is a download that has not reported bytes yet.
    var progress: Double??

    var body: some View {
        HStack(spacing: 7) {
            if showsGlyph {
                SecreteoGlyph(.listening, ink: SecreteoPalette.capsuleText.color)
                    .frame(width: 22, height: 20)
            }
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SecreteoPalette.capsuleText.color)
                .lineLimit(1)
                .padding(.leading, showsGlyph ? 3 : 0)
            Spacer(minLength: 4)
            if let holdKey {
                word(L10n.text("hold"))
                keyCap(holdKey, isHeld: true)
                if shortcut != nil { word(L10n.text("or")) }
            }
            if let shortcut { keyCap(shortcut, isHeld: false) }
            if let progress {
                ProgressView(value: progress)
                    .controlSize(.small)
                    .frame(width: 60)
                    .tint(SecreteoPalette.capsuleAmber.color)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(DictationMenuStyle.capsule, in: Capsule())
        .overlay { Capsule().strokeBorder(DictationMenuStyle.rim) }
        .contentShape(Capsule())
    }

    private func word(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
    }

    private func keyCap(_ label: String, isHeld: Bool) -> some View {
        Text(label)
            .font(.system(size: 11, weight: isHeld ? .semibold : .medium))
            .foregroundStyle((isHeld ? SecreteoPalette.capsuleInk : SecreteoPalette.capsuleText).color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(isHeld ? SecreteoPalette.capsuleAmber.color : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                if !isHeld {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(SecreteoPalette.capsuleText.color.opacity(0.25))
                }
            }
    }
}
