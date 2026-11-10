import DictationKit
import Foundation
import GRDB
import SpeechCore
import Testing

@testable import DictationStore

@Suite
struct DictationEmbeddingStoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func aVectorRoundTripsAndASecondSaveReplacesIt() async throws {
        let store = try await historyStore()
        let saved = try await save("Uno.", app: "Notes", into: store)
        let first: [Float] = [0.5, -1.25, 3e-8, -0.0, 1_000]

        #expect(try await store.saveDictationEmbedding(.init(recordID: saved.id, vector: first), profile: "model-a"))
        #expect(try await store.dictationEmbeddings(profile: "model-a") == [.init(recordID: saved.id, vector: first)])

        #expect(try await store.saveDictationEmbedding(.init(recordID: saved.id, vector: [1, 2]), profile: "model-b"))
        #expect(try await store.dictationEmbeddings(profile: "model-a").isEmpty, "one vector per dictation")
        #expect(try await store.dictationEmbeddings(profile: "model-b") == [.init(recordID: saved.id, vector: [1, 2])])
    }

    @Test
    func aVectorForADeletedDictationIsNotKept() async throws {
        let store = try await historyStore()
        let saved = try await save("Se borra.", app: "Notes", into: store)
        _ = try await store.deleteDictationRecord(saved.id)

        #expect(try await !store.saveDictationEmbedding(.init(recordID: saved.id, vector: [1]), profile: "model"))
        #expect(try await store.dictationEmbeddings(profile: "model").isEmpty)
    }

    @Test
    func deletingADictationDeletesItsVector() async throws {
        let store = try await historyStore()
        let kept = try await save("Se queda.", app: "Notes", into: store)
        let gone = try await save("Se va.", app: "Notes", into: store)
        for record in [kept, gone] {
            _ = try await store.saveDictationEmbedding(.init(recordID: record.id, vector: [1]), profile: "model")
        }

        _ = try await store.deleteDictationRecord(gone.id)

        #expect(try await store.dictationEmbeddings(profile: "model").map(\.recordID) == [kept.id])
        let rows = try await store.database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM dictationEmbedding") }
        #expect(rows == 1)
    }

    @Test
    func vectorsFollowTheApplicationAndDeliveryFilterButNotItsWords() async throws {
        let store = try await historyStore()
        let notes = try await save("Una nota.", app: "Notes", into: store)
        let slack = try await save("Un mensaje.", app: "Slack", delivery: .notDelivered, into: store)
        for record in [notes, slack] {
            _ = try await store.saveDictationEmbedding(.init(recordID: record.id, vector: [1]), profile: "model")
        }

        let byApp = try await store.dictationEmbeddings(profile: "model", matching: .init(applicationName: "Notes"))
        let undelivered = try await store.dictationEmbeddings(profile: "model", matching: .init(onlyNotDelivered: true))
        let worded = try await store.dictationEmbeddings(profile: "model", matching: .init(query: "nada"))
        let one = try await store.dictationEmbeddings(profile: "model", matching: .init(recordID: slack.id))

        #expect(byApp.map(\.recordID) == [notes.id])
        #expect(one.map(\.recordID) == [slack.id])
        #expect(try await store.dictationEmbeddingIDs(profile: "model", matching: .init(applicationName: "Slack")) == [slack.id])
        #expect(try await store.dictationEmbeddingIDs(profile: "model") == [notes.id, slack.id])
        #expect(try await store.dictationEmbeddingIDs(profile: "other").isEmpty)
        #expect(undelivered.map(\.recordID) == [slack.id])
        #expect(Set(worded.map(\.recordID)) == [notes.id, slack.id])
    }

    @Test
    func dictationsWithoutThisModelsVectorAreListedNewestFirst() async throws {
        let store = try await historyStore()
        let older = try await save("Antes.", app: "Notes", at: now.addingTimeInterval(-60), into: store)
        let newer = try await save("Después.", app: "Notes", into: store)
        let done = try await save("Hecho.", app: "Notes", at: now.addingTimeInterval(-30), into: store)
        _ = try await store.saveDictationEmbedding(.init(recordID: done.id, vector: [1]), profile: "model")
        _ = try await store.saveDictationEmbedding(.init(recordID: older.id, vector: [1]), profile: "old-model")

        let missing = try await store.dictationRecordsMissingEmbedding(profile: "model", limit: 10)

        #expect(missing.map(\.id) == [newer.id, older.id], "another model's vector counts as missing")
        #expect(try await store.dictationRecordsMissingEmbedding(profile: "model", limit: 0).isEmpty)
    }

    @Test
    func missingVectorPagesContinuePastAnIndexedCursorWithEqualDates() async throws {
        let store = try await historyStore()
        let first = try await save("First.", app: "Notes", id: .init(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!), into: store)
        let second = try await save("Second.", app: "Notes", id: .init(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!), into: store)
        let third = try await save("Third.", app: "Notes", id: .init(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), into: store)

        let page = try await store.dictationRecordsMissingEmbedding(profile: "model", limit: 2)
        #expect(page.map(\.id) == [first.id, second.id])
        #expect(try await store.saveDictationEmbedding(.init(recordID: second.id, vector: [1]), profile: "model"))
        let next = try await store.dictationRecordsMissingEmbedding(profile: "model", before: second, limit: 2)

        #expect(next.map(\.id) == [third.id])
    }

    @Test
    func recordsComeBackInTheOrderAskedWithoutTheMissingOnes() async throws {
        let store = try await historyStore()
        let first = try await save("Primero.", app: "Notes", into: store)
        let second = try await save("Segundo.", app: "Notes", at: now.addingTimeInterval(-10), into: store)

        let records = try await store.dictationRecords(ids: [second.id, DictationRecordID(), first.id])

        #expect(records.map(\.id) == [second.id, first.id])
        #expect(try await store.dictationRecords(ids: []).isEmpty)
    }

    @Test
    func moreIDsThanOnePageStillComeBackInOrder() async throws {
        let store = try await historyStore()
        var saved: [DictationRecord] = []
        for index in 0..<(DictationStore.maximumDictationPageSize + 20) {
            saved.append(try await save("Nota \(index).", app: "Notes", at: now.addingTimeInterval(-Double(index)), into: store))
        }
        let asked = saved.map(\.id).reversed().map { $0 }

        #expect(try await store.dictationRecords(ids: asked).map(\.id) == asked)
    }

    @Test
    func anUnusableVectorIsRefused() async throws {
        let store = try await historyStore()
        let saved = try await save("Uno.", app: "Notes", into: store)
        let unusable: [[Float]] = [
            [], [.nan], [0, 0, 0], [Float](repeating: 1, count: DictationEmbedding.maximumDimension + 1)
        ]
        for vector in unusable {
            await #expect(throws: DictationStoreError.self) {
                try await store.saveDictationEmbedding(.init(recordID: saved.id, vector: vector), profile: "model")
            }
        }
        // 150 characters, each a letter and a combining accent: 300 code points for SQLite.
        let decomposed = String(repeating: "e\u{301}", count: 150)
        for profile in ["", decomposed] {
            await #expect(throws: DictationStoreError.self) {
                try await store.saveDictationEmbedding(.init(recordID: saved.id, vector: [1]), profile: profile)
            }
        }
    }

    private func historyStore() async throws -> DictationStore {
        let store = try DictationStore.inMemory()
        _ = try await store.setDictationHistoryPolicy(isEnabled: true, keepsOriginal: false, retentionDays: 30, at: now)
        return store
    }

    private func save(
        _ text: String, app: String, delivery: DictationRecordDelivery = .verified, at createdAt: Date? = nil,
        id: DictationRecordID = DictationRecordID(),
        into store: DictationStore
    ) async throws -> DictationRecord {
        let record = DictationRecord(
            id: id, createdAt: createdAt ?? now, duration: 1, text: text, originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: app, applicationBundleID: nil,
            delivery: delivery)
        #expect(try await store.recordDictation(record, admittedGeneration: 0, at: now) == .saved)
        return record
    }
}
