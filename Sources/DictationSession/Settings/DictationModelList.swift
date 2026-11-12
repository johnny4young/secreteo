import Foundation
import Observation
import SwiftUI

/// The shared model folder as Settings shows it.
@MainActor
@Observable
final class DictationModelList {
    private(set) var entries: [DictationModelEntry] = []
    private(set) var removalFailed = false
    var pendingRemoval: DictationModelEntry?

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
    /// Only a model this build pins and dictation is not using: a model in use would be claimed
    /// again on the next readiness check, and an older revision's claim retires on its own.
    func canRemove(_ entry: DictationModelEntry) -> Bool {
        guard entry.isClaimedByThisApp, let models = environment.models else { return false }
        let pinned = Set(DictationModels.Part.allCases.map(models.key))
        let inUse = Set(modelsInUse.map(models.key))
        return pinned.contains(entry.id) && !inUse.contains(entry.id)
    }

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

    var body: some View {
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

    private func row(_ entry: DictationModelEntry, index: Int) -> some View {
        let locale = AppLanguage.current.locale
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name)
                    .accessibilityIdentifier("settings-model-name-\(index)")
                if !entry.sharedWith.isEmpty {
                    Text(verbatim: L10n.format(
                        "Also used by %@", entry.sharedWith.formatted(.list(type: .and).locale(locale))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings-model-shared-\(index)")
                }
            }
            Spacer()
            if let bytes = entry.bytes {
                Text(verbatim: Int64(bytes).formatted(.byteCount(style: .file).locale(locale)))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-model-size-\(index)")
            }
            if dictation.canRemove(entry) {
                Button("Remove") { dictation.modelList.pendingRemoval = entry }
                    .accessibilityIdentifier("settings-model-remove-\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-model-\(index)")
    }
}

/// Lives on a view that always shows, so the list keeps refreshing after its last row goes away.
struct DictationModelListHost: ViewModifier {
    let dictation: DictationFeature

    func body(content: Content) -> some View {
        content
            .task {
                guard let models = dictation.environment.models else { return }
                await dictation.modelList.refresh(models)
                for await _ in models.changes() { await dictation.modelList.refresh(models) }
            }
            .confirmationDialog(
                Text(verbatim: dictation.modelList.pendingRemoval.map { L10n.format("Remove %@?", $0.name) } ?? ""),
                isPresented: Binding(
                    get: { dictation.modelList.pendingRemoval != nil },
                    set: { if !$0 { dictation.modelList.pendingRemoval = nil } }),
                presenting: dictation.modelList.pendingRemoval
            ) { entry in
                Button("Remove", role: .destructive) { dictation.removeModel(entry) }
                    .accessibilityIdentifier("settings-model-remove-confirm")
            }
    }
}
