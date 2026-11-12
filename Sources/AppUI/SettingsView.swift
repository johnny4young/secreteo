import DictationSession
import SwiftUI

public struct SettingsView: View {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            if let dictation = model.dictation {
                DictationSettingsSection(dictation: dictation)
            }
            if model.dictationFailedToStart {
                Section {
                    Text("Dictation could not start.")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings-dictation-failed-to-start")
                }
            }
            Section {
                Toggle("Open at Login", isOn: launchBinding)
                    .accessibilityIdentifier("settings-launch-at-login")
                if model.launchAtLoginFailed {
                    Text("Could not change this setting.")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings-launch-at-login-error")
                }
            }
            Section("About") {
                LabeledContent("Version", value: model.versionDescription)
                    .accessibilityIdentifier("settings-version")
                if model.canCheckForUpdates {
                    Button("Check for Updates…") { model.checkForUpdates() }
                        .accessibilityIdentifier("settings-check-updates")
                }
                LabeledContent("License") { Text(verbatim: "MIT") }
                    .accessibilityIdentifier("settings-license")
                // CC BY 4.0 requires naming the authors wherever the models are used.
                LabeledContent("Speech Recognition") { Text("Parakeet by NVIDIA, CC BY 4.0") }
                    .accessibilityIdentifier("settings-credit-parakeet")
                LabeledContent("Voice Detection") { Text("Silero VAD by Silero Team, MIT") }
                    .accessibilityIdentifier("settings-credit-silero")
                Link(destination: AppModel.sourceCode) { Text("Source Code") }
                    .accessibilityIdentifier("settings-source-code")
                Button("Third-Party Notices") { model.openNotices() }
                    .accessibilityIdentifier("settings-open-notices")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-root")
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
    }
}
