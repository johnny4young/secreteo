import AppKit
import SwiftUI

/// What dictation shows in one Settings tab. The window owns the tabs.
public struct DictationSettingsPane: View {
    let dictation: DictationFeature
    let tab: SettingsTab

    public init(dictation: DictationFeature, tab: SettingsTab) {
        self.dictation = dictation
        self.tab = tab
    }

    /// Text and Polish only hold controls of a dictation that is on.
    public static func tabs(for dictation: DictationFeature) -> [SettingsTab] {
        dictation.isEnabled ? SettingsTab.allCases : [.dictation, .history, .general]
    }

    public var body: some View {
        switch tab {
        case .dictation:
            DictationReadinessHeader(dictation: dictation)
            if dictation.practiceIsShown {
                SettingsEyebrow(Text("Try It Here"))
                SettingsCard { DictationPracticeView(dictation: dictation) }
            }
            DictationSettingsControls(dictation: dictation)
        case .text:
            DictationTextTab(dictation: dictation)
        case .polish:
            DictationPolishTab(dictation: dictation)
        case .history:
            DictationHistorySettingsSection(dictation: dictation)
            DictationStatsSettingsSection(dictation: dictation)
        case .general:
            DictationModelListSection(dictation: dictation)
            if dictation.isEnabled {
                SettingsEyebrow(Text("Model Memory"))
                SettingsCard {
                    SettingsRow(Text("Keep Model in Memory")) {
                        SettingsSegments(
                            identifier: "settings-model-memory", label: Text("Model Memory"),
                            selection: dictation.modelMemoryChoice,
                            options: [
                                .init(value: .lightweight, title: Text("Lightweight"), suffix: "lightweight"),
                                .init(value: .balanced, title: Text("Balanced"), suffix: "balanced"),
                                .init(value: .prewarmed, title: Text("At Launch"), suffix: "launch")
                            ])
                    }
                }
            }
        }
    }
}

/// Lives on the window's root, so the sheet and the model list outlive the tab that opened them.
public struct DictationSettingsHost: ViewModifier {
    let dictation: DictationFeature
    @Binding var showsPortavozImport: Bool

    public init(dictation: DictationFeature, showsPortavozImport: Binding<Bool>) {
        self.dictation = dictation
        _showsPortavozImport = showsPortavozImport
    }

    public func body(content: Content) -> some View {
        content
            .modifier(DictationModelListHost(dictation: dictation))
            .sheet(isPresented: $showsPortavozImport) {
                PortavozImportSheet(changes: dictation.portavozImport?.changes ?? []) {
                    showsPortavozImport = false
                    dictation.importPortavozPreferences()
                }
            }
            // The Settings window is reused, and either app may have changed a value since.
            .onAppear { dictation.refreshPortavozImport() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                dictation.refreshPortavozImport()
            }
            .onChange(of: dictation.preferenceRevision) { dictation.refreshPortavozImport() }
    }
}

/// Shown only while Portavoz has a setting this app does not.
public struct DictationPortavozImportRow: View {
    let dictation: DictationFeature
    @Binding var showsPortavozImport: Bool

    public init(dictation: DictationFeature, showsPortavozImport: Binding<Bool>) {
        self.dictation = dictation
        _showsPortavozImport = showsPortavozImport
    }

    public var body: some View {
        if dictation.portavozImport != nil {
            SettingsRow(Text("Import Settings from Portavoz…")) {
                Button("Import") { showsPortavozImport = true }
                    .buttonStyle(SettingsLinkStyle())
                    .accessibilityIdentifier("settings-portavoz-import")
            }
        }
    }
}

struct DictationTextTab: View {
    let dictation: DictationFeature

    var body: some View {
        let text = dictation.textSettings
        SettingsCard {
            DictationTextModePicker(
                identifier: "settings-dictation-text-mode", label: Text("Text Mode"),
                selection: Binding(get: { text.globalChoice }, set: { text.setGlobalChoice($0) }),
                recipes: text.recipes)
                .labeledContentStyle(SettingsLabeledStyle())
            SettingsSwitch(
                Text("Filter Out Filler Words"), identifier: "settings-dictation-filler",
                isOn: dictation.preference(DictationController.fillerFilterKey, default: true))
                .disabled(!text.cleanModeInUse)
            DictationDictionaryEditor(stored: dictation.preference(DictationController.replacementsKey, default: ""))
                .labeledContentStyle(SettingsLabeledStyle())
                .disabled(!text.cleanModeInUse)
        }
        SettingsCard {
            DictationProfileSettings(model: text) { await dictation.selectDictationProfileApplication() }
        }
        SettingsEyebrow(Text("Vocabulary"))
        SettingsCard {
            DictationVocabularyEditor(stored: dictation.preference("customVocabulary", default: ""))
        }
        SettingsCard {
            SettingsSwitch(
                Text("Correct the Last Dictation by Voice"), identifier: "settings-dictation-corrections",
                isOn: dictation.preference(DictationCorrections.defaultsKey, default: false))
                .help(L10n.text("Start a dictation with “change Friday to Monday”, “delete Friday” or “scratch that”."))
            SettingsSwitch(
                Text("Match Capitalization to the Cursor"), identifier: "settings-dictation-caret-case",
                isOn: dictation.preference(DictationCaretCase.defaultsKey, default: false))
        }
    }
}

struct DictationPolishTab: View {
    let dictation: DictationFeature

    var body: some View {
        let text = dictation.textSettings
        SettingsCard { DictationPolishSettings(dictation: dictation) }
        SettingsCard { DictationPolishPreview() }
        SettingsEyebrow(Text("Polish Recipes"))
        SettingsCard { DictationRecipeSettings(model: text) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings-dictation-recipes")
        SettingsEyebrow(Text("Translate and Rewrite"))
        SettingsCard {
            DictationTranslationSettings(model: text)
            SettingsSwitch(
                Text("Rewrite the Selection"), identifier: "settings-dictation-rewrite-hotkey",
                shortcut: "⌃⌥⌘R", isOn: dictation.rewriteSelectionShortcutBinding)
            if dictation.rewriteSelectionShortcutIsUnavailable {
                Text("Another shortcut already uses ⌃⌥⌘R.")
                    .foregroundStyle(SecreteoDesign.notSent)
                    .accessibilityIdentifier("settings-dictation-rewrite-taken")
            }
        }
    }
}
