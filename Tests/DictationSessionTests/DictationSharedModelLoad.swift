import Foundation
import Synchronization

/// One model load shared by every request of a lane. A request that gives up stops waiting at
/// once, while the load runs on for the next request, so two loads never overlap. `waitSeconds`
/// counts only time spent inside requests, which is what the controller receipt bounds.
@MainActor
final class DictationSharedModelLoad<Value: Sendable> {
    private let load: @Sendable () async throws -> Value
    private var loading: Task<Value, any Error>?
    private(set) var value: Value?
    private(set) var waitSeconds = 0.0
    private(set) var loadsStarted = 0

    init(load: @escaping @Sendable () async throws -> Value) { self.load = load }

    func acquire() async throws -> Value {
        if let value { return value }
        let start = ContinuousClock.now
        defer { waitSeconds += DictationModelProbe.seconds(start.duration(to: .now)) }
        let task = loading ?? started()
        do {
            let value = try await Self.wait(for: task)
            self.value = value
            if loading == task { loading = nil }
            return value
        } catch {
            // A failed load must not be joined again; a cancelled wait leaves it running.
            if !(error is CancellationError), loading == task { loading = nil }
            throw error
        }
    }

    private func started() -> Task<Value, any Error> {
        loadsStarted += 1
        let task = Task { [load] in try await load() }
        loading = task
        return task
    }

    /// Cancelling the waiter resumes it with `CancellationError`; the task itself keeps running.
    private static func wait(for task: Task<Value, any Error>) async throws -> Value {
        let handoff = Handoff()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiter in
                handoff.attach(waiter)
                Task { handoff.offer(await task.result) }
            }
        } onCancel: {
            handoff.offer(.failure(CancellationError()))
        }
    }

    /// The first result wins, and reaches the waiter whichever of the two arrives first.
    private final class Handoff: Sendable {
        private struct State {
            var waiter: CheckedContinuation<Value, any Error>?
            var result: Result<Value, any Error>?
            var delivered = false
        }

        private let state = Mutex(State())

        func attach(_ waiter: CheckedContinuation<Value, any Error>) {
            let ready: Result<Value, any Error>? = state.withLock { state in
                state.waiter = waiter
                guard let result = state.result, !state.delivered else { return nil }
                state.delivered = true
                return result
            }
            if let ready { waiter.resume(with: ready) }
        }

        func offer(_ result: Result<Value, any Error>) {
            let waiter: CheckedContinuation<Value, any Error>? = state.withLock { state in
                guard state.result == nil else { return nil }
                state.result = result
                guard let waiter = state.waiter else { return nil }
                state.delivered = true
                return waiter
            }
            waiter?.resume(with: result)
        }
    }
}
