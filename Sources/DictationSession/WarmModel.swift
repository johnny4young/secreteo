import Foundation

/// Keeps one loaded model ready for the next dictation, only while this app may hold it.
@MainActor
final class WarmModel<Model: Sendable> {
    private let idleLimit: @MainActor () -> Duration
    private let mayKeep: @MainActor () -> Bool
    private let load: @Sendable () async throws -> Model
    private var model: Model?
    private var loading: Task<Model, Error>?
    private var idleRelease: Task<Void, Never>?
    /// Each `acquire` not yet matched by `releaseWhenIdle`. A model in use has no idle clock.
    private var users = 0
    /// Bumped by `release`, so a load that started before it is not kept or shared after it.
    private var generation = 0

    var isHoldingModel: Bool { model != nil }

    init(
        idleLimit: @escaping @MainActor () -> Duration = { .seconds(600) }, mayKeep: @escaping @MainActor () -> Bool,
        load: @escaping @Sendable () async throws -> Model
    ) {
        self.idleLimit = idleLimit
        self.mayKeep = mayKeep
        self.load = load
    }

    func acquire() async throws -> Model {
        idleRelease?.cancel()
        idleRelease = nil
        users += 1
        do {
            return try await loadedModel()
        } catch {
            users -= 1
            scheduleIdleRelease()
            throw error
        }
    }

    private func loadedModel() async throws -> Model {
        if let model { return model }
        if let loading { return try await loading.value }
        let task = Task { [load] in try await load() }
        let started = generation
        loading = task
        defer { if generation == started { loading = nil } }
        let loaded = try await task.value
        // The right to hold it can end during a load, and nothing later would release it.
        if mayKeep(), generation == started { model = loaded }
        return loaded
    }

    func releaseWhenIdle() {
        users = max(0, users - 1)
        scheduleIdleRelease()
    }

    /// A changed limit applies to a model already waiting, not only to the next one.
    func idleLimitChanged() {
        if idleRelease != nil { scheduleIdleRelease() }
    }

    private func scheduleIdleRelease() {
        idleRelease?.cancel()
        idleRelease = nil
        guard users == 0, model != nil else { return }
        let limit = idleLimit()
        idleRelease = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            self?.model = nil
        }
    }

    func release() {
        idleRelease?.cancel()
        idleRelease = nil
        model = nil
        loading = nil
        generation += 1
    }
}
