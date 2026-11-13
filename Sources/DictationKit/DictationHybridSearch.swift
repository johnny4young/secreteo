import Foundation
import SpeechCore

/// Search by meaning after the word search: dictations holding the typed words come
/// first, in their usual order, then those close in meaning that hold none of them.
/// Plain cosine with a 0.9 floor; on the public search corpus this order measures the
/// same as rank fusion, and it never puts a paraphrase above a word match.
public enum DictationHybridSearch {
    public static let similarityThreshold: Float = 0.9
    public static let semanticLimit = 12

    /// Whether the query has anything to mean; punctuation alone matches nothing, as with words.
    public static func isSearchable(_ query: String) -> Bool {
        query.contains { $0.isLetter || $0.isNumber }
    }

    /// The dictations whose normalized vector is close enough to the query's, best first.
    public static func semanticRanking(query: [Float], candidates: [DictationEmbedding]) -> [DictationRecordID] {
        var scored: [(id: DictationRecordID, similarity: Float)] = []
        for candidate in candidates where candidate.vector.count == query.count {
            var dot: Float = 0
            for index in query.indices { dot += candidate.vector[index] * query[index] }
            if dot >= similarityThreshold { scored.append((candidate.recordID, dot)) }
        }
        return scored.sorted {
            $0.similarity != $1.similarity
                ? $0.similarity > $1.similarity : $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }.map(\.id)
    }

    /// The best meaning matches the word search has not already listed, in their order.
    public static func meaningOnly(
        _ semantic: [DictationRecordID], after shown: some Sequence<DictationRecordID>
    ) -> [DictationRecordID] {
        let listed = Set(shown)
        return Array(semantic.lazy.filter { !listed.contains($0) }.prefix(semanticLimit))
    }
}

/// A search's vector and the model that made it; only vectors from the same profile are compared.
public struct DictationMeaningQuery: Equatable, Sendable {
    public let profile: String
    public let vector: [Float]

    public init(profile: String, vector: [Float]) {
        self.profile = profile
        self.vector = vector
    }

    /// Nil when the words have nothing to mean, the model is not on this Mac, or it fails:
    /// the search then matches words only, and nothing is downloaded.
    public static func make(for query: String, using embedding: (any DictationTextEmbedding)?) async -> Self? {
        guard let embedding, DictationHybridSearch.isSearchable(query), await embedding.isReady(),
              let vector = try? await embedding.embed(query)
        else { return nil }
        return Self(profile: embedding.profile, vector: vector)
    }
}

/// Word matches newest first, then up to `DictationHybridSearch.semanticLimit` dictations
/// close in meaning that hold none of the words. `page.total` counts both.
public struct DictationSearchPage: Equatable, Sendable {
    public let page: DictationRecordPage
    /// How many of `page.total` match by meaning only; they come after every word match.
    public let meaningMatches: Int

    public init(page: DictationRecordPage, meaningMatches: Int) {
        self.page = page
        self.meaningMatches = meaningMatches
    }

    /// Whether the record at this position of the page matched by meaning, not words.
    public func matchesByMeaning(at index: Int) -> Bool {
        page.offset + index >= page.total - meaningMatches
    }
}
