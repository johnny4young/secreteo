import Foundation

/// These choices never select, download or replace a model, or take one from a running session.
enum DictationModelMemory: String {
    case balanced
    case lightweight

    static let key = "modelMemoryProfile"

    /// Lightweight keeps a short grace so dictations in a row reuse a loaded model.
    var idleLimit: Duration {
        switch self {
        case .balanced: .seconds(600)
        case .lightweight: .seconds(60)
        }
    }

    static func current(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .balanced
    }
}

/// Opt-in warm load for dictation. It never pins the model: the hold ends at
/// once, so idle and pressure release still apply.
enum DictationPrewarmPolicy {
    static let defaultsKey = "dictationPrewarm"

    struct Conditions: Equatable {
        var dictationEnabled: Bool
        var prewarmEnabled: Bool
        var profile: DictationModelMemory
        var engine: LiveSpeechSelection
        var underPressure: Bool
        var lowPowerMode: Bool
        var temporaryStore: Bool
    }

    static func shouldWarm(_ conditions: Conditions) -> Bool {
        conditions.dictationEnabled && conditions.prewarmEnabled
            && conditions.profile == .balanced && [.parakeet, .parakeetUltra].contains(conditions.engine)
            && !conditions.underPressure && !conditions.lowPowerMode
            && !conditions.temporaryStore
    }
}
