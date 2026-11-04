import Foundation

/// Keeps one loaded model ready for the next dictation, only while this app may hold it.
@MainActor
final class WarmModel<Model: Sendable> {
    private let idleLimit: Duration
    private let mayKeep: @MainActor () -> Bool
    private let load: @Sendable () async throws -> Model
    private var model: Model?
    private var loading: Task<Model, Error>?
    private var idleRelease: Task<Void, Never>?

    var isHoldingModel: Bool { model != nil }

    init(
        idleLimit: Duration = .seconds(600), mayKeep: @escaping @MainActor () -> Bool,
        load: @escaping @Sendable () async throws -> Model
    ) {
        self.idleLimit = idleLimit
        self.mayKeep = mayKeep
        self.load = load
    }

    func acquire() async throws -> Model {
        idleRelease?.cancel()
        if let model { return model }
        if let loading { return try await loading.value }
        let task = Task { [load] in try await load() }
        loading = task
        defer { loading = nil }
        let loaded = try await task.value
        // The right to hold it can end during a load, and nothing later would release it.
        if mayKeep() { model = loaded }
        return loaded
    }

    func releaseWhenIdle() {
        idleRelease?.cancel()
        idleRelease = Task { [weak self, idleLimit] in
            try? await Task.sleep(for: idleLimit)
            guard !Task.isCancelled else { return }
            self?.model = nil
        }
    }

    func release() {
        idleRelease?.cancel()
        model = nil
    }
}
