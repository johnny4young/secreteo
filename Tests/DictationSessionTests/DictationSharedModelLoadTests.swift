import Foundation
import Synchronization
import Testing

@testable import DictationSession

@MainActor
struct DictationSharedModelLoadTests {
    private struct LoadFailure: Error {}

    /// A load that finishes only when the test opens it.
    private final class Gate: Sendable {
        private let open = Mutex(false)
        let started = Mutex(0)

        func release() { open.withLock { $0 = true } }

        func load(_ value: String, failing: Bool = false) async throws -> String {
            started.withLock { $0 += 1 }
            while !open.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(2)) }
            if failing { throw LoadFailure() }
            return value
        }
    }

    @Test
    func requestsDuringALoadShareIt() async throws {
        let gate = Gate()
        let shared = DictationSharedModelLoad { try await gate.load("model") }
        let first = Task { try await shared.acquire() }
        let second = Task { try await shared.acquire() }
        _ = await TestPolling.until { gate.started.withLock { $0 } == 1 }
        gate.release()

        #expect(try await first.value == "model")
        #expect(try await second.value == "model")
        #expect(shared.loadsStarted == 1)
        #expect(gate.started.withLock { $0 } == 1)
    }

    @Test
    func aRequestThatGivesUpStopsWaitingWhileTheLoadRunsOn() async throws {
        let gate = Gate()
        let shared = DictationSharedModelLoad { try await gate.load("model") }
        let cancelled = Task { try await shared.acquire() }
        _ = await TestPolling.until { gate.started.withLock { $0 } == 1 }

        cancelled.cancel()

        await #expect(throws: CancellationError.self) { try await cancelled.value }
        gate.release()
        #expect(try await shared.acquire() == "model")
        #expect(shared.loadsStarted == 1, "the next request joins the load instead of starting another")
    }

    @Test
    func onlyTimeInsideRequestsCounts() async throws {
        let gate = Gate()
        let shared = DictationSharedModelLoad { try await gate.load("model") }
        let started = ContinuousClock.now
        let cancelled = Task { try await shared.acquire() }
        _ = await TestPolling.until { gate.started.withLock { $0 } == 1 }
        cancelled.cancel()
        _ = try? await cancelled.value
        try await Task.sleep(for: .milliseconds(300))
        gate.release()
        _ = try await shared.acquire()

        let wall = DictationModelProbe.seconds(started.duration(to: .now))
        #expect(shared.waitSeconds < wall - 0.25, "the load's tail between requests is not request time")
    }

    @Test
    func aFailedLoadIsNotKept() async throws {
        let gate = Gate()
        let fails = Mutex(true)
        let shared = DictationSharedModelLoad {
            try await gate.load("model", failing: fails.withLock { failing in defer { failing = false }; return failing })
        }
        gate.release()

        await #expect(throws: LoadFailure.self) { try await shared.acquire() }
        let value = try await shared.acquire()

        #expect(value == "model")
        #expect(shared.loadsStarted == 2)
    }
}
