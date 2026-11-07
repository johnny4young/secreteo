import LiveSpeech
import LocalModelStore
import SwiftUI

extension DictationFeature {
    var speechEngine: LiveSpeechSelection {
        _ = preferenceRevision
        return LiveSpeechSelection.dictation(defaults: defaults)
    }

    var speechEngineBinding: Binding<LiveSpeechSelection> {
        Binding(
            get: { self.speechEngine },
            set: {
                self.store([LiveSpeechSelection.dictationKey: $0.rawValue])
                self.speechEngineChanged()
            })
    }

    /// The warm model may be the other checkpoint, so the next dictation loads afresh.
    func speechEngineChanged() {
        warmEngine.release()
        prewarmIfConfigured()
    }

    /// Settings asks only while Ultra is chosen, so nobody else hashes 632 MB they never use.
    func refreshUltra() async {
        guard speechEngine == .parakeetUltra, let models = environment.models else { return }
        await ultra.refresh(models)
    }

    func downloadUltra() {
        guard let models = environment.models else { return }
        ultra.download(models) { [weak self] in self?.speechEngineChanged() }
    }

    /// Ultra loads only once chosen and installed; until then dictation keeps v3.
    nonisolated static func loadSpeechModel(
        store: LocalModelStore, defaults: UserDefaults
    ) async throws -> ParakeetEngine {
        if LiveSpeechSelection.dictation(defaults: defaults) == .parakeetUltra,
           let ultra = await store.verifiedInstallation(ModelCatalog.parakeetUltra) {
            return try await ParakeetEngine.load(fromVerifiedDirectory: ultra.directory, checkpoint: .ultra)
        }
        guard let installed = await store.verifiedInstallation(ModelCatalog.parakeetTdtV3) else {
            throw DictationFeatureError.modelMissing
        }
        return try await ParakeetEngine.load(fromVerifiedDirectory: installed.directory)
    }
}
