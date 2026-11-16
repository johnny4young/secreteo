import SwiftUI

/// The switch for dictation and what it still needs. A missing item is its own fix.
struct DictationReadinessHeader: View {
    let dictation: DictationFeature

    var body: some View {
        HStack(spacing: 13) {
            mark
            VStack(alignment: .leading, spacing: 3) {
                Text("Dictate Anywhere")
                    .font(.secreteoSerif(24))
                    .accessibilityHidden(true)
                SettingsFlow {
                    if isReady { check(Text("Ready")) }
                    model
                    if dictation.microphoneIsAuthorized {
                        check(Text("Microphone"))
                    } else {
                        Button("Allow Microphone") { dictation.requestMicrophone() }
                            .accessibilityIdentifier("settings-dictation-microphone")
                    }
                    if dictation.accessibilityIsGranted {
                        check(Text("Accessibility"))
                    } else {
                        Button("Allow Accessibility") { dictation.requestAccessibility() }
                            .accessibilityIdentifier("settings-dictation-accessibility")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(SecreteoDesign.secondaryText)
                .buttonStyle(SettingsLinkStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: Binding(get: { dictation.isEnabled }, set: { dictation.setEnabled($0) })) {
                Text("Dictate Anywhere")
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityIdentifier("settings-dictation-enabled")
        }
        .padding(.leading, 15)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 74)
        .background(SecreteoDesign.card, in: shape)
        .overlay(shape.strokeBorder(SecreteoDesign.hairline).allowsHitTesting(false))
        if hasStatus {
            SettingsCard { status }
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 37) }

    private var mark: some View {
        SecreteoGlyph(.listening, ink: SecreteoPalette.capsuleText.color)
            .frame(width: 28, height: 26)
            .frame(width: 46, height: 46)
            .background(
                LinearGradient(
                    colors: [SecreteoDesign.ember, Color(nsColor: SecreteoColor.make(SecreteoPalette.accent.light))],
                    startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 11))
    }

    private var isReady: Bool {
        dictation.isEnabled && dictation.canDictate && dictation.modelState == .ready
            && dictation.microphoneIsAuthorized && dictation.accessibilityIsGranted
    }

    private func check(_ title: Text) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(SecreteoDesign.verified)
                .accessibilityHidden(true)
            title
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var model: some View {
        switch dictation.modelState {
        case .ready:
            check(Text("Speech model on this Mac"))
        case .downloading:
            HStack(spacing: 6) {
                Text("Downloading Speech Model…")
                    .accessibilityHidden(true)
                ProgressView(value: dictation.modelDownloadFraction)
                    .frame(width: 70)
                    .controlSize(.small)
                    .accessibilityLabel(L10n.text("Downloading Speech Model…"))
                    .accessibilityIdentifier("settings-dictation-model-progress")
            }
        case .missing, .failed:
            Button("Download Speech Model") { dictation.downloadModel() }
                .accessibilityIdentifier("settings-dictation-model-download")
        }
    }

    private var hasStatus: Bool {
        dictation.modelState == .failed || (dictation.isEnabled && dictation.canTakeOwnership)
            || dictation.unavailableMessage != nil || dictation.canResetOwnership || dictation.lastHandoffFailed
    }

    @ViewBuilder private var status: some View {
        if dictation.modelState == .failed {
            Text("The download failed.")
                .foregroundStyle(SecreteoDesign.notSent)
                .accessibilityIdentifier("settings-dictation-model-failed")
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
                    .foregroundStyle(SecreteoDesign.notSent)
                    .accessibilityIdentifier("settings-dictation-reset-failed")
            }
        }
        if dictation.lastHandoffFailed {
            Text("Could not take over dictation. Try again.")
                .foregroundStyle(SecreteoDesign.notSent)
                .accessibilityIdentifier("settings-dictation-handoff-failed")
        }
    }
}
