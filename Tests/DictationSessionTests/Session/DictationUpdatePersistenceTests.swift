import DictationKit
import DictationOwnership
import DictationStore
import Foundation
import SpeechCore
import XCTest
@testable import DictationSession

@MainActor
final class DictationUpdatePersistenceTests: XCTestCase {
    func testUpdateWaitsForAQueuedHistoryWriteWithoutAnActiveLease() async throws {
        try await checkHistoryWrite(succeeds: true)
    }

    func testAFailedHistoryWriteAlsoSettlesTheRelaunchWait() async throws {
        try await checkHistoryWrite(succeeds: false)
    }

    private func checkHistoryWrite(succeeds: Bool) async throws {
        let writes = DictationPendingWrites()
        let coordinator = makeCoordinator(writes)
        let gate = PreparationGate()
        let history = DictationHistorySession(sessionID: UUID(), write: { _ in
            await gate.wait()
            return succeeds
        }, pendingWrites: writes)
        defer { gate.release(); coordinator.finishUpdateCycle() }
        history.prepare(record())
        history.record(.verified)
        XCTAssertTrue(writes.hasPending, "Register before the writer task gets a turn")
        var resumed = 0

        XCTAssertTrue(coordinator.postponeUpdateRelaunch { resumed += 1 })
        let waiting = await TestPolling.until { gate.started }
        XCTAssertTrue(waiting)
        XCTAssertEqual(history.state, .saving)
        XCTAssertEqual(resumed, 0)
        gate.release()

        let settled = await TestPolling.until { !writes.hasPending }
        XCTAssertTrue(settled)
        XCTAssertEqual(history.state, succeeds ? .saved : .failed)
        XCTAssertEqual(resumed, 1)
    }

    func testUpdateWaitsForStatisticsToReachTheRealStore() async throws {
        let writes = DictationPendingWrites()
        let coordinator = makeCoordinator(writes)
        let store = try DictationStore.inMemory()
        let gate = PreparationGate()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stats = DictationStatsModel(
            store: HeldStatsStore(store: store, gate: gate), now: { now }, pendingWrites: writes)
        defer { gate.release(); coordinator.finishUpdateCycle() }
        await stats.update(isEnabled: true)
        let day = DictationStatsCalendar.day(of: now, calendar: .current)
        stats.record(.init(
            id: DictationRecordID(), day: day, words: 5, spokenDuration: 2,
            applicationName: "Synthetic receiver", delivered: true))
        XCTAssertTrue(writes.hasPending)
        var resumed = 0

        XCTAssertTrue(coordinator.postponeUpdateRelaunch { resumed += 1 })
        let waiting = await TestPolling.until { gate.started }
        XCTAssertTrue(waiting)
        XCTAssertEqual(resumed, 0)
        let before = try await store.dictationStatsSummary(days: [day])
        XCTAssertEqual(before.totals.words, 0)
        gate.release()

        let settled = await TestPolling.until { !writes.hasPending }
        XCTAssertTrue(settled)
        let after = try await store.dictationStatsSummary(days: [day])
        XCTAssertEqual(after.totals.words, 5)
        XCTAssertEqual(resumed, 1)
    }

    func testAbortingTheCycleDropsTheCallbackWhileHistoryStillSaves() async throws {
        let writes = DictationPendingWrites()
        let coordinator = makeCoordinator(writes)
        let gate = PreparationGate()
        let history = DictationHistorySession(sessionID: UUID(), write: { _ in
            await gate.wait()
            return true
        }, pendingWrites: writes)
        defer { gate.release() }
        history.prepare(record())
        history.record(.verified)
        var resumed = 0
        XCTAssertTrue(coordinator.postponeUpdateRelaunch { resumed += 1 })
        let waiting = await TestPolling.until { gate.started }
        XCTAssertTrue(waiting)

        coordinator.finishUpdateCycle()
        gate.release()

        let settled = await TestPolling.until { !writes.hasPending }
        XCTAssertTrue(settled)
        XCTAssertEqual(history.state, .saved)
        XCTAssertEqual(resumed, 0)
        XCTAssertNil(coordinator.admission.refusalNow())
    }

    func testEachPendingWriteFinishesOnceAndTheLastOneResumes() {
        let writes = DictationPendingWrites()
        let coordinator = makeCoordinator(writes)
        let first = writes.begin()
        let second = writes.begin()
        var resumed = 0
        XCTAssertTrue(coordinator.postponeUpdateRelaunch { resumed += 1 })

        first()
        first()

        XCTAssertTrue(writes.hasPending)
        XCTAssertEqual(resumed, 0)
        second()
        second()
        XCTAssertFalse(writes.hasPending)
        XCTAssertEqual(resumed, 1)
        coordinator.finishUpdateCycle()
    }

    func testSkippedHistoryNeverStartsAPersistenceWait() {
        let writes = DictationPendingWrites()
        let history = DictationHistorySession(sessionID: UUID(), write: { _ in
            XCTFail("A secure field must not write")
            return false
        }, pendingWrites: writes)
        history.prepare(record())

        history.record(.refused(.secureField))

        XCTAssertEqual(history.state, .skipped)
        XCTAssertFalse(writes.hasPending)
    }

    func testFinishingHistoryFirstStillWaitsForTheLease() async throws {
        try await checkLeaseAndHistory(writeFinishesFirst: true)
    }

    func testReleasingTheLeaseFirstStillWaitsForHistory() async throws {
        try await checkLeaseAndHistory(writeFinishesFirst: false)
    }

    private func checkLeaseAndHistory(writeFinishesFirst: Bool) async throws {
        let writes = DictationPendingWrites()
        let coordinator = makeCoordinator(writes)
        let lease = try coordinator.admission.acquire(.global).get()
        let gate = PreparationGate()
        let history = DictationHistorySession(sessionID: UUID(), write: { _ in
            await gate.wait()
            return true
        }, pendingWrites: writes)
        defer { gate.release(); lease.release(); coordinator.finishUpdateCycle() }
        history.prepare(record())
        history.record(.verified)
        var resumed = 0
        XCTAssertTrue(coordinator.postponeUpdateRelaunch { resumed += 1 })

        let waiting = await TestPolling.until { gate.started }
        XCTAssertTrue(waiting)
        if writeFinishesFirst {
            gate.release()
            let saved = await TestPolling.until { history.state == .saved }
            XCTAssertTrue(saved)
            XCTAssertEqual(resumed, 0)
            lease.release()
        } else {
            lease.release()
            XCTAssertEqual(resumed, 0)
            gate.release()
        }

        let finished = await TestPolling.until { resumed == 1 }
        XCTAssertTrue(finished)
        XCTAssertEqual(history.state, .saved)
        XCTAssertFalse(coordinator.holdsLease)
        XCTAssertFalse(writes.hasPending)
    }

    private func makeCoordinator(_ writes: DictationPendingWrites) -> DictationOwnershipCoordinator {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("update-writes-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let ownership = DictationOwnership(
            participant: "com.example.update-tests", root: root,
            conditions: {
                ParticipantConditions(preferenceIsOn: true, missingForReadiness: nil, legacyPeerIsActive: false)
            }, notificationName: "update-writes-\(UUID().uuidString)")
        _ = ownership.claimAtFirstRun()
        return DictationOwnershipCoordinator(ownership: ownership, pendingWrites: writes, settle: {})
    }

    private func record() -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: Date(), duration: 1, text: "Synthetic words",
            originalText: nil, mode: .literal, language: nil, engine: "fixture",
            applicationName: "Synthetic receiver", applicationBundleID: nil, delivery: .verified)
    }

    private struct HeldStatsStore: DictationStatsStore {
        let store: DictationStore
        let gate: PreparationGate
        func dictationStatsEnabled() async throws -> Bool { try await store.dictationStatsEnabled() }
        func setDictationStatsEnabled(_ isEnabled: Bool) async throws {
            try await store.setDictationStatsEnabled(isEnabled)
        }
        func recordDictationStats(_ sample: DictationStatsSample, at now: Date, calendar: Calendar) async throws -> Bool {
            await gate.wait()
            return try await store.recordDictationStats(sample, at: now, calendar: calendar)
        }
        func dictationStatsSummary(days: [String]) async throws -> DictationStatsSummary {
            try await store.dictationStatsSummary(days: days)
        }
        func deleteDictationStats() async throws { try await store.deleteDictationStats() }
    }
}
