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

    var speechModelIsRequired: Bool { speechEngine != .appleSpeech }

    /// Apple Speech still runs the speech gate and auto-stop on the detector.
    var requiredModels: [DictationModels.Part] {
        speechModelIsRequired ? DictationModels.Part.required : [.speechDetector]
    }

    /// What dictation keeps a claim on: nothing while it is off, so a removal stays removed.
    var modelsInUse: [DictationModels.Part] {
        guard isEnabled else { return [] }
        return requiredModels + (speechEngine == .parakeetUltra ? [.speechUltra] : [])
    }

    /// Apple Speech requires a concrete locale rather than Auto.
    static func preferredConcreteLanguage(locale: Locale = AppLanguage.current.locale) -> String {
        locale.language.languageCode?.identifier == "es" ? "es" : "en"
    }

    var dictationLanguageBinding: Binding<String> {
        Binding(
            get: {
                _ = self.preferenceRevision
                let stored = self.defaults.string(forKey: DictationController.languageKey) ?? "auto"
                if self.speechEngine == .appleSpeech {
                    return LiveSpeechSelection.dictationLanguages.contains(stored)
                        ? stored : Self.preferredConcreteLanguage()
                }
                if stored == "auto" || LiveSpeechSelection.dictationLanguages.contains(stored) {
                    return stored
                }
                return "auto"
            },
            set: { self.store([DictationController.languageKey: $0, Self.languageBeforeAppleSpeechKey: ""]) })
    }

    /// The choice Apple Speech replaced, restored on the way back unless the person picked another.
    static let languageBeforeAppleSpeechKey = "dictationLanguageBeforeAppleSpeech"

    func coerceAppleSpeechLanguageIfNeeded() {
        let stored = defaults.string(forKey: DictationController.languageKey) ?? "auto"
        guard speechEngine == .appleSpeech else {
            let previous = defaults.string(forKey: Self.languageBeforeAppleSpeechKey) ?? ""
            if !previous.isEmpty {
                store([DictationController.languageKey: previous, Self.languageBeforeAppleSpeechKey: ""])
            }
            return
        }
        if !LiveSpeechSelection.dictationLanguages.contains(stored) {
            store([DictationController.languageKey: Self.preferredConcreteLanguage(),
                   Self.languageBeforeAppleSpeechKey: stored])
        }
    }

    /// The warm model may be the other checkpoint, so the next dictation loads afresh.
    /// A failure belonged to the other engine's parts, and Parakeet may not have been hashed.
    func speechEngineChanged() {
        warmEngine.release()
        adoptedParts.removeAll()
        coerceAppleSpeechLanguageIfNeeded()
        if modelState == .failed { modelState = .missing }
        applyModelReadiness()
        if speechModelIsRequired { Task { await refreshReadiness() } }
        prewarmIfConfigured()
    }

    /// Settings asks only while Ultra is chosen, so nobody else hashes 632 MB they never use.
    func refreshUltra() async {
        guard speechEngine == .parakeetUltra, let models = environment.models else { return }
        await ultra.refresh(models, adopts: isEnabled)
    }

    func downloadUltra() {
        guard let models = environment.models else { return }
        ultra.download(models) { [weak self] in self?.speechEngineChanged() }
    }

    /// Ultra loads only once chosen and installed; until then dictation keeps v3.
    nonisolated static func loadSpeechModel(
        store: LocalModelStore, defaults: UserDefaults
    ) async throws -> ParakeetEngine {
        try await loadSpeechModel(defaults: defaults) { try await ParakeetEngine.load(from: store, checkpoint: $0) }
    }

    nonisolated static func loadSpeechModel<Engine>(
        defaults: UserDefaults, load: (ParakeetCheckpoint) async throws -> Engine
    ) async throws -> Engine {
        // The lease verifies under its lock, so a separate check first would only race it.
        if LiveSpeechSelection.dictation(defaults: defaults) == .parakeetUltra {
            do {
                return try await load(.ultra)
            } catch LocalModelStore.LocalModelStoreError.notInstalled {}
        }
        do {
            return try await load(.v3)
        } catch LocalModelStore.LocalModelStoreError.notInstalled {
            throw DictationFeatureError.modelMissing
        }
    }
}
