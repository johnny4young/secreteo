import DictationKit
import Foundation
import SpeechCore
import Testing

@Suite
struct DictationHybridSearchTests {
    private let first = DictationRecordID()
    private let second = DictationRecordID()
    private let third = DictationRecordID()

    @Test
    func onlyCloseEnoughDictationsRankByMeaningBestFirst() {
        let query: [Float] = [1, 0]
        let candidates = [
            DictationEmbedding(recordID: first, vector: [0.92, 0.392]),
            DictationEmbedding(recordID: second, vector: [0.98, 0.199]),
            DictationEmbedding(recordID: third, vector: [0.6, 0.8]),
            DictationEmbedding(recordID: DictationRecordID(), vector: [1, 0, 0])
        ]
        let ranked = DictationHybridSearch.semanticRanking(query: query, candidates: candidates)
        #expect(ranked == [second, first], "below the floor or another dimension never ranks")
    }

    @Test
    func meaningMatchesSkipWhatTheWordSearchListed() {
        let added = DictationHybridSearch.meaningOnly([second, third, first], after: [first])
        #expect(added == [second, third])
    }

    @Test
    func wordMatchesDoNotUseUpTheMeaningLimit() {
        let words = (0..<DictationHybridSearch.semanticLimit).map { _ in DictationRecordID() }
        let paraphrase = DictationRecordID()
        let candidates = words.map { DictationEmbedding(recordID: $0, vector: [1, 0]) }
            + [DictationEmbedding(recordID: paraphrase, vector: [0.95, 0.312])]
        let ranked = DictationHybridSearch.semanticRanking(query: [1, 0], candidates: candidates)
        #expect(DictationHybridSearch.meaningOnly(ranked, after: words) == [paraphrase])
    }

    @Test
    func meaningMatchesStopAtTheLimit() {
        let semantic = (0...DictationHybridSearch.semanticLimit).map { _ in DictationRecordID() }
        let added = DictationHybridSearch.meaningOnly(semantic, after: [])
        #expect(added == Array(semantic.prefix(DictationHybridSearch.semanticLimit)))
    }

    @Test
    func punctuationAloneHasNothingToMean() {
        #expect(!DictationHybridSearch.isSearchable("?! --"))
        #expect(!DictationHybridSearch.isSearchable(""))
        #expect(DictationHybridSearch.isSearchable("informe"))
        #expect(DictationHybridSearch.isSearchable("2026"))
    }

    @Test
    func aQueryVectorNeedsSearchableWordsAndAReadyModelThatWorks() async {
        let ready = RecordingEmbedding(ready: true, fails: false)
        #expect(await DictationMeaningQuery.make(for: "report", using: nil) == nil)
        #expect(await DictationMeaningQuery.make(for: "report", using: RecordingEmbedding(ready: false, fails: false)) == nil)
        #expect(await DictationMeaningQuery.make(for: "report", using: RecordingEmbedding(ready: true, fails: true)) == nil)
        #expect(await DictationMeaningQuery.make(for: "?! …", using: ready) == nil)
        #expect(await ready.texts.isEmpty, "punctuation never reaches the model")
        #expect(await DictationMeaningQuery.make(for: "report", using: ready) == .init(profile: "recording", vector: [1, 0]))
    }

    @Test
    func theModelReadsNoMoreThanAWordSearchDoes() async {
        let embedding = RecordingEmbedding(ready: true, fails: false)
        _ = await DictationMeaningQuery.make(for: String(repeating: "palabra ", count: 1_000), using: embedding)
        #expect(await embedding.texts.map(\.count) == [DictationRecordFilter.maximumQueryLength])
    }
}

private actor RecordingEmbedding: DictationTextEmbedding {
    nonisolated let profile = "recording"
    let ready: Bool
    let fails: Bool
    private(set) var texts: [String] = []

    init(ready: Bool, fails: Bool) {
        self.ready = ready
        self.fails = fails
    }

    func isReady() -> Bool { ready }

    func embed(_ text: String) throws -> [Float] {
        texts.append(text)
        if fails { throw CancellationError() }
        return [1, 0]
    }
}
