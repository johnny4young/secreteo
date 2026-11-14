import Foundation
import NaturalLanguage

/// Turns a dictation's text into a sentence vector, on this Mac only.
public protocol DictationTextEmbedding: Sendable {
    /// Names the model and pooling, so vectors from another model are never compared.
    var profile: String { get }
    /// False until the model's assets are on this Mac; search never downloads them.
    func isReady() async -> Bool
    func embed(_ text: String) async throws -> [Float]
}

/// Apple's Latin-script contextual embedding, which puts English and Spanish in one
/// space. Mean-pooled and L2-normalized, so cosine similarity is a dot product.
public actor SystemSentenceEmbedding: DictationTextEmbedding {
    public enum Failure: Error { case unavailable }

    nonisolated public let profile: String
    private let embedding: NLContextualEmbedding
    private var loaded = false

    public init?() {
        guard let embedding = NLContextualEmbedding(script: .latin) else { return nil }
        self.embedding = embedding
        profile = "\(embedding.modelIdentifier)-r\(embedding.revision)-d\(embedding.dimension)-token-mean-pooling-l2-v1"
    }

    public func isReady() -> Bool { embedding.hasAvailableAssets }

    public func embed(_ text: String) throws -> [Float] {
        guard embedding.hasAvailableAssets else { throw Failure.unavailable }
        if !loaded {
            try embedding.load()
            loaded = true
        }
        let result = try embedding.embeddingResult(for: text, language: nil)
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for index in 0..<min(vector.count, sum.count) { sum[index] += vector[index] }
            count += 1
            return true
        }
        guard count > 0 else { throw Failure.unavailable }
        let mean = sum.map { Float($0 / Double(count)) }
        let norm = mean.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { throw Failure.unavailable }
        return mean.map { $0 / norm }
    }
}
