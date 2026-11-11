import Foundation
import GRDB
import DictationKit
import SpeechCore
import XCTest

@testable import DictationStore

final class DictationHistoryStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testV1AddsAnOffConsentRowAndTheRecordTable() throws {
        let database = try DatabaseQueue()
        try DictationSchema.migrator().migrate(database, upTo: "v1")
        try database.read { database in
            XCTAssertEqual(
                try String.fetchOne(database, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid DESC"),
                "v1")
            let policy = try Row.fetchOne(database, sql: "SELECT * FROM dictationHistoryPolicy")
            XCTAssertEqual(policy?["isEnabled"], false)
            XCTAssertEqual(policy?["keepsOriginal"], false)
            XCTAssertEqual(policy?["retentionDays"], 30)
            XCTAssertEqual(try Set(database.columns(in: "dictationRecord").map(\.name)), [
                "id", "createdAt", "durationMs", "text", "originalText", "mode", "language",
                "engine", "applicationName", "applicationBundleID", "delivery"
            ])
        }
    }

    func testNothingIsSavedUntilHistoryIsTurnedOn() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.dictationHistoryPolicy()
        let outcome = try await store.recordDictation(record(), admittedGeneration: 0, at: now)
        let saved = try await store.dictationRecords(limit: 10)

        XCTAssertEqual(policy, .off)
        XCTAssertEqual(outcome, .refused)
        XCTAssertEqual(saved, [])
    }

    func testSavingKeepsTheOriginalOnlyWhenAskedAndRetriesUpdateTheDelivery() async throws {
        let store = try DictationStore.inMemory()
        try await enable(store)
        let dictation = record(original: "eh no borres estas notas")
        let first = try await store.recordDictation(dictation, admittedGeneration: 0, at: now)
        let retry = try await store.recordDictation(dictation.with(delivery: .verified), admittedGeneration: 0, at: now)
        let saved = try await store.dictationRecords(limit: 10)

        XCTAssertEqual([first, retry], [.saved, .saved])
        XCTAssertEqual(saved.count, 1)
        XCTAssertNil(saved.first?.originalText)
        XCTAssertEqual(saved.first?.delivery, .verified)
        XCTAssertEqual(saved.first?.applicationName, "Notes")

        try await enable(store, keepsOriginal: true)
        _ = try await store.recordDictation(record(original: "eh second", text: "Second"), admittedGeneration: 0, at: now)
        let second = try await store.dictationRecords(limit: 10).first { $0.text == "Second" }
        XCTAssertEqual(second?.originalText, "eh second")
    }

    func testTurningOffOrDeletingAllRefusesADictationAdmittedEarlier() async throws {
        let store = try DictationStore.inMemory()
        let admitted = try await enable(store).generation
        _ = try await store.setDictationHistoryPolicy(isEnabled: false, keepsOriginal: false, retentionDays: 30, at: now)
        let current = try await enable(store).generation

        let stale = try await store.recordDictation(record(), admittedGeneration: admitted, at: now)
        let fresh = try await store.recordDictation(record(), admittedGeneration: current, at: now)
        let deleted = try await store.deleteAllDictationRecords()
        let afterDeleteAll = try await store.recordDictation(record(), admittedGeneration: current, at: now)
        let remaining = try await store.dictationRecords(limit: 10)

        XCTAssertEqual(stale, .refused)
        XCTAssertEqual(fresh, .saved)
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(afterDeleteAll, .refused)
        XCTAssertEqual(remaining, [])
    }

    func testARetryAfterADeleteNeverBringsTheDictationBack() async throws {
        let store = try DictationStore.inMemory()
        try await enable(store)
        let dictation = record()
        let first = try await store.recordDictation(dictation, admittedGeneration: 0, at: now)
        let deleted = try await store.deleteDictationRecord(dictation.id)
        let retry = try await store.recordDictation(dictation.with(delivery: .verified), admittedGeneration: 0, at: now)
        let vector = try await store.saveDictationEmbedding(.init(recordID: dictation.id, vector: [1, 0]), profile: "p")
        let other = try await store.recordDictation(record(text: "Otra nota."), admittedGeneration: 0, at: now)
        let saved = try await store.dictationRecords(limit: 10)

        XCTAssertEqual([first, retry, other], [.saved, .refused, .saved])
        XCTAssertTrue(deleted)
        XCTAssertFalse(vector)
        XCTAssertEqual(saved.map(\.text), ["Otra nota."])
    }

    func testADeleteThatRollsBackLeavesRetriesAsTheyWere() async throws {
        let store = try DictationStore.inMemory()
        try await enable(store)
        let gone = record(text: "Borrada.")
        let kept = record(text: "Sigue aquí.")
        _ = try await store.recordDictation(gone, admittedGeneration: 0, at: now)
        _ = try await store.recordDictation(kept, admittedGeneration: 0, at: now)
        _ = try await store.deleteDictationRecord(gone.id)
        try await store.database.write { database in
            try database.execute(
                sql: "CREATE TABLE pin (recordID TEXT REFERENCES dictationRecord(id) DEFERRABLE INITIALLY DEFERRED)")
            try database.execute(sql: "INSERT INTO pin VALUES (?)", arguments: [kept.id.rawValue.uuidString])
        }

        let deleteOne = try? await store.deleteDictationRecord(kept.id)
        let keptRetry = try await store.recordDictation(kept.with(delivery: .verified), admittedGeneration: 0, at: now)
        let deleteAll = try? await store.deleteAllDictationRecords()
        let goneRetry = try await store.recordDictation(gone.with(delivery: .verified), admittedGeneration: 0, at: now)
        let saved = try await store.dictationRecords(limit: 10)

        XCTAssertNil(deleteOne)
        XCTAssertNil(deleteAll)
        XCTAssertEqual([keptRetry, goneRetry], [.saved, .refused])
        XCTAssertEqual(saved.map(\.text), ["Sigue aquí."])
        XCTAssertEqual(saved.map(\.delivery), [.verified])
    }

    func testRetentionPurgesOldDictationsAndAShorterChoiceAppliesAtOnce() async throws {
        let store = try DictationStore.inMemory()
        try await enable(store)
        let day: TimeInterval = 86_400
        for age in [1.0, 10, 40] {
            let createdAt = now.addingTimeInterval(-age * day)
            _ = try await store.recordDictation(record(createdAt: createdAt), admittedGeneration: 0, at: createdAt)
        }
        let purged = try await store.purgeExpiredDictationRecords(at: now)
        let withinThirtyDays = try await store.dictationRecords(limit: 10).count
        _ = try await store.setDictationHistoryPolicy(isEnabled: true, keepsOriginal: false, retentionDays: 7, at: now)
        let withinSevenDays = try await store.dictationRecords(limit: 10).count

        XCTAssertEqual(purged, 1)
        XCTAssertEqual(withinThirtyDays, 2)
        XCTAssertEqual(withinSevenDays, 1)
    }

    func testPagesAreNewestFirstWithoutGapsOrRepeats() async throws {
        let store = try DictationStore.inMemory()
        try await enable(store)
        let sameInstant = now.addingTimeInterval(-60)
        for index in 0..<5 {
            let createdAt = index < 3 ? sameInstant : now.addingTimeInterval(Double(-index))
            _ = try await store.recordDictation(record(createdAt: createdAt), admittedGeneration: 0, at: now)
        }
        let first = try await store.dictationRecords(limit: 2)
        let second = try await store.dictationRecords(before: first.last, limit: 2)
        let third = try await store.dictationRecords(before: second.last, limit: 2)
        let unbounded = try await store.dictationRecords(limit: 0)
        let all = first + second + third

        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(Set(all.map(\.id)).count, 5)
        XCTAssertEqual(all.map(\.createdAt), all.map(\.createdAt).sorted(by: >))
        XCTAssertEqual(unbounded, [])
    }

    func testInvalidRecordsAndRetentionsAreRejected() async throws {
        let store = try DictationStore.inMemory()
        try await enable(store)
        do {
            _ = try await store.recordDictation(record(text: "  "), admittedGeneration: 0, at: now)
            XCTFail("Blank text must not be stored")
        } catch {}
        do {
            _ = try await store.setDictationHistoryPolicy(
                isEnabled: true, keepsOriginal: false, retentionDays: 365, at: now)
            XCTFail("Only the offered retention choices are stored")
        } catch {}
        let deletedUnknown = try await store.deleteDictationRecord(DictationRecordID())
        XCTAssertFalse(deletedUnknown)
    }

    @discardableResult
    private func enable(_ store: DictationStore, keepsOriginal: Bool = false) async throws -> DictationHistoryPolicy {
        try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: keepsOriginal, retentionDays: 30, at: now)
    }

    private func record(
        original: String? = nil, text: String = "No borres estas notas.", createdAt: Date? = nil
    ) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: createdAt ?? now, duration: 2.5, text: text,
            originalText: original, mode: .clean, language: "es", engine: "parakeet",
            applicationName: "Notes", applicationBundleID: "com.apple.Notes", delivery: .notDelivered)
    }
}
