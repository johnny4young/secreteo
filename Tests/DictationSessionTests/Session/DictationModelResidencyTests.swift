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
        rig.warm.release()
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
            rig.pressure.changed(isActive: true)
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

        rig.pressure.changed(isActive: true)

        XCTAssertFalse(rig.warm.isHoldingModel, "Pressure does not wait for the window")
        await assertGivenBack(rig)
        let cancelled = await rig.clock.waitUntilCancellationCount(1)
        XCTAssertTrue(cancelled)
    }

    func testAModelInUseHasNoIdleClock() async throws {
        let rig = makeRig()
        rig.defaults.set(DictationModelMemory.lightweight.rawValue, forKey: DictationModelMemory.key)
        rig.pressure.changed(isActive: true)
        _ = try await rig.warm.acquire()
        _ = try await rig.warm.acquire()

        rig.warm.idleLimitChanged()
        rig.warm.releaseWhenIdle()
        XCTAssertEqual(rig.idleClockStarts.count, 0, "Another user still has the model")
        XCTAssertTrue(rig.warm.isHoldingModel)

        rig.warm.releaseWhenIdle()
        XCTAssertEqual(rig.idleClockStarts.count, 1, "The clock starts only when the last user gives it back")
        let started = await rig.clock.waitUntilCallCount(1)
        XCTAssertTrue(started)
        let window = await rig.clock.requestedDuration(at: 0)
        XCTAssertEqual(window, .zero)
        let ended = await rig.clock.resumeCall(at: 0)
        XCTAssertTrue(ended)
        await assertGivenBack(rig)
    }

    func testMemoryPressureNeverTakesTheModelFromASessionInUse() async throws {
        let rig = makeRig()
        var session: SyntheticModel? = try await rig.warm.acquire()
        let identity = session.map(ObjectIdentifier.init)

        rig.pressure.changed(isActive: true)

        XCTAssertFalse(rig.warm.isHoldingModel)
        XCTAssertEqual(rig.census.resident, 1, "The session keeps working with the model it was given")
        XCTAssertEqual(session.map(ObjectIdentifier.init), identity)
        XCTAssertNil(rig.warm.prewarm(), "A prewarm must not load a second copy beside the session's")

        session = nil
        let freed = await TestPolling.until { rig.census.resident == 0 }
        XCTAssertTrue(freed, "Its memory goes as soon as the session gives it back")
        rig.warm.releaseWhenIdle()
        XCTAssertEqual(rig.idleClockStarts.count, 0, "Nothing is left to wait for")
    }

    func testAPrewarmLoadsAgainAfterPressureAndStillWaitsOutItsWindow() async throws {
        let rig = makeRig()
        _ = try await rig.warm.acquire()
        rig.warm.releaseWhenIdle()
        let started = await rig.clock.waitUntilCallCount(1)
        XCTAssertTrue(started)
        rig.pressure.changed(isActive: true)
        await assertGivenBack(rig)
        rig.pressure.changed(isActive: false)

        let prewarm = try XCTUnwrap(rig.warm.prewarm())
        await prewarm.value

        XCTAssertEqual(rig.census.loads, 2)
        XCTAssertTrue(rig.warm.isHoldingModel)
        let waiting = await rig.clock.waitUntilCallCount(2)
        XCTAssertTrue(waiting, "A prewarmed model still gets its idle clock")
        let window = await rig.clock.requestedDuration(at: 1)
        XCTAssertEqual(window, .seconds(600))
        XCTAssertTrue(rig.warm.release(), "pressure would have something to give back")
        XCTAssertFalse(rig.warm.release(), "and nothing the second time")
    }

    func testCompilingAheadLoadsOnceAndGivesTheModelBackAtOnce() async throws {
        let rig = makeRig()
        let compile = try XCTUnwrap(rig.warm.compileAhead())
        let compiled = await compile.value

        XCTAssertTrue(compiled)
        XCTAssertEqual(rig.census.loads, 1)
        await assertGivenBack(rig)
        XCTAssertEqual(rig.idleClockStarts.count, 0, "Nothing waits out an idle window")
    }

    func testADictationDuringTheCompileKeepsTheModelItLoaded() async throws {
        let rig = makeRig()
        let compile = try XCTUnwrap(rig.warm.compileAhead())
        _ = try await rig.warm.acquire()
        _ = await compile.value

        XCTAssertEqual(rig.census.loads, 1, "The dictation joins the compile's load")
        XCTAssertTrue(rig.warm.isHoldingModel)
        rig.warm.releaseWhenIdle()
        let waiting = await rig.clock.waitUntilCallCount(1)
        XCTAssertTrue(waiting, "The dictation's model still gets its idle clock")
        rig.warm.release()
    }

    func testAFailedCompileSaysSoAndHoldsNothing() async throws {
        let rig = makeRig(loadFails: true)
        let compile = try XCTUnwrap(rig.warm.compileAhead())
        let compiled = await compile.value

        XCTAssertFalse(compiled, "A failed load must not count as compiled")
        XCTAssertFalse(rig.warm.isHoldingModel)
        XCTAssertNotNil(rig.warm.compileAhead(), "The next trigger may try again")
    }

    func testCompilingAheadLoadsNothingOnceTheAppMayNotHoldTheModel() async throws {
        let rig = makeRig(mayKeep: { false })
        let compile = try XCTUnwrap(rig.warm.compileAhead())
        let compiled = await compile.value

        XCTAssertFalse(compiled)
        XCTAssertEqual(rig.census.loads, 0)
    }

    func testCompilingAheadSkipsAModelAlreadyLoadedOrInUse() async throws {
        let rig = makeRig()
        _ = try await rig.warm.acquire()
        XCTAssertNil(rig.warm.compileAhead())
        rig.warm.releaseWhenIdle()
        XCTAssertNil(rig.warm.compileAhead(), "A held model is already compiled")
        XCTAssertEqual(rig.census.loads, 1)
        rig.warm.release()
    }

    func testANewUseAfterAReleaseLoadsAgain() async throws {
        for releasesUnderPressure in [false, true] {
            let rig = makeRig()
            _ = try await rig.warm.acquire()
            rig.warm.releaseWhenIdle()
            let started = await rig.clock.waitUntilCallCount(1)
            XCTAssertTrue(started)
            if releasesUnderPressure {
                rig.pressure.changed(isActive: true)
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

    private func makeRig(mayKeep: @escaping @MainActor () -> Bool = { true }, loadFails: Bool = false) -> Rig {
        let name = "DictationModelResidencyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(DictationModelMemory.balanced.rawValue, forKey: DictationModelMemory.key)
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
            mayKeep: mayKeep,
            load: {
                if loadFails { throw CocoaError(.fileNoSuchFile) }
                return SyntheticModel(census: census)
            },
            sleep: { try await clock.wait(for: $0) })
        pressure.releases(warm)
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
