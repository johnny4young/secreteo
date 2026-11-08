import Foundation
import NaturalLanguage

/// Apple's Latin-script contextual embedding, which puts English and Spanish in one
/// space. Mean-pooled and L2-normalized, so cosine similarity is a dot product.
actor SentenceEmbedder {
    enum EmbedderError: Error, LocalizedError {
        case unsupported
        case assetsUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "this OS has no Latin-script contextual embedding model"
            case .assetsUnavailable:
                return "the embedding assets are not installed yet (network needed once)"
            }
        }
    }

    private let embedding: NLContextualEmbedding
    private var loaded = false

    init() throws {
        guard let embedding = NLContextualEmbedding(script: .latin) else {
            throw EmbedderError.unsupported
        }
        self.embedding = embedding
    }

    /// Identity of the model and pooling behind a set of vectors. Reading it
    /// does not load or download model assets.
    var profileFingerprint: String {
        "\(embedding.modelIdentifier)-r\(embedding.revision)-d\(embedding.dimension)-token-mean-pooling-l2-v1"
    }

    /// Loads the model, requesting the OS's assets only when allowed.
    func prepare(allowAssetDownload: Bool = true) async throws {
        if !embedding.hasAvailableAssets {
            guard allowAssetDownload else { throw EmbedderError.assetsUnavailable }
            let result = try await embedding.requestAssets()
            guard result == .available else { throw EmbedderError.assetsUnavailable }
        }
        if !loaded {
            try embedding.load()
            loaded = true
        }
    }

    func embed(_ texts: [String]) throws -> [[Float]] {
        try texts.map { text in
            let result = try embedding.embeddingResult(for: text, language: nil)
            var sum = [Double](repeating: 0, count: embedding.dimension)
            var count = 0
            result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                for index in 0..<min(vector.count, sum.count) {
                    sum[index] += vector[index]
                }
                count += 1
                return true
            }
            guard count > 0 else {
                return [Float](repeating: 0, count: embedding.dimension)
            }
            var mean = sum.map { Float($0 / Double(count)) }
            let norm = sqrt(mean.reduce(0) { $0 + $1 * $1 })
            if norm > 0 {
                for index in 0..<mean.count { mean[index] /= norm }
            }
            return mean
        }
    }
}
