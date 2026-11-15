import DictationSession
import SwiftUI

/// The status item's content. UI tests mount this same view in a window, because the
/// status item itself cannot be automated reliably.
public struct MenuContentView: View {
    static let width: CGFloat = 320

    private let model: AppModel
    /// Runs a row whose words go to the app with focus.
    private let inTargetApp: @MainActor (@escaping @MainActor () -> Void) -> Void

    public init(
        model: AppModel, inTargetApp: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { $0() }
    ) {
        self.model = model
        self.inTargetApp = inTargetApp
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let dictation = model.dictation {
                DictationMenuDashboard(dictation: dictation, openSettings: model.openSettings, inTargetApp: inTargetApp)
                Divider()
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                if dictation.canRewriteSelection {
                    MenuRow(title: "Rewrite Selection…", shortcut: dictation.rewriteSelectionShortcutLabel,
                            identifier: "menu-bar-rewrite-selection") {
                        inTargetApp { dictation.rewriteSelection() }
                    }
                }
                MenuRow(title: "Dictation History…", identifier: "menu-bar-history") { model.openHistory() }
            }
            if model.updateIsAvailable {
                MenuRow(title: "Update Available…", identifier: "menu-update-available", action: model.checkForUpdates)
            }
            MenuRow(title: "Settings…", shortcut: "⌘,", key: ",", identifier: "menu-settings") { model.openSettings() }
            if model.canCheckForUpdates {
                MenuRow(title: "Check for Updates…", identifier: "menu-check-updates", action: model.checkForUpdates)
            }
            MenuRow(title: "Quit Secreteo", shortcut: "⌘Q", identifier: "menu-quit", action: model.quit)
        }
        .padding(14)
        .frame(width: Self.width)
        .background(SecreteoDesign.windowBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-content")
        .tint(SecreteoDesign.accent)
    }
}

private struct MenuRow: View {
    let title: LocalizedStringKey
    var shortcut: String?
    /// Set when the shortcut works only while the menu is open; the main menu owns the others.
    var key: KeyEquivalent?
    let identifier: String
    let action: () -> Void
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let isLit = isHovered || isFocused
        Button(action: action) {
            // Inside the label: a plain button only responds where its label has a shape.
            HStack(spacing: 10) {
                Text(title)
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(isLit ? SecreteoDesign.onAccent : SecreteoDesign.tertiaryText)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(isLit ? SecreteoDesign.onAccent : SecreteoDesign.text)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(isLit ? SecreteoDesign.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: .command) })
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(identifier)
    }
}
