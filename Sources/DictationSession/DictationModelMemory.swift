import Foundation

/// These choices never select, download or replace a model, or take one from a running session.
enum DictationModelMemory: String {
    case balanced
    case lightweight

    static let key = "modelMemoryProfile"
    /// Macs with 8 GiB or less default to Lightweight so speech weights unload quickly when idle.
    static let lightweightMemoryFloorBytes: UInt64 = 8 * 1_024 * 1_024 * 1_024

    /// Lightweight keeps a short grace so dictations in a row reuse a loaded model.
    /// A Mac short of memory gets no grace at all.
    func idleLimit(underPressure: Bool) -> Duration {
        if underPressure { return .zero }
        switch self {
        case .balanced: return .seconds(600)
        case .lightweight: return .seconds(60)
        }
    }

    static func defaultProfile(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Self {
        physicalMemory <= lightweightMemoryFloorBytes ? .lightweight : .balanced
    }

    static func current(
        in defaults: UserDefaults,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Self {
        if let saved = defaults.string(forKey: key).flatMap(Self.init(rawValue:)) {
            return saved
        }
        // Pre-1.4 Prewarm opt-ins wrote only dictationPrewarm without modelMemoryProfile; honor them on 8 GB Macs.
        if defaults.bool(forKey: DictationPrewarmPolicy.defaultsKey) {
            return .balanced
        }
        return defaultProfile(physicalMemory: physicalMemory)
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
    private var pressureActions: [@MainActor () -> Void] = []
    private var afterEnd: [@MainActor () -> Void] = []
    private var tookSomething = false

    /// Pressure gives an idle model back at once; a session in use keeps the one it holds.
    func releases<Model>(_ warm: WarmModel<Model>) {
        releases { [weak warm] in warm?.release() ?? false }
    }

    /// Pressure gives an idle model back, and its end restores nothing: the model reloads on next use.
    func evicts<Model>(_ warm: WarmModel<Model>) {
        onPressure { [weak warm] in warm?.release() }
    }

    /// Runs on each report of pressure; returns whether it gave anything back.
    func releases(_ release: @escaping @MainActor () -> Bool) {
        releasers.append(release)
    }

    /// Runs on pressure for caches that reload lazily and do not need prewarm restoration.
    func onPressure(_ action: @escaping @MainActor () -> Void) {
        pressureActions.append(action)
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
            pressureActions.forEach { $0() }
        }
        guard ended, tookSomething else { return }
        tookSomething = false
        afterEnd.forEach { $0() }
    }
}

/// When dictation loads its model ahead of use: an opt-in warm load, or a load at launch
/// that lets go at once. Neither pins the model, so idle and pressure release still apply.
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
        conditions.prewarmEnabled && conditions.profile == .balanced && shouldCompile(conditions)
    }

    /// Core ML keeps its compiled model per macOS build, so the first load after a macOS
    /// update takes seconds. Loading once at launch moves that wait off the first dictation.
    static func shouldCompile(_ conditions: Conditions) -> Bool {
        conditions.dictationEnabled && [.parakeet, .parakeetUltra].contains(conditions.engine)
            && !conditions.underPressure && !conditions.lowPowerMode
            && !conditions.temporaryStore
    }
}
