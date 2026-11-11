import DictationKit
import SpeechCore
import DictationStore
import XCTest

@testable import DictationSession

@MainActor
final class DictationHistoryModelTests: XCTestCase {
    func testAFilteredListOnlyShowsMatchingDictationsWhileTheMenuLearnsNewApps() async throws {
        let model = DictationHistoryModel(store: try DictationStore.inMemory())
        await model.load()
        await model.update(isEnabled: true)
        let write = try XCTUnwrap(model.admit())
        _ = await write(record("Send the report on Friday.", app: "Slack"))
        _ = await write(record("No borres estas notas.", app: "Notes"))

        await model.apply(.init(applicationName: "Slack"))
        XCTAssertEqual(model.records.map(\.text), ["Send the report on Friday."])

        _ = await write(record("Reply to the thread.", app: "Mail"))
        XCTAssertEqual(model.records.map(\.text), ["Send the report on Friday."], "A new row must match the filter")
        XCTAssertEqual(model.applications, ["Mail", "Notes", "Slack"])

        await model.apply(.init(query: "notas"))
        XCTAssertEqual(model.records.map(\.text), ["No borres estas notas."])
        await model.apply(.all)
        XCTAssertEqual(model.records.count, 3)

        await model.deleteAll()
        XCTAssertEqual(model.filter, .all)
        XCTAssertEqual(model.applications, [])
    }

    func testARetryAfterTheUserDeletesTheDictationSavesNothing() async throws {
        let store = try DictationStore.inMemory()
        let model = DictationHistoryModel(store: store)
        await model.load()
        await model.update(isEnabled: true)
        let write = try XCTUnwrap(model.admit())
        let dictation = record("Texto que no debe volver.", app: "Notes").with(delivery: .notDelivered)
        _ = await write(dictation)
        await model.delete(dictation.id)

        _ = await write(dictation.with(delivery: .verified))

        let saved = try await store.dictationRecords(limit: 10)
        XCTAssertEqual(model.records, [])
        XCTAssertEqual(saved, [])
    }

    func testApplyingAllBeforeLoadKeepsInitialRowsUnloaded() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let existing = record("An existing dictation.", app: "Notes")
        let saved = try await store.recordDictation(
            existing, admittedGeneration: policy.generation, at: Date())
        XCTAssertEqual(saved, .saved)
        let model = DictationHistoryModel(store: store)

        await model.apply(.all)

        XCTAssertFalse(model.isLoaded)
        XCTAssertTrue(model.records.isEmpty)
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.records.map(\.id), [existing.id])
    }

    private func record(_ text: String, app: String) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: Date(), duration: 1, text: text, originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: app,
            applicationBundleID: nil, delivery: .verified)
    }
}
