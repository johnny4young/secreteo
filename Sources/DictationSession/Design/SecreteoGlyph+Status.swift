extension DictationController {
    var statusFace: SecreteoGlyphFace { Self.statusFace(for: phase, isLoadingModel: isLoadingModel) }

    nonisolated static func statusFace(for phase: Phase, isLoadingModel: Bool) -> SecreteoGlyphFace {
        switch phase {
        case .idle: .ready
        case .preparing: .loading
        case .listening: isLoadingModel ? .loading : .listening
        case .delivering: .polishing
        case .verified: .inserted
        case .dispatched: .sent
        case .noSpeech: .noSpeech
        case .failed, .recovery: .notSent
        }
    }
}

extension SecreteoGlyphFace {
    /// Read by VoiceOver on the menu bar icon, after the app's name.
    public var accessibilityName: String {
        switch self {
        case .ready: L10n.text("Ready")
        case .listening: L10n.text("Listening…")
        case .loading: L10n.text("Loading the speech model")
        case .polishing: L10n.text("Polishing…")
        case .inserted: L10n.text("Inserted")
        case .sent: L10n.text("Sent, not verified")
        case .notSent: L10n.text("Text wasn’t sent")
        case .noSpeech: L10n.text("No speech detected")
        case .notOwner: L10n.text("Another app handles dictation")
        }
    }
}
