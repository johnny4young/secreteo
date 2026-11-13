import SwiftUI

/// The status item's content. UI tests mount this same view in a window, because the
/// status item itself cannot be automated reliably.
public struct MenuContentView: View {
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
        VStack(alignment: .leading, spacing: 4) {
            if let dictation = model.dictation {
                if dictation.isActive {
                    MenuRow(title: "Stop Dictating", identifier: "menu-bar-dictate") {
                        inTargetApp { dictation.toggleDictation() }
                    }
                } else if dictation.canDictate {
                    MenuRow(title: "Dictate", identifier: "menu-bar-dictate") {
                        inTargetApp { dictation.toggleDictation() }
                    }
                } else if dictation.isEnabled, dictation.canTakeOwnership {
                    MenuRow(title: "Use Secreteo for Dictation", identifier: "menu-bar-take-ownership") {
                        dictation.takeOwnership()
                    }
                } else {
                    MenuRow(title: "Set Up Dictation…", identifier: "menu-bar-set-up-dictation") {
                        model.openSettings()
                    }
                }
                if dictation.canPasteLast {
                    MenuRow(title: "Paste Last Dictation", identifier: "menu-bar-paste-last") {
                        inTargetApp { dictation.pasteLast() }
                    }
                }
                if dictation.canRewriteSelection {
                    MenuRow(title: "Rewrite Selection…", identifier: "menu-bar-rewrite-selection") {
                        inTargetApp { dictation.rewriteSelection() }
                    }
                }
                if dictation.canPasteUnpolished {
                    MenuRow(title: "Paste Without Polish", identifier: "menu-bar-paste-unpolished") {
                        inTargetApp { dictation.pasteLast(alternate: true) }
                    }
                }
                if dictation.canPasteOriginal {
                    MenuRow(title: "Paste the Original", identifier: "menu-bar-paste-original") {
                        inTargetApp { dictation.pasteLast(alternate: true) }
                    }
                }
                MenuRow(title: "Dictation History…", identifier: "menu-bar-history") { model.openHistory() }
                Divider()
            }
            if model.updateIsAvailable {
                MenuRow(title: "Update Available…", identifier: "menu-update-available", action: model.checkForUpdates)
                Divider()
            }
            MenuRow(title: "Settings…", identifier: "menu-settings", action: model.openSettings)
            if model.canCheckForUpdates {
                MenuRow(title: "Check for Updates…", identifier: "menu-check-updates", action: model.checkForUpdates)
            }
            Divider()
            MenuRow(title: "Quit Secreteo", identifier: "menu-quit", action: model.quit)
        }
        .padding(8)
        .frame(width: 220)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-content")
    }
}

private struct MenuRow: View {
    let title: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Inside the label: a plain button only responds where its label has a shape.
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
