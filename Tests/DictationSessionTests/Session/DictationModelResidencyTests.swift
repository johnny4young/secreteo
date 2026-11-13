import Foundation
import Synchronization
import XCTest

@testable import DictationSession

/// Secreteo's residency contract for the warm speech model, with a synthetic loader and a held clock.
@MainActor
final class DictationModelResidencyTests: XCTestCase {
    func testABalancedModelIsGivenBackAfterTenIdleMinutes() async throws {
        let rig = makeRig()
        _ = try await rig.warm.acquire()
        rig.warm.releaseWhenIdle()

        let started = await rig.clock.waitUntilCallCount(1)
        XCTAssertTrue(started)
        let window = await rig.clock.requestedDuration(at: 0)
        XCTAssertEqual(window, .seconds(600))
        XCTAssertTrue(rig.warm.isHoldingModel, "Nothing is given back before the window ends")

        let ended = await rig.clock.resumeCall(at: 0)
        XCTAssertTrue(ended)
        await assertGivenBack(rig)
    }

    func testAUseWithinTheIdleWindowStartsItAgain() async throws {
        let rig = makeRig()
        _ = try await rig.warm.acquire()
        rig.warm.releaseWhenIdle()
        let firstWait = await rig.clock.waitUntilCallCount(1)
        XCTAssertTrue(firstWait)

        _ = try await rig.warm.acquire()
        let cancelled = await rig.clock.waitUntilCancellationCount(1)
        XCTAssertTrue(cancelled, "A new use stops the running window")
        rig.warm.releaseWhenIdle()
        let secondWait = await rig.clock.waitUntilCallCount(2)
        XCTAssertTrue(secondWait)
        let window = await rig.clock.requestedDuration(at: 1)

        XCTAssertEqual(window, .seconds(600), "The window is counted from the last use")
        XCTAssertTrue(rig.warm.isHoldingModel)
        XCTAssertEqual(rig.census.loads, 1)
    }

    func testTheLightweightProfileGivesTheModelBackAfterOneIdleMinute() async throws {
        let rig = makeRig()
        rig.defaults.set(DictationModelMemory.lightweight.rawValue, forKey: DictationModelMemory.key)
        _ = try await rig.warm.acquire()
        rig.warm.releaseWhenIdle()

        let started = await rig.clock.waitUntilCallCount(1)
        XCTAssertTrue(started)
        let window = await rig.clock.requestedDuration(at: 0)
        XCTAssertEqual(window, .seconds(60))
        XCTAssertTrue(rig.warm.isHoldingModel)

        let ended = await rig.clock.resumeCall(at: 0)
        XCTAssertTrue(ended)
        await assertGivenBack(rig)
    }

    func testUnderMemoryPressureAnIdleModelGetsNoGrace() async throws {
        for profile in [DictationModelMemory.balanced, .lightweight] {
            let rig = makeRig()
            rig.defaults.set(profile.rawValue, forKey: DictationModelMemory.key)
            rig.pressure.isActive = true
            _ = try await rig.warm.acquire()
            rig.warm.releaseWhenIdle()

            let started = await rig.clock.waitUntilCallCount(1)
            XCTAssertTrue(started)
            let window = await rig.clock.requestedDuration(at: 0)
            XCTAssertEqual(window, .zero, "\(profile)")

            let ended = await rig.clock.resumeCall(at: 0)
            XCTAssertTrue(ended)
            await assertGivenBack(rig)
        }
    }

    func testMemoryPressureGivesBackAModelWaitingOutItsWindow() async throws {
        let rig = makeRig()
        _ = try await rig.warm.acquire()
        rig.warm.releaseWhenIdle()
        let started = await rig.clock.waitUntilCallCount(1)
        XCTAssertTrue(started)

        // What `DictationFeature.memoryPressureChanged(isUnderPressure: true)` does.
        rig.pressure.isActive = true
        rig.warm.release()

        XCTAssertFalse(rig.warm.isHoldingModel, "Pressure does not wait for the window")
        await assertGivenBack(rig)
        let cancelled = await rig.clock.waitUntilCancellationCount(1)
        XCTAssertTrue(cancelled)
    }

    func testAModelInUseHasNoIdleClock() async throws {
        let rig = makeRig()
        rig.defaults.set(DictationModelMemory.lightweight.rawValue, forKey: DictationModelMemory.key)
        rig.pressure.isActive = true
        _ = try await rig.warm.acquire()
        _ = try await rig.warm.acquire()

        rig.warm.idleLimitChanged()
        rig.warm.releaseWhenIdle()
        XCTAssertEqual(rig.idleClockStarts.count, 0, "Another user still has the model")
        XCTAssertTrue(rig.warm.isHoldingModel)

        rig.warm.releaseWhenIdle()
        XCTAssertEqual(rig.idleClockStarts.count, 1, "The clock starts only when the last user gives it back")
    }

    func testMemoryPressureNeverTakesTheModelFromASessionInUse() async throws {
        let rig = makeRig()
        var session: SyntheticModel? = try await rig.warm.acquire()
        let identity = session.map(ObjectIdentifier.init)

        rig.pressure.isActive = true
        rig.warm.release()

        XCTAssertFalse(rig.warm.isHoldingModel)
        XCTAssertEqual(rig.census.resident, 1, "The session keeps working with the model it was given")
        XCTAssertEqual(session.map(ObjectIdentifier.init), identity)

        session = nil
        rig.warm.releaseWhenIdle()
        XCTAssertEqual(rig.census.resident, 0, "Its memory goes as soon as the session gives it back")
        XCTAssertEqual(rig.idleClockStarts.count, 0, "Nothing is left to wait for")
    }

    func testANewUseAfterAReleaseLoadsAgain() async throws {
        for releasesUnderPressure in [false, true] {
            let rig = makeRig()
            _ = try await rig.warm.acquire()
            rig.warm.releaseWhenIdle()
            let started = await rig.clock.waitUntilCallCount(1)
            XCTAssertTrue(started)
            if releasesUnderPressure {
                rig.pressure.isActive = true
                rig.warm.release()
            } else {
                let ended = await rig.clock.resumeCall(at: 0)
                XCTAssertTrue(ended)
            }
            await assertGivenBack(rig)

            _ = try await rig.warm.acquire()

            XCTAssertEqual(rig.census.loads, 2, "pressure: \(releasesUnderPressure)")
            XCTAssertEqual(rig.census.resident, 1)
            XCTAssertTrue(rig.warm.isHoldingModel)
            rig.warm.release()
        }
    }

    // MARK: Rig

    private struct Rig {
        let warm: WarmModel<SyntheticModel>
        let defaults: UserDefaults
        let pressure: DictationMemoryPressure
        let clock: ControlledTestSleep
        let census: ModelCensus
        let idleClockStarts: IdleClockStarts
    }

    @MainActor
    private final class IdleClockStarts {
        var count = 0
    }

    private func makeRig() -> Rig {
        let name = "DictationModelResidencyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let pressure = DictationMemoryPressure()
        let clock = ControlledTestSleep()
        let census = ModelCensus()
        let starts = IdleClockStarts()
        let warm = WarmModel<SyntheticModel>(
            idleLimit: {
                starts.count += 1
                return DictationModelMemory.idleLimit(in: defaults, pressure: pressure)
            },
            mayKeep: { true },
            load: { SyntheticModel(census: census) },
            sleep: { try await clock.wait(for: $0) })
        return Rig(
            warm: warm, defaults: defaults, pressure: pressure, clock: clock, census: census,
            idleClockStarts: starts)
    }

    private func assertGivenBack(_ rig: Rig, file: StaticString = #filePath, line: UInt = #line) async {
        let freed = await TestPolling.until { rig.census.resident == 0 }
        XCTAssertTrue(freed, "The model's memory is freed", file: file, line: line)
        XCTAssertFalse(rig.warm.isHoldingModel, file: file, line: line)
    }
}

/// Counts loads and frees, so a test sees whether a model is still in memory, not only referenced.
private final class ModelCensus: Sendable {
    private let counts = Mutex((loads: 0, frees: 0))

    var loads: Int { counts.withLock { $0.loads } }
    var resident: Int { counts.withLock { $0.loads - $0.frees } }

    func loaded() { counts.withLock { $0.loads += 1 } }
    func freed() { counts.withLock { $0.frees += 1 } }
}

private final class SyntheticModel: Sendable {
    private let census: ModelCensus

    init(census: ModelCensus) {
        self.census = census
        census.loaded()
    }

    deinit { census.freed() }
}
