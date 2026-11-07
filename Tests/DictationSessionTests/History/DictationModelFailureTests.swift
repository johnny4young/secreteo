import DictationKit
import DictationStore
import Foundation
import SpeechCore
import Synchronization
import XCTest

@testable import DictationSession

/// Settings and the history window show a model's failure, so a later success must clear it.
@MainActor
final class DictationModelFailureTests: XCTestCase {
    func testAStatisticsFailureClearsWhenTheNextChangeSucceeds() async throws {
        let store = try FlakyStore(DictationStore.inMemory())
        let model = DictationStatsModel(store: store)
        await model.load()

        store.failNext()
        await model.update(isEnabled: true)
        XCTAssertNotNil(model.failure)
        await model.update(isEnabled: true)
        XCTAssertNil(model.failure)

        store.failNext()
        await model.deleteAll()
        XCTAssertNotNil(model.failure)
        await model.deleteAll()
        XCTAssertNil(model.failure)
    }

    func testAHistoryFailureClearsWhenTheNextChangeSucceeds() async throws {
        let store = try FlakyStore(DictationStore.inMemory())
        let model = DictationHistoryModel(store: store)
        await model.load()

        store.failNext()
        await model.update(isEnabled: true)
        XCTAssertNotNil(model.failure)
        await model.update(isEnabled: true)
        XCTAssertNil(model.failure)

        store.failNext()
        await model.delete(DictationRecordID())
        XCTAssertNotNil(model.failure)
        await model.delete(DictationRecordID())
        XCTAssertNil(model.failure)

        store.failNext()
        await model.deleteAll()
        XCTAssertNotNil(model.failure)
        await model.deleteAll()
        XCTAssertNil(model.failure)
    }

    func testStatisticsOffNeverReachTheDatabase() async throws {
        let store = try FlakyStore(DictationStore.inMemory())
        let model = DictationStatsModel(store: store)
        await model.load()
        let before = store.calls

        model.record(DictationStatsSample(
            id: DictationRecordID(), day: DictationStatsCalendar.day(of: Date(), calendar: .current),
            words: 3, spokenDuration: 1, applicationName: "Notes", delivered: true))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.calls, before)
    }
}

/// Forwards to a real store, failing the next call when asked.
private final class FlakyStore: DictationHistoryStore, DictationStatsStore {
    struct Failure: Error {}
    private let base: DictationStore
    private let state = Mutex((failing: false, calls: 0))

    init(_ base: DictationStore) {
        self.base = base
    }

    var calls: Int { state.withLock { $0.calls } }

    func failNext() {
        state.withLock { $0.failing = true }
    }

    private func pass() throws {
        let fails = state.withLock { state -> Bool in
            state.calls += 1
            defer { state.failing = false }
            return state.failing
        }
        if fails { throw Failure() }
    }

    func dictationHistoryPolicy() async throws -> DictationHistoryPolicy {
        try pass()
        return try await base.dictationHistoryPolicy()
    }
    func setDictationHistoryPolicy(
        isEnabled: Bool, keepsOriginal: Bool, retentionDays: Int, exposesToAgents: Bool, at now: Date
    ) async throws -> DictationHistoryPolicy {
        try pass()
        return try await base.setDictationHistoryPolicy(
            isEnabled: isEnabled, keepsOriginal: keepsOriginal, retentionDays: retentionDays,
            exposesToAgents: exposesToAgents, at: now)
    }
    func recordDictation(
        _ record: DictationRecord, admittedGeneration: Int, at now: Date
    ) async throws -> DictationRecordOutcome {
        try pass()
        return try await base.recordDictation(record, admittedGeneration: admittedGeneration, at: now)
    }
    func dictationRecords(
        matching filter: DictationRecordFilter, before cursor: DictationRecord?, limit: Int
    ) async throws -> [DictationRecord] {
        try pass()
        return try await base.dictationRecords(matching: filter, before: cursor, limit: limit)
    }
    func dictationApplications() async throws -> [String] {
        try pass()
        return try await base.dictationApplications()
    }
    func deleteDictationRecord(_ id: DictationRecordID) async throws -> Bool {
        try pass()
        return try await base.deleteDictationRecord(id)
    }
    func deleteAllDictationRecords() async throws -> Int {
        try pass()
        return try await base.deleteAllDictationRecords()
    }
    func purgeExpiredDictationRecords(at now: Date) async throws -> Int {
        try pass()
        return try await base.purgeExpiredDictationRecords(at: now)
    }
    func dictationStatsEnabled() async throws -> Bool {
        try pass()
        return try await base.dictationStatsEnabled()
    }
    func setDictationStatsEnabled(_ isEnabled: Bool) async throws {
        try pass()
        try await base.setDictationStatsEnabled(isEnabled)
    }
    func recordDictationStats(_ sample: DictationStatsSample, at now: Date, calendar: Calendar) async throws -> Bool {
        try pass()
        return try await base.recordDictationStats(sample, at: now, calendar: calendar)
    }
    func dictationStatsSummary(days: [String]) async throws -> DictationStatsSummary {
        try pass()
        return try await base.dictationStatsSummary(days: days)
    }
    func deleteDictationStats() async throws {
        try pass()
        try await base.deleteDictationStats()
    }
}
