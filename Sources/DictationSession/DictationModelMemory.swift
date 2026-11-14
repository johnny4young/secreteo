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
    private(set) var isActive = false
    private var releasers: [@MainActor () -> Bool] = []
    private var afterEnd: [@MainActor () -> Void] = []
    private var tookSomething = false

    /// Pressure gives an idle model back at once; a session in use keeps the one it holds.
    func releases<Model>(_ warm: WarmModel<Model>) {
        releases { [weak warm] in warm?.release() ?? false }
    }

    /// Runs on each report of pressure; returns whether it gave anything back.
    func releases(_ release: @escaping @MainActor () -> Bool) {
        releasers.append(release)
    }

    /// Runs when pressure that gave something back ends, not on every report of normal memory.
    func whenItEnds(_ action: @escaping @MainActor () -> Void) {
        afterEnd.append(action)
    }

    func changed(isActive: Bool) {
        let ended = self.isActive && !isActive
        self.isActive = isActive
        if isActive {
            for release in releasers where release() { tookSomething = true }
        }
        guard ended, tookSomething else { return }
        tookSomething = false
        afterEnd.forEach { $0() }
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
