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
        let (model, _, store) = try await model()
        let write = try XCTUnwrap(model.admit())
        let report = record("Send the report on Friday.", app: "Slack")
        let notes = record("No borres estas notas.", app: "Notes")
        _ = await write(report)
        _ = await write(notes)
        try await waitForVectors([report.id, notes.id], in: store)

        await model.apply(.init(query: "summary"))

        XCTAssertEqual(model.records.map(\.text), ["Send the report on Friday."], "no word matches, the meaning does")
    }

    func testWordMatchesComeFirstThenMeaningMatchesAndFiltersApply() async throws {
        let (model, _, store) = try await model()
        let write = try XCTUnwrap(model.admit())
        let report = record("Send the report on Friday.", app: "Slack", minutesAgo: 1)
        let paraphrase = record("El informe sale el viernes.", app: "Notes")
        _ = await write(report)
        _ = await write(paraphrase)
        try await waitForVectors([report.id, paraphrase.id], in: store)

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

    func testAnOlderMeaningReadCannotReplaceANewerVectorRefresh() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let first = fixedRecord("report antiguo", id: "00000000-0000-0000-0000-000000000031", time: 4_070_908_800)
        let second = fixedRecord("informe nuevo", id: "00000000-0000-0000-0000-000000000032", time: 4_070_908_860)
        let firstSaved = try await store.recordDictation(first, admittedGeneration: policy.generation, at: Date())
        let secondSaved = try await store.recordDictation(second, admittedGeneration: policy.generation, at: Date())
        XCTAssertEqual(firstSaved, .saved)
        XCTAssertEqual(secondSaved, .saved)
        let gate = ControlledTestSleep()
        let index = DictationSemanticIndex(
            store: HeldMeaningStore(store: store, gate: gate, holdSingleOnly: true, skipBackfill: true),
            embedding: DictationFixtureEmbedding())
        let model = DictationHistoryModel(store: store, semantic: index)
        await model.load()
        await model.apply(.init(query: "summary"))
        XCTAssertTrue(model.records.isEmpty)

        let firstIndex = Task { await index.index(first) }
        let held = await gate.waitUntilCallCount(1)
        guard held else {
            firstIndex.cancel()
            XCTFail("the first meaning read did not suspend")
            return
        }
        await index.index(second)
        XCTAssertEqual(model.records.map(\.id), [first.id, second.id])

        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await firstIndex.value

        XCTAssertEqual(model.records.map(\.id), [first.id, second.id])
    }

    func testAFirstSearchIncludesAVectorSavedWhileItsLibraryReadIsPending() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let first = fixedRecord("report antiguo", id: "00000000-0000-0000-0000-000000000041", time: 4_070_908_800)
        let second = fixedRecord("informe nuevo", id: "00000000-0000-0000-0000-000000000042", time: 4_070_908_860)
        let firstSaved = try await store.recordDictation(first, admittedGeneration: policy.generation, at: Date())
        let secondSaved = try await store.recordDictation(second, admittedGeneration: policy.generation, at: Date())
        XCTAssertEqual(firstSaved, .saved)
        XCTAssertEqual(secondSaved, .saved)
        let embedding = DictationFixtureEmbedding()
        let firstVector = try await embedding.embed(first.text)
        let firstIndexed = try await store.saveDictationEmbedding(
            .init(recordID: first.id, vector: firstVector), profile: embedding.profile)
        XCTAssertTrue(firstIndexed)
        let gate = ControlledTestSleep()
        let index = DictationSemanticIndex(
            store: HeldMeaningStore(store: store, gate: gate, holdSingleOnly: true, holdLibraryRead: true),
            embedding: embedding)
        let model = DictationHistoryModel(store: store, semantic: index)
        model.show(search: "summary")
        let loading = Task { await model.load() }
        addTeardownBlock {
            loading.cancel()
            _ = await gate.resumeCall(at: 0)
            await loading.value
        }
        let held = await gate.waitUntilCallCount(1)
        guard held else {
            loading.cancel()
            await loading.value
            XCTFail("the first library read did not suspend")
            return
        }
        XCTAssertFalse(model.isLoaded)

        await index.index(second)
        XCTAssertFalse(model.isLoaded)
        let vectors = try await store.dictationEmbeddings(profile: embedding.profile, matching: .all)
        XCTAssertEqual(Set(vectors.map(\.recordID)), [first.id, second.id])
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await loading.value
        await index.backfill()

        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.records.map(\.id), [first.id, second.id])
    }

    func testANewWordMatchStaysAheadOfParaphrasesInAnOpenSearch() async throws {
        let (model, index, store) = try await model()
        let old = fixedRecord("report antiguo", id: "00000000-0000-0000-0000-000000000002", time: 4_070_908_800)
        let paraphrase = fixedRecord("summary", id: "00000000-0000-0000-0000-000000000001", time: 4_070_908_810)
        let new = fixedRecord("report nuevo", id: "00000000-0000-0000-0000-000000000003", time: 4_070_908_860)
        _ = try await store.recordDictation(old, admittedGeneration: model.policy.generation, at: Date())
        _ = try await store.recordDictation(paraphrase, admittedGeneration: model.policy.generation, at: Date())
        await index.index(old)
        await index.index(paraphrase)
        await model.apply(.init(query: "report"))
        XCTAssertEqual(model.records.map(\.id), [old.id, paraphrase.id])

        let write = try XCTUnwrap(model.admit())
        let saved = await write(new)
        XCTAssertTrue(saved)
        await index.index(new)

        XCTAssertEqual(model.records.map(\.id), [new.id, old.id, paraphrase.id])
    }

    func testNewWordMatchKeepsLoadedPagesAndOtherFilters() async throws {
        let (model, _, store) = try await model(embedding: Unready())
        for minute in 0..<51 {
            let item = record("report \(minute)", app: "Notes", minutesAgo: minute)
            _ = try await store.recordDictation(item, admittedGeneration: model.policy.generation, at: Date())
        }
        await model.apply(.init(query: "report", applicationName: "Notes"))
        XCTAssertEqual(model.records.count, 50)
        XCTAssertTrue(model.hasMore)
        let write = try XCTUnwrap(model.admit())
        let excluded = record("report from Slack", app: "Slack")
        let included = fixedRecord("report nuevo", id: "00000000-0000-0000-0000-000000000004", time: 4_070_908_860)

        _ = await write(excluded)
        _ = await write(included)

        XCTAssertEqual(model.records.count, 50)
        XCTAssertEqual(model.records.first?.id, included.id)
        XCTAssertFalse(model.records.contains { $0.id == excluded.id })
        XCTAssertTrue(model.hasMore)
        await model.loadMore()
        XCTAssertEqual(model.records.count, 52)
        XCTAssertFalse(model.hasMore)
    }

    func testDeletingWhileAFilterLoadsStillShowsTheNewFilter() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let alpha = record("alpha", app: "Notes")
        let beta = record("beta", app: "Notes")
        _ = try await store.recordDictation(alpha, admittedGeneration: policy.generation, at: Date())
        _ = try await store.recordDictation(beta, admittedGeneration: policy.generation, at: Date())
        let gate = ControlledTestSleep()
        let reader = HeldHistoryRead(gate: gate, kind: .page("beta"), count: 1)
        let model = DictationHistoryModel(store: HeldHistoryStore(store: store, reader: reader))
        await model.load()
        await model.apply(.init(query: "alpha"))
        let changeFilter = Task { await model.apply(.init(query: "beta")) }
        let held = await gate.waitUntilCallCount(1)
        XCTAssertTrue(held)

        await model.delete(alpha.id)
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await changeFilter.value

        XCTAssertEqual(model.records.map(\.id), [beta.id])
    }

    func testCancellingATypedSearchDoesNotPublishALoadFailure() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let alpha = fixedRecord("alpha", id: "00000000-0000-0000-0000-000000000061", time: 4_070_908_800)
        let saved = try await store.recordDictation(
            alpha, admittedGeneration: policy.generation, at: Date())
        XCTAssertEqual(saved, .saved)
        let gate = ControlledTestSleep()
        let reader = HeldHistoryRead(gate: gate, kind: .page("beta"), count: 1)
        let model = DictationHistoryModel(store: HeldHistoryStore(store: store, reader: reader))
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.records.map(\.id), [alpha.id])
        XCTAssertNil(model.failure)
        let search = Task { await model.apply(.init(query: "beta")) }
        addTeardownBlock {
            search.cancel()
            _ = await gate.resumeCall(at: 0)
            await search.value
        }
        let held = await gate.waitUntilCallCount(1)
        guard held else {
            XCTFail("the beta page did not suspend")
            return
        }

        search.cancel()
        await search.value

        XCTAssertEqual(model.records.map(\.id), [alpha.id])
        XCTAssertNil(model.failure)
    }

    func testReapplyingAFilterCancelledDuringMeaningSearchRestoresItsMatches() async throws {
        try await assertCancelledMeaningSearchCanRetry(overlapping: false)
    }

    func testReapplyingAFilterWhileItsCancelledMeaningSearchIsStillFinishing() async throws {
        try await assertCancelledMeaningSearchCanRetry(overlapping: true)
    }

    private func assertCancelledMeaningSearchCanRetry(overlapping: Bool) async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let report = record("Send the report on Friday.", app: "Notes")
        _ = try await store.recordDictation(report, admittedGeneration: policy.generation, at: Date())
        let fixture = DictationFixtureEmbedding()
        let vector = try await fixture.embed(report.text)
        _ = try await store.saveDictationEmbedding(
            .init(recordID: report.id, vector: vector), profile: fixture.profile)
        let gate = ControlledTestSleep()
        let index = DictationSemanticIndex(
            store: store, embedding: HeldQueryEmbedding(gate: gate, ignoresCancellation: overlapping))
        let model = DictationHistoryModel(store: store, semantic: index)
        await model.load()
        await index.backfill()
        let filter = DictationRecordFilter(query: "summary")
        let search = Task { await model.apply(filter) }
        addTeardownBlock {
            search.cancel()
            _ = await gate.resumeCall(at: 0)
            await search.value
        }
        let held = await gate.waitUntilCallCount(1)
        guard held else {
            XCTFail("the semantic query did not suspend")
            return
        }

        search.cancel()
        if overlapping {
            await model.apply(filter)
            XCTAssertEqual(model.records.map(\.id), [report.id], "the retry finishes while the old query is held")
            _ = await gate.resumeCall(at: 0)
            await search.value
        } else {
            await search.value
            await model.apply(filter)
        }

        XCTAssertEqual(model.records.map(\.id), [report.id])
        XCTAssertNil(model.failure)
    }

    private actor HeldQueryEmbedding: DictationTextEmbedding {
        nonisolated let profile = DictationFixtureEmbedding().profile
        let gate: ControlledTestSleep
        let ignoresCancellation: Bool
        private var held = false

        init(gate: ControlledTestSleep, ignoresCancellation: Bool) {
            self.gate = gate
            self.ignoresCancellation = ignoresCancellation
        }
        func isReady() async -> Bool { true }
        func embed(_ text: String) async throws -> [Float] {
            if text == "summary", !held {
                held = true
                if ignoresCancellation {
                    let operation = Task { try await gate.wait(for: .zero) }
                    try await operation.value
                } else {
                    try await gate.wait(for: .zero)
                }
            }
            return try await DictationFixtureEmbedding().embed(text)
        }
    }

    func testReapplyingACancelledFilterLoadsItsRowsAfterASave() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let alpha = fixedRecord("alpha", id: "00000000-0000-0000-0000-000000000051", time: 4_070_908_800)
        let beta = fixedRecord("beta", id: "00000000-0000-0000-0000-000000000052", time: 4_070_908_860)
        let newestBeta = fixedRecord("beta newest", id: "00000000-0000-0000-0000-000000000053", time: 4_070_908_920)
        let alphaSaved = try await store.recordDictation(
            alpha, admittedGeneration: policy.generation, at: Date())
        let betaSaved = try await store.recordDictation(
            beta, admittedGeneration: policy.generation, at: Date())
        XCTAssertEqual(alphaSaved, .saved)
        XCTAssertEqual(betaSaved, .saved)
        let gate = ControlledTestSleep()
        let reader = HeldHistoryRead(gate: gate, kind: .page("beta"), count: 1)
        let model = DictationHistoryModel(store: HeldHistoryStore(store: store, reader: reader))
        await model.load()
        await model.apply(.init(query: "alpha"))
        XCTAssertEqual(model.records.map(\.id), [alpha.id])
        let write = try XCTUnwrap(model.admit())
        let betaFilter = DictationRecordFilter(query: "beta")
        let changeFilter = Task { await model.apply(betaFilter) }
        addTeardownBlock {
            changeFilter.cancel()
            _ = await gate.resumeCall(at: 0)
            await changeFilter.value
        }
        let held = await gate.waitUntilCallCount(1)
        guard held else {
            XCTFail("the beta page did not suspend")
            return
        }

        let saved = await write(newestBeta)
        XCTAssertTrue(saved)
        let persisted = try await store.dictationRecords(
            matching: betaFilter, before: nil, limit: ListDictations.pageSize)
        XCTAssertEqual(persisted.map(\.id), [newestBeta.id, beta.id])
        changeFilter.cancel()
        _ = await gate.resumeCall(at: 0)
        await changeFilter.value
        await model.apply(betaFilter)

        XCTAssertEqual(model.records.map(\.id), [newestBeta.id, beta.id])
    }

    func testDeletingARowCapturedByALoadingPageDoesNotRestoreIt() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let deleted = record("beta deleted", app: "Notes")
        let survivor = record("beta kept", app: "Notes")
        _ = try await store.recordDictation(deleted, admittedGeneration: policy.generation, at: Date())
        _ = try await store.recordDictation(survivor, admittedGeneration: policy.generation, at: Date())
        let gate = ControlledTestSleep()
        let reader = HeldHistoryRead(gate: gate, kind: .page("beta"), count: 1)
        let model = DictationHistoryModel(store: HeldHistoryStore(store: store, reader: reader))
        await model.load()
        let changeFilter = Task { await model.apply(.init(query: "beta")) }
        let held = await gate.waitUntilCallCount(1)
        XCTAssertTrue(held)

        await model.delete(deleted.id)
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await changeFilter.value

        XCTAssertEqual(model.records.map(\.id), [survivor.id])
    }

    func testConcurrentSavesBothAppearInAnOpenSearch() async throws {
        let store = try DictationStore.inMemory()
        let gate = ControlledTestSleep()
        let reader = HeldHistoryRead(gate: gate, kind: .individual, count: 2)
        let model = DictationHistoryModel(store: HeldHistoryStore(store: store, reader: reader))
        await model.load()
        await model.update(isEnabled: true)
        await model.apply(.init(query: "report"))
        let write = try XCTUnwrap(model.admit())
        let first = fixedRecord("report first", id: "00000000-0000-0000-0000-000000000011", time: 4_070_908_800)
        let second = fixedRecord("report second", id: "00000000-0000-0000-0000-000000000012", time: 4_070_908_860)
        let firstSave = Task { await write(first) }
        let secondSave = Task { await write(second) }
        let held = await gate.waitUntilCallCount(2)
        XCTAssertTrue(held)

        let resumedFirst = await gate.resumeCall(at: 0)
        let resumedSecond = await gate.resumeCall(at: 1)
        XCTAssertTrue(resumedFirst)
        XCTAssertTrue(resumedSecond)
        _ = await (firstSave.value, secondSave.value)

        XCTAssertEqual(model.records.map(\.id), [second.id, first.id])
    }

    func testADeletedSaveCannotReturnFromAnInFlightLookup() async throws {
        let store = try DictationStore.inMemory()
        let gate = ControlledTestSleep()
        let reader = HeldHistoryRead(gate: gate, kind: .individual, count: 1)
        let model = DictationHistoryModel(store: HeldHistoryStore(store: store, reader: reader))
        await model.load()
        await model.update(isEnabled: true)
        await model.apply(.init(query: "report"))
        let write = try XCTUnwrap(model.admit())
        let report = record("report deleted", app: "Notes")
        let save = Task { await write(report) }
        let held = await gate.waitUntilCallCount(1)
        XCTAssertTrue(held)

        await model.delete(report.id)
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        _ = await save.value

        XCTAssertTrue(model.records.isEmpty)
        XCTAssertTrue(model.applications.isEmpty)
        let persisted = try await store.dictationRecords(ids: [report.id])
        XCTAssertTrue(persisted.isEmpty)
    }

    func testSavingWhileLoadingMoreKeepsTheDisplacedRowReachable() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        for minute in 0..<51 {
            let item = record("report \(minute)", app: "Notes", minutesAgo: minute)
            _ = try await store.recordDictation(item, admittedGeneration: policy.generation, at: Date())
        }
        let gate = ControlledTestSleep()
        let reader = HeldHistoryRead(gate: gate, kind: .page("report"), count: 0)
        let model = DictationHistoryModel(store: HeldHistoryStore(store: store, reader: reader))
        await model.load()
        await model.apply(.init(query: "report"))
        await reader.arm(1)
        let nextPage = Task { await model.loadMore() }
        let held = await gate.waitUntilCallCount(1)
        XCTAssertTrue(held)
        let write = try XCTUnwrap(model.admit())
        let new = fixedRecord("report new", id: "00000000-0000-0000-0000-000000000021", time: 4_070_908_860)

        _ = await write(new)
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await nextPage.value

        XCTAssertEqual(model.records.count, 52)
        XCTAssertEqual(Set(model.records.map(\.id)).count, 52)
        XCTAssertEqual(model.records.first?.id, new.id)
        XCTAssertFalse(model.hasMore)
    }

    func testLoadingMoreDuringASaveUsesTheCursorAfterItsInsertion() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        for minute in 0..<51 {
            let item = record("report \(minute)", app: "Notes", minutesAgo: minute)
            _ = try await store.recordDictation(item, admittedGeneration: policy.generation, at: Date())
        }
        let lookupGate = ControlledTestSleep()
        let pageGate = ControlledTestSleep()
        let lookup = HeldHistoryRead(gate: lookupGate, kind: .individual, count: 1)
        let page = HeldHistoryRead(gate: pageGate, kind: .page("report"), count: 0)
        let model = DictationHistoryModel(store: HeldHistoryStore(store: store, reader: lookup, reader2: page))
        await model.load()
        await model.apply(.init(query: "report"))
        await page.arm(1)
        let write = try XCTUnwrap(model.admit())
        let new = fixedRecord("report new", id: "00000000-0000-0000-0000-000000000022", time: 4_070_908_860)
        let save = Task { await write(new) }
        let lookupHeld = await lookupGate.waitUntilCallCount(1)
        XCTAssertTrue(lookupHeld)
        let nextPage = Task { await model.loadMore() }
        let pageHeld = await pageGate.waitUntilCallCount(1)
        XCTAssertTrue(pageHeld)

        let lookupResumed = await lookupGate.resumeCall(at: 0)
        XCTAssertTrue(lookupResumed)
        _ = await save.value
        let pageResumed = await pageGate.resumeCall(at: 0)
        XCTAssertTrue(pageResumed)
        await nextPage.value

        XCTAssertEqual(model.records.count, 52)
        XCTAssertEqual(Set(model.records.map(\.id)).count, 52)
        XCTAssertEqual(model.records.first?.id, new.id)
        XCTAssertFalse(model.hasMore)
    }

    func testConcurrentLoadMoreRequestsDoNotDuplicatePages() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        for minute in 0..<101 {
            let item = record("report \(minute)", app: "Notes", minutesAgo: minute)
            _ = try await store.recordDictation(item, admittedGeneration: policy.generation, at: Date())
        }
        let gate = ControlledTestSleep()
        let reader = HeldHistoryRead(gate: gate, kind: .page("report"), count: 0)
        let model = DictationHistoryModel(store: HeldHistoryStore(store: store, reader: reader))
        await model.load()
        await model.apply(.init(query: "report"))
        await reader.arm(2)
        let first = Task { await model.loadMore() }
        let second = Task { await model.loadMore() }
        let held = await gate.waitUntilCallCount(2)
        XCTAssertTrue(held)

        let firstResumed = await gate.resumeCall(at: 0)
        let secondResumed = await gate.resumeCall(at: 1)
        XCTAssertTrue(firstResumed)
        XCTAssertTrue(secondResumed)
        _ = await (first.value, second.value)

        XCTAssertEqual(model.records.count, 101)
        XCTAssertEqual(Set(model.records.map(\.id)).count, 101)
        XCTAssertFalse(model.hasMore)
    }

    func testDeliveryUpdateRemovesARowThatNoLongerMatchesTheFilter() async throws {
        let store = try DictationStore.inMemory()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: Date())
        let undelivered = record("report", app: "Notes").with(delivery: .notDelivered)
        _ = try await store.recordDictation(undelivered, admittedGeneration: policy.generation, at: Date())
        let model = DictationHistoryModel(store: store)
        await model.load()
        await model.apply(.init(query: "report", onlyNotDelivered: true))
        XCTAssertEqual(model.records.map(\.id), [undelivered.id])
        let write = try XCTUnwrap(model.admit())

        let saved = await write(undelivered.with(delivery: .verified))

        XCTAssertTrue(saved)
        XCTAssertTrue(model.records.isEmpty)
        let persisted = try await store.dictationRecords(ids: [undelivered.id])
        XCTAssertEqual(persisted.first?.delivery, .verified)
    }

    func testDeliveryUpdateKeepsAVisibleMeaningMatchWithoutReindexing() async throws {
        let embedding = SwitchableEmbedding()
        let (model, index, store) = try await model(embedding: embedding)
        let report = record("Send the report on Friday.", app: "Notes").with(delivery: .notDelivered)
        _ = try await store.recordDictation(report, admittedGeneration: model.policy.generation, at: Date())
        await index.index(report)
        await model.apply(.init(query: "summary"))
        XCTAssertEqual(model.records.map(\.id), [report.id])
        await embedding.setReady(false)
        let write = try XCTUnwrap(model.admit())

        let saved = await write(report.with(delivery: .verified))

        XCTAssertTrue(saved)
        XCTAssertEqual(model.records.map(\.id), [report.id])
        XCTAssertEqual(model.records.first?.delivery, .verified)
    }

    func testDeliveryUpdateRemovesAMeaningMatchExcludedByOtherFilters() async throws {
        let embedding = SwitchableEmbedding()
        let (model, index, store) = try await model(embedding: embedding)
        let report = record("Send the report on Friday.", app: "Notes").with(delivery: .notDelivered)
        _ = try await store.recordDictation(report, admittedGeneration: model.policy.generation, at: Date())
        await index.index(report)
        await model.apply(.init(query: "summary", onlyNotDelivered: true))
        XCTAssertEqual(model.records.map(\.id), [report.id])
        await embedding.setReady(false)
        let write = try XCTUnwrap(model.admit())

        let saved = await write(report.with(delivery: .verified))

        XCTAssertTrue(saved)
        XCTAssertTrue(model.records.isEmpty)
    }

    private actor SwitchableEmbedding: DictationTextEmbedding {
        nonisolated let profile = "switchable-fixture"
        private var ready = true

        func setReady(_ value: Bool) { ready = value }
        func isReady() -> Bool { ready }
        func embed(_ text: String) async throws -> [Float] {
            try await DictationFixtureEmbedding().embed(text)
        }
    }

    private actor HeldHistoryRead {
        enum Kind { case page(String), individual }
        let gate: ControlledTestSleep
        let kind: Kind
        var remaining: Int

        init(gate: ControlledTestSleep, kind: Kind, count: Int) {
            self.gate = gate
            self.kind = kind
            self.remaining = count
        }

        func arm(_ count: Int) { remaining = count }

        func holdIfNeeded(_ filter: DictationRecordFilter) async throws {
            let matches: Bool
            switch kind {
            case .page(let query): matches = filter.query == query && filter.recordID == nil
            case .individual: matches = filter.recordID != nil
            }
            guard matches, remaining > 0 else { return }
            remaining -= 1
            try await gate.wait(for: .zero)
        }
    }

    private struct HeldHistoryStore: DictationHistoryStore {
        let store: DictationStore
        let reader: HeldHistoryRead
        let reader2: HeldHistoryRead?

        init(store: DictationStore, reader: HeldHistoryRead, reader2: HeldHistoryRead? = nil) {
            self.store = store
            self.reader = reader
            self.reader2 = reader2
        }

        func dictationHistoryPolicy() async throws -> DictationHistoryPolicy { try await store.dictationHistoryPolicy() }
        func setDictationHistoryPolicy(
            isEnabled: Bool, keepsOriginal: Bool, retentionDays: Int, exposesToAgents: Bool, at now: Date
        ) async throws -> DictationHistoryPolicy {
            try await store.setDictationHistoryPolicy(
                isEnabled: isEnabled, keepsOriginal: keepsOriginal, retentionDays: retentionDays,
                exposesToAgents: exposesToAgents, at: now)
        }
        func recordDictation(
            _ record: DictationRecord, admittedGeneration: Int, at now: Date
        ) async throws -> DictationRecordOutcome {
            try await store.recordDictation(record, admittedGeneration: admittedGeneration, at: now)
        }
        func dictationRecords(matching filter: DictationRecordFilter, before cursor: DictationRecord?, limit: Int)
            async throws -> [DictationRecord] {
            let snapshot = try await store.dictationRecords(matching: filter, before: cursor, limit: limit)
            try await reader.holdIfNeeded(filter)
            try await reader2?.holdIfNeeded(filter)
            return snapshot
        }
        func dictationApplications() async throws -> [String] { try await store.dictationApplications() }
        func deleteDictationRecord(_ id: DictationRecordID) async throws -> Bool {
            try await store.deleteDictationRecord(id)
        }
        func deleteAllDictationRecords() async throws -> Int { try await store.deleteAllDictationRecords() }
        func purgeExpiredDictationRecords(at now: Date) async throws -> Int {
            try await store.purgeExpiredDictationRecords(at: now)
        }
        func dictationRecordsForAgents(matching filter: DictationRecordFilter, offset: Int, limit: Int)
            async throws -> DictationAgentRead<DictationRecordPage> {
            try await store.dictationRecordsForAgents(matching: filter, offset: offset, limit: limit)
        }
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

    func testDeletingOneDropsAnInFlightMeaningResult() async throws {
        let (model, gate, report, survivor, store) = try await modelWithHeldMeaningResult()
        let search = Task { await model.apply(.init(query: "summary")) }
        let held = await gate.waitUntilCallCount(1)
        XCTAssertTrue(held)

        await model.delete(report.id)
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await search.value

        XCTAssertEqual(model.records.map(\.id), [survivor.id])
        let persisted = try await store.dictationRecords(ids: [report.id])
        XCTAssertTrue(persisted.isEmpty)
    }

    func testDeletingAllDropsAnInFlightMeaningResult() async throws {
        let (model, gate, report, _, store) = try await modelWithHeldMeaningResult()
        let search = Task { await model.apply(.init(query: "summary")) }
        let held = await gate.waitUntilCallCount(1)
        XCTAssertTrue(held)

        await model.deleteAll()
        let resumed = await gate.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        await search.value

        XCTAssertTrue(model.records.isEmpty)
        XCTAssertEqual(model.filter, .all)
        let persisted = try await store.dictationRecords(ids: [report.id])
        XCTAssertTrue(persisted.isEmpty)
    }

    private func modelWithHeldMeaningResult() async throws
        -> (DictationHistoryModel, ControlledTestSleep, DictationRecord, DictationRecord, DictationStore) {
        let store = try DictationStore.inMemory()
        let now = Date()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: now)
        let report = record("Send the report on Friday.", app: "Slack")
        let survivor = record("A summary for Friday.", app: "Notes")
        _ = try await store.recordDictation(report, admittedGeneration: policy.generation, at: now)
        _ = try await store.recordDictation(survivor, admittedGeneration: policy.generation, at: now)
        let embedding = DictationFixtureEmbedding()
        let vector = try await embedding.embed(report.text)
        _ = try await store.saveDictationEmbedding(.init(recordID: report.id, vector: vector), profile: embedding.profile)
        let survivorVector = try await embedding.embed(survivor.text)
        _ = try await store.saveDictationEmbedding(
            .init(recordID: survivor.id, vector: survivorVector), profile: embedding.profile)
        let gate = ControlledTestSleep()
        let index = DictationSemanticIndex(store: HeldMeaningStore(store: store, gate: gate), embedding: embedding)
        let model = DictationHistoryModel(store: store, semantic: index)
        await model.load()
        return (model, gate, report, survivor, store)
    }

    private struct HeldMeaningStore: DictationEmbeddingStore {
        let store: DictationStore
        let gate: ControlledTestSleep
        let holdSingleOnly: Bool
        let skipBackfill: Bool
        let holdLibraryRead: Bool

        init(
            store: DictationStore, gate: ControlledTestSleep, holdSingleOnly: Bool = false,
            skipBackfill: Bool = false, holdLibraryRead: Bool = false
        ) {
            self.store = store
            self.gate = gate
            self.holdSingleOnly = holdSingleOnly
            self.skipBackfill = skipBackfill
            self.holdLibraryRead = holdLibraryRead
        }

        func saveDictationEmbedding(_ embedding: DictationEmbedding, profile: String) async throws -> Bool {
            try await store.saveDictationEmbedding(embedding, profile: profile)
        }

        func dictationEmbeddings(profile: String, matching filter: DictationRecordFilter) async throws
            -> [DictationEmbedding] {
            let snapshot = try await store.dictationEmbeddings(profile: profile, matching: filter)
            if holdLibraryRead && (!holdSingleOnly || snapshot.count == 1) { try await gate.wait(for: .zero) }
            return snapshot
        }

        func dictationEmbeddingIDs(profile: String, matching filter: DictationRecordFilter) async throws
            -> Set<DictationRecordID> {
            try await store.dictationEmbeddingIDs(profile: profile, matching: filter)
        }

        func dictationRecordsMissingEmbedding(
            profile: String, before cursor: DictationRecord?, limit: Int
        ) async throws -> [DictationRecord] {
            if skipBackfill { return [] }
            return try await store.dictationRecordsMissingEmbedding(profile: profile, before: cursor, limit: limit)
        }

        func dictationRecords(ids: [DictationRecordID]) async throws -> [DictationRecord] {
            let snapshot = try await store.dictationRecords(ids: ids)
            if !holdLibraryRead && (!holdSingleOnly || ids.count == 1) { try await gate.wait(for: .zero) }
            return snapshot
        }
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

    func testBackfillReachesOlderDictationPastOneHundredUnembeddableRows() async throws {
        let store = try DictationStore.inMemory()
        let now = Date()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, at: now)
        let old = record("Send the report on Friday.", app: "Slack", minutesAgo: 101)
        let oldOutcome = try await store.recordDictation(old, admittedGeneration: policy.generation, at: now)
        XCTAssertEqual(oldOutcome, .saved)
        for minute in 0..<100 {
            let broken = record("broken \(minute)", app: "Notes", minutesAgo: minute)
            let outcome = try await store.recordDictation(broken, admittedGeneration: policy.generation, at: now)
            XCTAssertEqual(outcome, .saved)
        }
        let index = DictationSemanticIndex(store: store, embedding: FailsOn(word: "broken"))

        await index.backfill()

        let vectors = try await store.dictationEmbeddings(profile: FailsOn(word: "broken").profile, matching: .all)
        XCTAssertEqual(vectors.map(\.recordID), [old.id])

        let older = record("Another report.", app: "Slack", minutesAgo: 102)
        let olderOutcome = try await store.recordDictation(older, admittedGeneration: policy.generation, at: now)
        XCTAssertEqual(olderOutcome, .saved)
        await index.backfill()
        let afterRetry = try await store.dictationEmbeddings(profile: FailsOn(word: "broken").profile, matching: .all)
        XCTAssertEqual(Set(afterRetry.map(\.recordID)), [old.id, older.id])
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

    private func waitForVectors(_ ids: Set<DictationRecordID>, in store: DictationStore) async throws {
        // Joining the launch backfill is not a barrier for a writer's detached indexing.
        let indexed = await TestPolling.untilAsync {
            let actual = try? await store.dictationEmbeddingIDs(
                profile: DictationFixtureEmbedding().profile, matching: .all)
            return actual == ids
        }
        XCTAssertTrue(indexed, "Every saved fixture must be indexed automatically before testing ranking")
        let actual = try await store.dictationEmbeddingIDs(
            profile: DictationFixtureEmbedding().profile, matching: .all)
        XCTAssertEqual(actual, ids)
    }

    private func record(_ text: String, app: String, minutesAgo: Int = 0) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: Date().addingTimeInterval(Double(-minutesAgo * 60)), duration: 1,
            text: text, originalText: nil, mode: .literal, language: nil, engine: "parakeet", applicationName: app,
            applicationBundleID: nil, delivery: .verified)
    }

    private func fixedRecord(_ text: String, id: String, time: TimeInterval) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(rawValue: UUID(uuidString: id)!), createdAt: Date(timeIntervalSince1970: time),
            duration: 1, text: text, originalText: nil, mode: .literal, language: nil, engine: "parakeet",
            applicationName: "Notes", applicationBundleID: nil, delivery: .verified)
    }
}
