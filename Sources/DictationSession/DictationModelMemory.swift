import Foundation

/// These choices never select, download or replace a model, or take one from a running session.
enum DictationModelMemory: String {
    case balanced
    case lightweight

    static let key = "modelMemoryProfile"

    /// Lightweight keeps a short grace so dictations in a row reuse a loaded model.
    /// A Mac short of memory gets no grace at all.
    func idleLimit(underPressure: Bool) -> Duration {
        if underPressure { return .zero }
        switch self {
        case .balanced: return .seconds(600)
        case .lightweight: return .seconds(60)
        }
    }

    static func current(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .balanced
    }

    /// Read each time the warm model goes idle, so a changed profile or pressure applies to the next wait.
    @MainActor
    static func idleLimit(in defaults: UserDefaults, pressure: DictationMemoryPressure) -> Duration {
        current(in: defaults).idleLimit(underPressure: pressure.isActive)
    }
}

/// The system's last word on memory, which `WarmModel` reads before the feature exists.
@MainActor
final class DictationMemoryPressure {
    var isActive = false
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
