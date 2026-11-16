import DictationKit
import SwiftUI

/// Consent for the dictation history. Every switch here starts off.
struct DictationHistorySettingsSection: View {
    let dictation: DictationFeature

    private var model: DictationHistoryModel { dictation.history }

    var body: some View {
        SettingsEyebrow(Text("Dictation History"))
        SettingsCard {
            SettingsSwitch(
                Text("Save Dictation History"), identifier: "settings-dictation-history",
                isOn: binding(\.isEnabled) { await model.update(isEnabled: $0) })
            if model.policy.isEnabled {
                SettingsRow(Text("Keep Dictations For")) {
                    Picker(selection: retention) {
                        ForEach(DictationHistoryPolicy.retentionChoices, id: \.self) { days in
                            Text(L10n.format("%d days", days)).tag(days)
                        }
                    } label: {
                        Text("Keep Dictations For")
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings-dictation-history-retention")
                }
                SettingsSwitch(
                    Text("Also Keep the Words Before Clean Mode"), identifier: "settings-dictation-history-original",
                    isOn: binding(\.keepsOriginal) { await model.update(keepsOriginal: $0) })
                SettingsSwitch(
                    Text("Let Agents and Shortcuts Read History"), identifier: "settings-dictation-history-agents",
                    isOn: binding(\.exposesToAgents) { await model.update(exposesToAgents: $0) })
            }
            if let failure = model.failure {
                Text(failure)
                    .foregroundStyle(SecreteoDesign.notSent)
                    .accessibilityIdentifier("settings-dictation-history-error")
            }
        }
        .task { if !model.isLoaded { await model.load() } }
    }

    private var retention: Binding<Int> {
        Binding(
            get: { model.policy.retentionDays },
            set: { days in Task { await model.update(retentionDays: days) } })
    }

    private func binding(
        _ keyPath: KeyPath<DictationHistoryPolicy, Bool>, update: @escaping (Bool) async -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { model.policy[keyPath: keyPath] },
            set: { value in Task { await update(value) } })
    }
}
