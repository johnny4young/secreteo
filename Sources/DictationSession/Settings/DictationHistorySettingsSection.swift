import DictationKit
import SwiftUI

/// Consent for the dictation history. Every switch here starts off.
struct DictationHistorySettingsSection: View {
    let dictation: DictationFeature

    private var model: DictationHistoryModel { dictation.history }

    var body: some View {
        Section("Dictation History") {
            Toggle("Save Dictation History", isOn: binding(\.isEnabled) { await model.update(isEnabled: $0) })
                .accessibilityIdentifier("settings-dictation-history")
            if model.policy.isEnabled {
                Picker("Keep Dictations For", selection: retention) {
                    ForEach(DictationHistoryPolicy.retentionChoices, id: \.self) { days in
                        Text(L10n.format("%d days", days)).tag(days)
                    }
                }
                .accessibilityIdentifier("settings-dictation-history-retention")
                Toggle(
                    "Also Keep the Words Before Clean Mode",
                    isOn: binding(\.keepsOriginal) { await model.update(keepsOriginal: $0) })
                    .accessibilityIdentifier("settings-dictation-history-original")
            }
            if let failure = model.failure {
                Text(failure)
                    .foregroundStyle(.red)
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
