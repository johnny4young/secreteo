import SwiftUI

public struct DictationSettingsSection: View {
    let dictation: DictationFeature
    @State private var showsPortavozImport = false

    public init(dictation: DictationFeature) {
        self.dictation = dictation
    }

    public var body: some View {
        Section("Dictation") {
            Toggle("Dictate Anywhere", isOn: Binding(get: { dictation.isEnabled }, set: { dictation.setEnabled($0) }))
                .accessibilityIdentifier("settings-dictation-enabled")
            DictationShortcutSettings(
                shortcut: dictation.controller.shortcut,
                isUnavailable: dictation.shortcutIsUnavailable,
                record: { dictation.recordShortcut($0) },
                recordingChanged: { dictation.shortcutRecording($0) },
                retry: { dictation.triggersChanged() })
            modelRow
            if !dictation.microphoneIsAuthorized {
                Button("Allow Microphone") { dictation.requestMicrophone() }
                    .accessibilityIdentifier("settings-dictation-microphone")
            }
            if !dictation.accessibilityIsGranted {
                Button("Allow Accessibility") { dictation.requestAccessibility() }
                    .accessibilityIdentifier("settings-dictation-accessibility")
            }
            if dictation.isEnabled, dictation.canTakeOwnership {
                Button("Use Secreteo for Dictation") { dictation.takeOwnership() }
                    .accessibilityIdentifier("settings-dictation-take-ownership")
            }
            if let message = dictation.unavailableMessage {
                Text(message)
                    .accessibilityIdentifier("settings-dictation-unavailable")
            }
            if dictation.canResetOwnership {
                Button("Reset Dictation State") { dictation.resetOwnership() }
                    .accessibilityIdentifier("settings-dictation-reset")
                if dictation.lastResetFailed {
                    Text("Could not reset dictation. Try again.")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings-dictation-reset-failed")
                }
            }
            if dictation.lastHandoffFailed {
                Text("Could not take over dictation. Try again.")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings-dictation-handoff-failed")
            }
        }
        .onAppear { dictation.refreshPortavozImport() }
        if let found = dictation.portavozImport {
            Section {
                Button("Import Settings from Portavoz…") { showsPortavozImport = true }
                    .accessibilityIdentifier("settings-portavoz-import")
            }
            .sheet(isPresented: $showsPortavozImport) {
                PortavozImportSheet(changes: found.changes) { dictation.importPortavozPreferences() }
            }
        }
        if dictation.practiceIsShown {
            Section("Try It Here") {
                DictationPracticeView(dictation: dictation)
            }
        }
        if dictation.isEnabled {
            DictationSettingsControls(dictation: dictation)
        }
    }

    @ViewBuilder private var modelRow: some View {
        switch dictation.modelState {
        case .ready:
            EmptyView()
        case .downloading:
            ProgressView("Downloading Speech Model…")
                .accessibilityIdentifier("settings-dictation-model-progress")
        case .missing, .failed:
            Button("Download Speech Model") { dictation.downloadModel() }
                .accessibilityIdentifier("settings-dictation-model-download")
            if dictation.modelState == .failed {
                Text("The download failed.")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings-dictation-model-failed")
            }
        }
    }
}
