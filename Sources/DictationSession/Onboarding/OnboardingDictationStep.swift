import SwiftUI

/// Onboarding step for system-wide dictation. The switch starts off, so
/// continuing past the step never registers a global shortcut.
struct OnboardingDictationStep: View {
    let dictation: DictationFeature

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Dictate Anywhere")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("onboarding-dictation")
                Toggle("Turn On Dictation", isOn: Binding(
                    get: { dictation.isEnabled }, set: { dictation.setEnabled($0) }))
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("onboarding-dictation-toggle")
                if dictation.isEnabled {
                    DictationShortcutSettings(
                        shortcut: dictation.controller.shortcut,
                        isUnavailable: dictation.shortcutIsUnavailable,
                        record: { dictation.recordShortcut($0) },
                        recordingChanged: { dictation.shortcutRecording($0) },
                        retry: { dictation.triggersChanged() })
                    DictationPermissionRows(dictation: dictation)
                }
            }
        }
    }
}

/// macOS posts no change notification for Accessibility, so the rows check
/// once a second while they are visible.
private struct DictationPermissionRows: View {
    let dictation: DictationFeature

    var body: some View {
        VStack(spacing: 8) {
            row(icon: "mic", title: Text("Microphone")) {
                if dictation.microphoneIsAuthorized {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("onboarding-microphone-allowed")
                } else {
                    Button("Allow") { dictation.requestMicrophone() }
                        .controlSize(.small)
                        .accessibilityIdentifier("onboarding-microphone-allow")
                }
            }
            row(icon: "accessibility", title: Text("Accessibility")) {
                if dictation.accessibilityIsGranted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("onboarding-accessibility-allowed")
                } else {
                    Button("Allow") { dictation.requestAccessibility() }
                        .controlSize(.small)
                        .accessibilityIdentifier("onboarding-accessibility-allow")
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await dictation.refreshPermissionsIfChanged()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func row(icon: String, title: Text, @ViewBuilder status: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22).accessibilityHidden(true)
            title.font(.callout.weight(.medium))
            Spacer()
            status()
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
