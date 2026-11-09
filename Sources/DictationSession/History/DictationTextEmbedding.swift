import Foundation
import NaturalLanguage

/// Turns a dictation's text into a sentence vector, on this Mac only.
protocol DictationTextEmbedding: Sendable {
    /// Names the model and pooling, so vectors from another model are never compared.
    var profile: String { get }
    /// False until the model's assets are on this Mac; search never downloads them.
    func isReady() async -> Bool
    func embed(_ text: String) async throws -> [Float]
}

/// Apple's Latin-script contextual embedding, which puts English and Spanish in one
/// space. Mean-pooled and L2-normalized, so cosine similarity is a dot product.
actor SystemSentenceEmbedding: DictationTextEmbedding {
    enum Failure: Error { case unavailable }

    nonisolated let profile: String
    private let embedding: NLContextualEmbedding
    private var loaded = false

    init?() {
        guard let embedding = NLContextualEmbedding(script: .latin) else { return nil }
        self.embedding = embedding
        profile = "\(embedding.modelIdentifier)-r\(embedding.revision)-d\(embedding.dimension)-token-mean-pooling-l2-v1"
    }

    func isReady() -> Bool { embedding.hasAvailableAssets }

    func embed(_ text: String) throws -> [Float] {
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

/// A disposable launch's stand-in: words that mean the same in English and Spanish
/// share one axis, so a UI test can search by meaning without a model.
struct DictationFixtureEmbedding: DictationTextEmbedding {
    private static let concepts: [Set<String>] = [
        ["report", "informe", "reporte"], ["friday", "viernes"], ["notes", "notas", "note", "nota"],
        ["delete", "borres", "borrar", "erase"], ["send", "envía", "enviar"]
    ]

    var profile: String { "fixture-concepts-v1" }

    func isReady() async -> Bool { true }

    func embed(_ text: String) async throws -> [Float] {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        var vector = Self.concepts.map { concept in Float(words.filter(concept.contains).count) }
        // An axis for everything else keeps unrelated text from looking like a match.
        vector.append(Float(words.filter { word in !Self.concepts.contains { $0.contains(word) } }.count) * 0.2)
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? vector.map { $0 / norm } : vector
    }
}
