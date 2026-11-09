import DictationKit
import DictationStore
import Foundation
import SpeechCore
import XCTest

@testable import DictationSession

@MainActor
final class DictationHybridHistoryTests: XCTestCase {
    private func model(embedding: any DictationTextEmbedding = DictationFixtureEmbedding()) async throws
        -> (DictationHistoryModel, DictationSemanticIndex, DictationStore) {
        let store = try DictationStore.inMemory()
        let index = DictationSemanticIndex(store: store, embedding: embedding)
        let model = DictationHistoryModel(store: store, semantic: index)
        await model.load()
        await model.update(isEnabled: true)
        return (model, index, store)
    }

    func testAParaphraseFindsTheDictationByMeaning() async throws {
        let (model, index, _) = try await model()
        let write = try XCTUnwrap(model.admit())
        _ = await write(record("Send the report on Friday.", app: "Slack"))
        _ = await write(record("No borres estas notas.", app: "Notes"))
        await index.backfill()

        await model.apply(.init(query: "summary"))

        XCTAssertEqual(model.records.map(\.text), ["Send the report on Friday."], "no word matches, the meaning does")
    }

    func testWordMatchesComeFirstThenMeaningMatchesAndFiltersApply() async throws {
        let (model, index, _) = try await model()
        let write = try XCTUnwrap(model.admit())
        _ = await write(record("Send the report on Friday.", app: "Slack", minutesAgo: 1))
        _ = await write(record("El informe sale el viernes.", app: "Notes"))
        await index.backfill()

        await model.apply(.init(query: "report"))
        XCTAssertEqual(model.records.map(\.text), ["Send the report on Friday.", "El informe sale el viernes."],
                       "a newer paraphrase never jumps above the word match")

        await model.apply(.init(query: "report", applicationName: "Notes"))
        XCTAssertEqual(model.records.map(\.text), ["El informe sale el viernes."])
    }

    func testWordMatchesKeepTheirPages() async throws {
        let (model, index, _) = try await model()
        let write = try XCTUnwrap(model.admit())
        let count = ListDictations.pageSize + 10
        for minute in 0..<count { _ = await write(record("Report \(minute).", app: "Notes", minutesAgo: minute)) }
        await index.backfill()

        await model.apply(.init(query: "report"))
        XCTAssertEqual(model.records.count, ListDictations.pageSize)
        XCTAssertTrue(model.hasMore)

        await model.loadMore()
        XCTAssertEqual(model.records.count, count, "every word match is reachable, and meaning adds no duplicate")
        XCTAssertFalse(model.hasMore)
    }

    func testASearchOnScreenAddsADictationOnceItsVectorIsSaved() async throws {
        let (model, index, store) = try await model()
        // Saved straight to the store, so only the explicit index call makes its vector.
        let report = record("Send the report on Friday.", app: "Slack")
        _ = try await store.recordDictation(report, admittedGeneration: model.policy.generation, at: Date())
        await model.apply(.init(query: "summary"))
        XCTAssertTrue(model.records.isEmpty)

        await index.index(report)

        XCTAssertEqual(model.records.map(\.id), [report.id], "the shown search refreshed without retyping")
    }

    func testADeletedDictationNeverComesBackByMeaning() async throws {
        let (model, index, _) = try await model()
        let write = try XCTUnwrap(model.admit())
        let report = record("Send the report on Friday.", app: "Slack")
        _ = await write(report)
        await index.backfill()
        await model.apply(.init(query: "summary"))
        XCTAssertEqual(model.records.count, 1)

        await model.delete(report.id)
        await index.index(report)
        await model.apply(.init(query: "informe"))

        XCTAssertTrue(model.records.isEmpty, "a vector computed after the delete is refused")
    }

    func testPunctuationAndAMissingModelMatchWordsOnly() async throws {
        let (model, index, _) = try await model(embedding: Unready())
        let write = try XCTUnwrap(model.admit())
        _ = await write(record("Send the report on Friday.", app: "Slack"))
        await index.backfill()

        await model.apply(.init(query: "summary"))
        XCTAssertTrue(model.records.isEmpty)
        await model.apply(.init(query: "?!"))
        XCTAssertTrue(model.records.isEmpty)
        await model.apply(.init(query: "report"))
        XCTAssertEqual(model.records.map(\.text), ["Send the report on Friday."])
    }

    func testDictationsTheModelCannotEmbedDoNotStallTheBackfill() async throws {
        let (model, index, store) = try await model(embedding: FailsOn(word: "broken"))
        let write = try XCTUnwrap(model.admit())
        _ = await write(record("Send the report on Friday.", app: "Slack", minutesAgo: 5))
        for minute in 0..<3 { _ = await write(record("broken \(minute)", app: "Notes", minutesAgo: minute)) }

        async let first: Void = index.backfill()
        async let second: Void = index.backfill()
        _ = await (first, second)

        let vectors = try await store.dictationEmbeddings(profile: FailsOn(word: "").profile, matching: .all)
        XCTAssertEqual(vectors.count, 1, "the older dictation is reached past the ones that fail")
        await model.apply(.init(query: "report"))
        XCTAssertEqual(model.records.first?.text, "Send the report on Friday.")
    }

    private struct Unready: DictationTextEmbedding {
        var profile: String { "unready" }
        func isReady() async -> Bool { false }
        func embed(_ text: String) async throws -> [Float] { XCTFail("an unready model is never asked"); return [1] }
    }

    private struct FailsOn: DictationTextEmbedding {
        struct Failure: Error {}
        let word: String
        var profile: String { "fails-on-a-word" }
        func isReady() async -> Bool { true }
        func embed(_ text: String) async throws -> [Float] {
            if !word.isEmpty, text.contains(word) { throw Failure() }
            return try await DictationFixtureEmbedding().embed(text)
        }
    }

    private func record(_ text: String, app: String, minutesAgo: Int = 0) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: Date().addingTimeInterval(Double(-minutesAgo * 60)), duration: 1,
            text: text, originalText: nil, mode: .literal, language: nil, engine: "parakeet", applicationName: app,
            applicationBundleID: nil, delivery: .verified)
    }
}
