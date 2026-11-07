import SwiftUI

/// Consent for dictation statistics, separate from the history and off by default.
struct DictationStatsSettingsSection: View {
    let dictation: DictationFeature
    @State private var confirmingDelete = false

    private var model: DictationStatsModel { dictation.stats }

    // Modifiers on a Form section reach every row, so each row carries its own.
    var body: some View {
        Section("Dictation Statistics") {
            Toggle("Keep Dictation Statistics", isOn: Binding(
                get: { model.isEnabled },
                set: { value in Task { await model.update(isEnabled: value) } }))
                .accessibilityIdentifier("settings-dictation-stats")
            Button("Delete Statistics", role: .destructive) { confirmingDelete = true }
                .accessibilityIdentifier("settings-dictation-stats-delete")
                .confirmationDialog(
                    Text("Delete your dictation statistics?"), isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete Statistics", role: .destructive) { Task { await model.deleteAll() } }
                        .accessibilityIdentifier("settings-dictation-stats-delete-confirm")
                }
            if let failure = model.failure {
                Text(failure)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings-dictation-stats-error")
            }
        }
    }
}
