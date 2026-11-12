import Foundation
import Observation
import SwiftUI

/// The shared model folder as Settings shows it.
@MainActor
@Observable
final class DictationModelList {
    private(set) var entries: [DictationModelEntry] = []
    private(set) var removalFailed = false

    func refresh(_ models: DictationModels) async {
        entries = await models.inventory()
    }

    /// Drops this app's claim, then reads the folder again so the row shows what is left.
    func remove(_ entry: DictationModelEntry, models: DictationModels) async {
        do {
            _ = try await models.release(entry.id)
            removalFailed = false
        } catch {
            removalFailed = true
        }
        await refresh(models)
    }
}

extension DictationFeature {
    func removeModel(_ entry: DictationModelEntry) {
        guard let models = environment.models else { return }
        Task {
            await modelList.remove(entry, models: models)
            await refreshReadiness()
        }
    }
}

struct DictationModelListSection: View {
    let dictation: DictationFeature
    @State private var pendingRemoval: DictationModelEntry?

    var body: some View {
        if let models = dictation.environment.models {
            Group {
                if !dictation.modelList.entries.isEmpty {
                    Section("Speech Models") {
                        ForEach(Array(dictation.modelList.entries.enumerated()), id: \.element.id) {
                            row($1, index: $0)
                        }
                        if dictation.modelList.removalFailed {
                            Text("Could not remove the model.")
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("settings-model-remove-failed")
                        }
                    }
                }
            }
            .task {
                await dictation.modelList.refresh(models)
                for await _ in models.changes() { await dictation.modelList.refresh(models) }
            }
            .confirmationDialog(
                Text(verbatim: pendingRemoval.map { L10n.format("Remove %@?", $0.name) } ?? ""),
                isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                presenting: pendingRemoval
            ) { entry in
                Button("Remove", role: .destructive) { dictation.removeModel(entry) }
                    .accessibilityIdentifier("settings-model-remove-confirm")
            }
        }
    }

    private func row(_ entry: DictationModelEntry, index: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name)
                    .accessibilityIdentifier("settings-model-name-\(index)")
                if !entry.sharedWith.isEmpty {
                    Text(verbatim: L10n.format("Also used by %@", entry.sharedWith.formatted(.list(type: .and))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings-model-shared-\(index)")
                }
            }
            Spacer()
            if let bytes = entry.bytes {
                Text(Int64(bytes).formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-model-size-\(index)")
            }
            if entry.isClaimedByThisApp {
                Button("Remove") { pendingRemoval = entry }
                    .accessibilityIdentifier("settings-model-remove-\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-model-\(index)")
    }
}
