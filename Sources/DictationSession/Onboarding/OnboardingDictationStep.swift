import SwiftUI

/// Onboarding step for system-wide dictation. The switch starts off, so
/// continuing past the step never registers a global shortcut.
struct OnboardingDictationStep: View {
    let dictation: DictationFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTitle(title: L10n.text("Dictate Anywhere"), identifier: "onboarding-dictation")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    rows
                    if dictation.isEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            DictationShortcutSettings(
                                shortcut: dictation.controller.shortcut,
                                isUnavailable: dictation.shortcutIsUnavailable,
                                record: { dictation.recordShortcut($0) },
                                recordingChanged: { dictation.shortcutRecording($0) },
                                retry: { dictation.triggersChanged() })
                            if dictation.fnKeyConflicts {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("So macOS doesn't also react, set “Press 🌐 key to” to “Do Nothing”.")
                                        .foregroundStyle(SecreteoDesign.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("onboarding-dictation-modifier-fn-note")
                                    Spacer(minLength: 4)
                                    Button("Open Keyboard Settings") { dictation.openKeyboardSettings() }
                                        .buttonStyle(SettingsLinkStyle())
                                        .accessibilityIdentifier("onboarding-dictation-modifier-fn-settings")
                                }
                            }
                        }
                        .font(.system(size: 13))
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // macOS posts no change notification for Accessibility, so the rows check once a second.
        .task {
            while !Task.isCancelled {
                await dictation.refreshPermissionsIfChanged()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row(title: Text("Microphone")) {
                Image(systemName: "mic")
            } status: {
                permission(
                    isGranted: dictation.microphoneIsAuthorized,
                    allowed: "onboarding-microphone-allowed", allow: "onboarding-microphone-allow"
                ) { dictation.requestMicrophone() }
            }
            Rectangle().fill(SecreteoDesign.hairline).frame(height: 1)
            row(title: Text("Accessibility")) {
                Image(systemName: "accessibility")
            } status: {
                permission(
                    isGranted: dictation.accessibilityIsGranted,
                    allowed: "onboarding-accessibility-allowed", allow: "onboarding-accessibility-allow"
                ) { dictation.requestAccessibility() }
            }
            Rectangle().fill(SecreteoDesign.hairline).frame(height: 1)
            row(title: Text("Turn On Dictation")) {
                SecreteoGlyph(.ready, ink: SecreteoDesign.accent, tinted: false).frame(width: 22, height: 20)
            } status: {
                Toggle(L10n.text("Turn On Dictation"), isOn: Binding(
                    get: { dictation.isEnabled }, set: { dictation.setEnabled($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("onboarding-dictation-toggle")
            }
        }
        .onboardingCard()
    }

    @ViewBuilder
    private func permission(
        isGranted: Bool, allowed: String, allow: String, request: @escaping () -> Void
    ) -> some View {
        if isGranted {
            Label("Allowed", systemImage: "checkmark")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(SecreteoDesign.verified)
                .accessibilityIdentifier(allowed)
        } else {
            Button("Allow", action: request)
                .buttonStyle(OnboardingButtonStyle(kind: .primary, isCompact: true))
                .accessibilityIdentifier(allow)
        }
    }

    private func row(
        title: Text, @ViewBuilder icon: () -> some View, @ViewBuilder status: () -> some View
    ) -> some View {
        HStack(spacing: 14) {
            icon()
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SecreteoDesign.accent)
                .frame(width: 38, height: 38)
                .background(SecreteoDesign.control, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            title.font(.system(size: 14.5, weight: .semibold)).foregroundStyle(SecreteoDesign.text)
            Spacer()
            status()
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
    }
}
