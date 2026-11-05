import SwiftUI

/// Presentation of the one process-owned registration. Retrying a shortcut
/// never begins capture or asks for microphone/Accessibility permission.
struct DictationShortcutSettings: View {
    let shortcut: DictationShortcut
    let isUnavailable: Bool
    let record: (HotkeySetting) -> Void
    let recordingChanged: (Bool) -> Void
    let retry: () -> Void

    var body: some View {
        HotkeyRecorder(setting: shortcut.setting, onRecord: record, onRecordingChange: recordingChanged)
        if shortcut.usedFallback {
            Text(L10n.format(
                "The saved shortcut is invalid. Using %@ instead.",
                shortcut.setting.label))
                .accessibilityIdentifier("settings-dictation-shortcut-recovered")
        }
        if isUnavailable {
            Text("Another app is using this shortcut.")
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings-dictation-shortcut-unavailable")
            Button("Retry Shortcut", action: retry)
                .accessibilityIdentifier("settings-dictation-shortcut-retry")
        }
        if shortcut.usedFallback || shortcut.setting != .default {
            Button("Use Default Shortcut") { record(.default) }
                .accessibilityIdentifier("settings-dictation-shortcut-default")
        }
    }
}
