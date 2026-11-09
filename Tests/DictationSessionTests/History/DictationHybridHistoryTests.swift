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

    func testAQuestionInTheOtherLanguageFindsTheDictationByMeaning() async throws {
        let (model, index, _) = try await model()
        let write = try XCTUnwrap(model.admit())
        _ = await write(record("Send the report on Friday.", app: "Slack"))
        _ = await write(record("No borres estas notas.", app: "Notes"))
        await index.backfill()

        await model.apply(.init(query: "informe"))

        XCTAssertEqual(model.records.map(\.text), ["Send the report on Friday."], "no word matches, the meaning does")
        XCTAssertFalse(model.hasMore, "a ranked search is one page")
    }

    func testAWordMatchStaysFirstAndFiltersStillApply() async throws {
        let (model, index, _) = try await model()
        let write = try XCTUnwrap(model.admit())
        _ = await write(record("Send the report on Friday.", app: "Slack"))
        _ = await write(record("El informe sale el viernes.", app: "Notes"))
        await index.backfill()

        await model.apply(.init(query: "report"))
        XCTAssertEqual(model.records.first?.text, "Send the report on Friday.")
        XCTAssertEqual(Set(model.records.map(\.text)), ["Send the report on Friday.", "El informe sale el viernes."])

        await model.apply(.init(query: "report", applicationName: "Notes"))
        XCTAssertEqual(model.records.map(\.text), ["El informe sale el viernes."])
    }

    func testANewDictationIsFoundByMeaningOnceItsVectorIsSaved() async throws {
        let (model, index, store) = try await model()
        let write = try XCTUnwrap(model.admit())
        let report = record("Send the report on Friday.", app: "Slack")
        _ = await write(report)
        await index.index(report)
        let vectors = try await store.dictationEmbeddings(profile: DictationFixtureEmbedding().profile, matching: .all)
        XCTAssertEqual(vectors.map(\.recordID), [report.id])

        await model.apply(.init(query: "informe"))
        XCTAssertEqual(model.records.map(\.id), [report.id])
    }

    func testADeletedDictationNeverComesBackByMeaning() async throws {
        let (model, index, _) = try await model()
        let write = try XCTUnwrap(model.admit())
        let report = record("Send the report on Friday.", app: "Slack")
        _ = await write(report)
        await index.backfill()
        await model.apply(.init(query: "informe"))
        XCTAssertEqual(model.records.count, 1)

        await model.delete(report.id)
        await index.index(report)
        await model.apply(.init(query: "informe"))

        XCTAssertTrue(model.records.isEmpty, "a vector computed after the delete is refused")
    }

    func testWithoutTheModelSearchMatchesWordsAndPagesAsBefore() async throws {
        let (model, index, _) = try await model(embedding: Unready())
        let write = try XCTUnwrap(model.admit())
        _ = await write(record("Send the report on Friday.", app: "Slack"))
        await index.backfill()

        await model.apply(.init(query: "informe"))
        XCTAssertTrue(model.records.isEmpty)
        await model.apply(.init(query: "report"))
        XCTAssertEqual(model.records.map(\.text), ["Send the report on Friday."])
    }

    func testABackfillThatSavesNothingStops() async throws {
        let (model, index, _) = try await model(embedding: Failing())
        let write = try XCTUnwrap(model.admit())
        _ = await write(record("Send the report on Friday.", app: "Slack"))

        await index.backfill()
        await model.apply(.init(query: "report"))

        XCTAssertEqual(model.records.map(\.text), ["Send the report on Friday."], "words still match")
    }

    private struct Unready: DictationTextEmbedding {
        var profile: String { "unready" }
        func isReady() async -> Bool { false }
        func embed(_ text: String) async throws -> [Float] { XCTFail("an unready model is never asked"); return [1] }
    }

    private struct Failing: DictationTextEmbedding {
        struct Failure: Error {}
        var profile: String { "failing" }
        func isReady() async -> Bool { true }
        func embed(_ text: String) async throws -> [Float] { throw Failure() }
    }

    private func record(_ text: String, app: String) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: Date(), duration: 1, text: text, originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: app,
            applicationBundleID: nil, delivery: .verified)
    }
}
