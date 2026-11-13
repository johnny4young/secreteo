import DictationKit
import Foundation
import SpeechCore
import XCTest

@testable import DictationStore

/// Agent and Shortcuts search: word matches, then dictations close in meaning that hold
/// none of the words, all behind the agent consent of the same read.
final class DictationAgentSearchStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let profile = "test-profile"
    private let near: [Float] = [1, 0]
    private let far: [Float] = [0, 1]

    func testWordMatchesComeFirstThenMeaningOnlyAndTheTotalCountsBoth() async throws {
        let store = try DictationStore.inMemory()
        let generation = try await sharing(store, true).generation
        let newerWord = try await save(store, "Report draft", age: 0, vector: near, generation: generation)
        let olderWord = try await save(store, "Send the report", age: 1, vector: far, generation: generation)
        let paraphrase = try await save(store, "Mail the summary", age: 2, vector: near, generation: generation)
        _ = try await save(store, "Buy bread", age: 3, vector: far, generation: generation)

        let all = try await search(store, "report", offset: 0, limit: 10)
        XCTAssertEqual(all.page.records.map(\.id), [newerWord, olderWord, paraphrase].map(\.id))
        XCTAssertEqual(all.page.total, 3)
        XCTAssertEqual(all.meaningMatches, 1)
        XCTAssertEqual((0..<3).map(all.matchesByMeaning(at:)), [false, false, true])

        let across = try await search(store, "report", offset: 1, limit: 2)
        XCTAssertEqual(across.page.records.map(\.id), [olderWord, paraphrase].map(\.id))
        XCTAssertEqual((0..<2).map(across.matchesByMeaning(at:)), [false, true])
        let past = try await search(store, "report", offset: 3, limit: 2)
        XCTAssertEqual(past.page.records, [])
        XCTAssertEqual(past.page.total, 3)
    }

    func testNothingIsReadUntilTheHistoryIsShared() async throws {
        let store = try DictationStore.inMemory()
        let generation = try await sharing(store, false).generation
        _ = try await save(store, "Mail the summary", age: 0, vector: near, generation: generation)

        let read = try await store.searchDictationsForAgents(
            matching: .init(query: "report"), meaning: .init(profile: profile, vector: near), offset: 0, limit: 10)
        XCTAssertEqual(read, .notAllowed)
    }

    func testMeaningNeedsSearchableWordsAVectorFromTheSameModelAndTheSameFilter() async throws {
        let store = try DictationStore.inMemory()
        let generation = try await sharing(store, true).generation
        _ = try await save(store, "Mail the summary", age: 0, vector: near, generation: generation)
        _ = try await save(store, "Write the notes", age: 1, vector: near, application: "Mail", generation: generation)

        let wordsOnly = try await search(store, "report", meaning: nil)
        let otherModel = try await search(store, "report", meaning: .init(profile: "other", vector: near))
        let punctuation = try await search(store, "?!", meaning: .init(profile: profile, vector: near))
        let oneApp = try await search(
            store, "report", application: "Mail", meaning: .init(profile: profile, vector: near))

        XCTAssertEqual(wordsOnly.page.total, 0)
        XCTAssertEqual(otherModel.page.total, 0, "vectors from another model are never compared")
        XCTAssertEqual(punctuation.page.total, 0)
        XCTAssertEqual(oneApp.page.records.map(\.text), ["Write the notes"])
        XCTAssertEqual(oneApp.meaningMatches, 1)
    }

    func testMeaningKeepsTheUndeliveredFilterAndSkipsWordMatchesBeyondThePage() async throws {
        let store = try DictationStore.inMemory()
        let generation = try await sharing(store, true).generation
        for index in 0..<150 {
            _ = try await save(store, "Report \(index)", age: Double(index), vector: near, generation: generation)
        }
        let undelivered = try await save(
            store, "Mail the summary", age: 200, vector: near, delivery: .notDelivered, generation: generation)
        _ = try await save(store, "Write the summary", age: 201, vector: near, generation: generation)

        let all = try await search(store, "report", offset: 148, limit: 10)
        XCTAssertEqual(all.page.total, 152)
        XCTAssertEqual(all.meaningMatches, 2, "word matches past the first page are never listed again")
        XCTAssertEqual(all.page.records.map(\.text), ["Report 148", "Report 149", "Mail the summary", "Write the summary"])

        let read = try await store.searchDictationsForAgents(
            matching: .init(query: "report", onlyNotDelivered: true),
            meaning: .init(profile: profile, vector: near), offset: 0, limit: 10)
        guard case .allowed(let filtered) = read else { return XCTFail("sharing is on") }
        XCTAssertEqual(filtered.page.records.map(\.id), [undelivered.id])
    }

    func testMeaningListsAtMostTheHistoryWindowsLimit() async throws {
        let store = try DictationStore.inMemory()
        let generation = try await sharing(store, true).generation
        for index in 0...DictationHybridSearch.semanticLimit {
            _ = try await save(store, "Paraphrase \(index)", age: Double(index), vector: near, generation: generation)
        }

        let result = try await search(store, "report", offset: 0, limit: 50)
        XCTAssertEqual(result.meaningMatches, DictationHybridSearch.semanticLimit)
        XCTAssertEqual(result.page.total, DictationHybridSearch.semanticLimit)
    }

    private func search(
        _ store: DictationStore, _ query: String, application: String? = nil,
        meaning: DictationMeaningQuery? = .init(profile: "test-profile", vector: [1, 0]), offset: Int = 0,
        limit: Int = 10
    ) async throws -> DictationSearchPage {
        let read = try await store.searchDictationsForAgents(
            matching: .init(query: query, applicationName: application),
            meaning: meaning, offset: offset, limit: limit)
        guard case .allowed(let page) = read else {
            XCTFail("sharing is on")
            return DictationSearchPage(page: .init(total: 0, offset: 0, records: []), meaningMatches: 0)
        }
        return page
    }

    @discardableResult
    private func sharing(_ store: DictationStore, _ shared: Bool) async throws -> DictationHistoryPolicy {
        try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, exposesToAgents: shared, at: now)
    }

    private func save(
        _ store: DictationStore, _ text: String, age: Double, vector: [Float], application: String = "Notes",
        delivery: DictationRecordDelivery = .verified, generation: Int
    ) async throws -> DictationRecord {
        let record = DictationRecord(
            id: DictationRecordID(), createdAt: now.addingTimeInterval(-age), duration: 2, text: text,
            originalText: nil, mode: .literal, language: nil, engine: "parakeet", applicationName: application,
            applicationBundleID: nil, delivery: delivery)
        _ = try await store.recordDictation(record, admittedGeneration: generation, at: now)
        let saved = try await store.saveDictationEmbedding(.init(recordID: record.id, vector: vector), profile: profile)
        XCTAssertTrue(saved)
        return record
    }
}
