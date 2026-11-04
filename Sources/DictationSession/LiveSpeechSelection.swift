import Foundation
import DictationKit
import LiveSpeech

/// Dictation defaults to Ultra, which falls back to v3 until the person downloads it.
enum LiveSpeechSelection: String, CaseIterable {
    case parakeet
    case parakeetUltra
    case appleSpeech

    static let dictationKey = "dictationLiveSpeechEngine"
    static let dictationDefault = Self.parakeetUltra

    static func dictation(defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: dictationKey) ?? "") ?? dictationDefault
    }

    init(checkpoint: ParakeetCheckpoint) {
        self = checkpoint == .ultra ? .parakeetUltra : .parakeet
    }
}

@MainActor
enum LiveSpeechPurpose {
    case dictation

    func selectedEngine(in defaults: UserDefaults) -> LiveSpeechSelection {
        LiveSpeechSelection.dictation(defaults: defaults)
    }

    func language(in defaults: UserDefaults) -> String? {
        let value = defaults.string(forKey: DictationController.languageKey)
        return ["en", "es"].contains(value) ? value : nil
    }
}

enum LiveSpeechFailureMessage {
    static func dictation(_ error: Error) -> String {
        guard let readiness = error as? SpeechAnalyzerLiveReadiness else {
            return L10n.format("Dictation failed: %@", error.localizedDescription)
        }
        switch readiness {
        case .languageRequired:
            return L10n.text("Choose English or Spanish for Apple Speech in Dictation settings.")
        case .unavailable:
            return L10n.text("Apple Speech is unavailable. Choose Parakeet in Dictation settings.")
        case .unsupported:
            return L10n.text("Apple Speech does not support this language. Choose Parakeet in Dictation settings.")
        case .needsDownload:
            return L10n.text("Prepare the Apple Speech language asset in Dictation settings first.")
        case .ready:
            return L10n.text("Apple Speech could not start. Try Parakeet in Dictation settings.")
        }
    }
}
