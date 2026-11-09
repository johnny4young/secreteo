import Foundation
import SpeechCore

/// Search by meaning fused with the word search, as measured on the public search
/// corpus: plain cosine with a 0.9 floor, and reciprocal rank fusion. Centering on the
/// library's mean measured slightly better but is unstable while a library is small.
public enum DictationHybridSearch {
    public static let similarityThreshold: Float = 0.9
    public static let semanticLimit = 12
    public static let resultLimit = 100
    static let fusionK = 60.0

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
        }.prefix(semanticLimit).map(\.id)
    }

    /// Reciprocal rank fusion of the two rankings; ties fall back to the identifier.
    public static func fuse(
        lexical: [DictationRecordID], semantic: [DictationRecordID], limit: Int = resultLimit
    ) -> [DictationRecordID] {
        var scores: [DictationRecordID: Double] = [:]
        for ranking in [lexical, semantic] {
            for (rank, id) in ranking.enumerated() {
                scores[id, default: 0] += 1 / (fusionK + Double(rank))
            }
        }
        let ranked = scores.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue.uuidString < $1.key.rawValue.uuidString
        }
        return ranked.prefix(limit).map(\.key)
    }
}
