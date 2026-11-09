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
    func punctuationAloneHasNothingToMean() {
        #expect(!DictationHybridSearch.isSearchable("?! --"))
        #expect(!DictationHybridSearch.isSearchable(""))
        #expect(DictationHybridSearch.isSearchable("informe"))
        #expect(DictationHybridSearch.isSearchable("2026"))
    }
}
