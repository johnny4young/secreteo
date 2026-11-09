import Foundation
import SpeechCore

/// Search by meaning fused with the word search, as measured on the public search
/// corpus: vectors centered on the library's mean, a 0.5 similarity floor, and
/// reciprocal rank fusion. Every exact match stays first; paraphrases join them.
public enum DictationHybridSearch {
    public static let similarityThreshold: Float = 0.5
    public static let semanticLimit = 12
    public static let resultLimit = 100
    static let fusionK = 60.0

    public static func mean(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors where vector.count == first.count {
            for index in vector.indices { sum[index] += vector[index] }
        }
        return sum.map { $0 / Float(vectors.count) }
    }

    /// Removes the direction every vector shares, so similarity reflects what differs.
    public static func centered(_ vector: [Float], mean: [Float]) -> [Float] {
        guard vector.count == mean.count else { return vector }
        let shifted = zip(vector, mean).map { $0 - $1 }
        let norm = shifted.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? shifted.map { $0 / norm } : shifted
    }

    /// The dictations whose centered vector is close enough to the centered query, best first.
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
        return scores.keys.sorted {
            scores[$0] != scores[$1] ? scores[$0] ?? 0 > scores[$1] ?? 0 : $0.rawValue.uuidString < $1.rawValue.uuidString
        }.prefix(limit).map { $0 }
    }
}
