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

    func testAHistoryLoadFailureRecoversWhenLoadIsRetried() async throws {
        let store = try FlakyStore(DictationStore.inMemory())
        let model = DictationHistoryModel(store: store)
        store.failNext()

        await model.load()

        XCTAssertFalse(model.isLoaded)
        XCTAssertEqual(
            model.failure,
            L10n.text("Dictation history could not be loaded."))

        await model.load()

        XCTAssertTrue(model.isLoaded)
        XCTAssertNil(model.failure)
    }

    func testARepeatedSearchRecoversAfterACurrentReadFailure() async throws {
        let store = try FlakyStore(DictationStore.inMemory())
        let model = DictationHistoryModel(store: store)
        let filter = DictationRecordFilter(query: "report")
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertNil(model.failure)
        store.failNext()

        await model.apply(filter)

        XCTAssertEqual(model.filter, filter)
        XCTAssertEqual(
            model.failure,
            L10n.text("Dictation history could not be loaded."))

        await model.apply(filter)

        XCTAssertEqual(model.filter, filter)
        XCTAssertNil(model.failure)
    }

    func testACurrentSearchFailureRemainsVisible() async throws {
        let store = try FlakyStore(DictationStore.inMemory())
        let model = DictationHistoryModel(store: store)
        await model.load()
        XCTAssertNil(model.failure)

        store.failNext()
        await model.apply(.init(query: "report"))

        XCTAssertEqual(
            model.failure,
            L10n.text("Dictation history could not be loaded."))
    }

    func testAnOlderSearchSuccessDoesNotClearTheCurrentSearchFailure() async throws {
        let gate = ControlledTestSleep()
        let store = try FlakyStore(
            DictationStore.inMemory(), heldRead: (query: "beta", gate: gate))
        let model = DictationHistoryModel(store: store)
        let current = DictationRecordFilter(query: "gamma")
        let expectedFailure = L10n.text("Dictation history could not be loaded.")
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertNil(model.failure)
        let older = Task { await model.apply(.init(query: "beta")) }
        addTeardownBlock {
            older.cancel()
            _ = await gate.resumeCall(at: 0)
            await older.value
        }
        let held = await gate.waitUntilCallCount(1)
        guard held else {
            XCTFail("the beta page did not suspend")
            return
        }

        store.failNext()
        await model.apply(current)
        XCTAssertEqual(model.failure, expectedFailure)
        XCTAssertEqual(model.filter, current)
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await older.value

        XCTAssertEqual(model.filter, current)
        XCTAssertEqual(model.failure, expectedFailure)
    }

    func testAnOlderSemanticSearchDoesNotClearTheCurrentSearchFailure() async throws {
        let base = try DictationStore.inMemory()
        let store = FlakyStore(base)
        let gate = ControlledTestSleep()
        let heldQuery = "summary held query"
        let embedding = HeldQueryEmbedding(query: heldQuery, gate: gate)
        let index = DictationSemanticIndex(store: base, embedding: embedding)
        let policy = try await base.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let report = DictationRecord(
            id: .init(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000071")!),
            createdAt: Date(timeIntervalSince1970: 4_070_908_800), duration: 1, text: "report", originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: "Notes",
            applicationBundleID: nil, delivery: .verified)
        let saved = try await base.recordDictation(
            report, admittedGeneration: policy.generation, at: Date())
        XCTAssertEqual(saved, .saved)
        await index.index(report)
        let vectors = try await base.dictationEmbeddings(profile: embedding.profile, matching: .all)
        XCTAssertEqual(vectors.map(\.recordID), [report.id])
        let model = DictationHistoryModel(store: store, semantic: index)
        let heldFilter = DictationRecordFilter(query: heldQuery)
        let current = DictationRecordFilter(query: "gamma")
        let expectedFailure = L10n.text("Dictation history could not be loaded.")
        await model.load()
        await index.backfill()
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.records.map(\.id), [report.id])
        XCTAssertNil(model.failure)
        let older = Task { await model.apply(heldFilter) }
        addTeardownBlock {
            older.cancel()
            _ = await gate.resumeCall(at: 0)
            await older.value
        }
        let held = await gate.waitUntilCallCount(1)
        guard held else {
            XCTFail("the semantic query embedding did not suspend")
            return
        }
        XCTAssertEqual(model.filter, heldFilter)
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertFalse(model.hasMore)

        store.failNext()
        await model.apply(current)
        XCTAssertEqual(model.filter, current)
        XCTAssertEqual(model.failure, expectedFailure)
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await older.value

        XCTAssertEqual(model.filter, current)
        XCTAssertEqual(model.failure, expectedFailure)
    }

    func testAnOlderSearchFailureDoesNotPublishAfterANewerSearchSucceeds() async throws {
        let base = try DictationStore.inMemory()
        let gate = ControlledTestSleep()
        let store = FlakyStore(
            base, heldRead: (query: "beta", gate: gate), failsHeldRead: true)
        let policy = try await base.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let beta = DictationRecord(
            id: .init(rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000081"))),
            createdAt: Date(timeIntervalSince1970: 4_070_908_800), duration: 1, text: "beta", originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: "Notes",
            applicationBundleID: nil, delivery: .verified)
        let gamma = DictationRecord(
            id: .init(rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000082"))),
            createdAt: Date(timeIntervalSince1970: 4_070_908_801), duration: 1, text: "gamma", originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: "Notes",
            applicationBundleID: nil, delivery: .verified)
        let savedBeta = try await base.recordDictation(
            beta, admittedGeneration: policy.generation, at: Date())
        let savedGamma = try await base.recordDictation(
            gamma, admittedGeneration: policy.generation, at: Date())
        XCTAssertEqual(savedBeta, .saved)
        XCTAssertEqual(savedGamma, .saved)
        let model = DictationHistoryModel(store: store)
        let current = DictationRecordFilter(query: "gamma")
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.records.map(\.id), [gamma.id, beta.id])
        XCTAssertNil(model.failure)
        let older = Task { await model.apply(.init(query: "beta")) }
        addTeardownBlock {
            older.cancel()
            _ = await gate.resumeCall(at: 0)
            await older.value
        }
        let held = await gate.waitUntilCallCount(1)
        guard held else {
            XCTFail("the beta failure did not suspend")
            return
        }

        await model.apply(current)

        XCTAssertEqual(model.filter, current)
        XCTAssertEqual(model.records.map(\.id), [gamma.id])
        XCTAssertNil(model.failure)
        XCTAssertFalse(older.isCancelled)
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await older.value

        XCTAssertEqual(model.filter, current)
        XCTAssertEqual(model.records.map(\.id), [gamma.id])
        XCTAssertNil(model.failure)
    }

    func testAnOlderSearchFailureDoesNotPublishWhenItsFilterBecomesCurrentAgain() async throws {
        let base = try DictationStore.inMemory()
        let gate = ControlledTestSleep()
        let store = FlakyStore(
            base, heldRead: (query: "beta", gate: gate), failsHeldRead: true, holdsOnlyFirstRead: true)
        let policy = try await base.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let beta = DictationRecord(
            id: .init(rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000081"))),
            createdAt: Date(timeIntervalSince1970: 4_070_908_800), duration: 1, text: "beta", originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: "Notes",
            applicationBundleID: nil, delivery: .verified)
        let gamma = DictationRecord(
            id: .init(rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000082"))),
            createdAt: Date(timeIntervalSince1970: 4_070_908_801), duration: 1, text: "gamma", originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: "Notes",
            applicationBundleID: nil, delivery: .verified)
        let savedBeta = try await base.recordDictation(
            beta, admittedGeneration: policy.generation, at: Date())
        let savedGamma = try await base.recordDictation(
            gamma, admittedGeneration: policy.generation, at: Date())
        XCTAssertEqual(savedBeta, .saved)
        XCTAssertEqual(savedGamma, .saved)
        let model = DictationHistoryModel(store: store)
        let original = DictationRecordFilter(query: "beta")
        let current = DictationRecordFilter(query: "gamma")
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.records.map(\.id), [gamma.id, beta.id])
        XCTAssertNil(model.failure)
        let older = Task { await model.apply(original) }
        addTeardownBlock {
            older.cancel()
            _ = await gate.resumeCall(at: 0)
            await older.value
        }
        let held = await gate.waitUntilCallCount(1)
        guard held else {
            XCTFail("the beta failure did not suspend")
            return
        }

        await model.apply(current)

        XCTAssertEqual(model.filter, current)
        XCTAssertEqual(model.records.map(\.id), [gamma.id])
        XCTAssertNil(model.failure)
        await model.apply(original)
        XCTAssertEqual(model.filter, original)
        XCTAssertEqual(model.records.map(\.id), [beta.id])
        XCTAssertNil(model.failure)
        XCTAssertFalse(older.isCancelled)
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await older.value

        XCTAssertEqual(model.filter, original)
        XCTAssertEqual(model.records.map(\.id), [beta.id])
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

private struct HeldQueryEmbedding: DictationTextEmbedding {
    let query: String
    let gate: ControlledTestSleep
    private let base = DictationFixtureEmbedding()

    var profile: String { base.profile }

    func isReady() async -> Bool { await base.isReady() }

    func embed(_ text: String) async throws -> [Float] {
        let vector = try await base.embed(text)
        if text == query { try await gate.wait(for: .zero) }
        return vector
    }
}

/// Forwards to a real store, failing the next call when asked.
private final class FlakyStore: DictationHistoryStore, DictationStatsStore {
    struct Failure: Error {}
    private let base: DictationStore
    private let heldRead: (query: String, gate: ControlledTestSleep)?
    private let failsHeldRead: Bool
    private let holdsOnlyFirstRead: Bool
    private let state = Mutex((failing: false, calls: 0, heldReadClaimed: false))

    init(
        _ base: DictationStore, heldRead: (query: String, gate: ControlledTestSleep)? = nil,
        failsHeldRead: Bool = false, holdsOnlyFirstRead: Bool = false
    ) {
        self.base = base
        self.heldRead = heldRead
        self.failsHeldRead = failsHeldRead
        self.holdsOnlyFirstRead = holdsOnlyFirstRead
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
        let snapshot = try await base.dictationRecords(matching: filter, before: cursor, limit: limit)
        if let heldRead, filter.query == heldRead.query, filter.recordID == nil {
            let shouldHold = state.withLock { state in
                guard !holdsOnlyFirstRead || !state.heldReadClaimed else { return false }
                state.heldReadClaimed = true
                return true
            }
            if shouldHold {
                try await heldRead.gate.wait(for: .zero)
                if failsHeldRead { throw Failure() }
            }
        }
        return snapshot
    }
    func dictationRecordsForAgents(
        matching filter: DictationRecordFilter, offset: Int, limit: Int
    ) async throws -> DictationAgentRead<DictationRecordPage> {
        try pass()
        return try await base.dictationRecordsForAgents(matching: filter, offset: offset, limit: limit)
    }
    func searchDictationsForAgents(
        matching filter: DictationRecordFilter, meaning: DictationMeaningQuery?, offset: Int, limit: Int
    ) async throws -> DictationAgentRead<DictationSearchPage> {
        try pass()
        return try await base.searchDictationsForAgents(matching: filter, meaning: meaning, offset: offset, limit: limit)
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
