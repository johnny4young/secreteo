import DictationKit
import Foundation

/// A disposable launch's stand-in: synonyms share one axis, and a text points along its
/// most frequent concept (the earlier one on a tie), so a UI test can search by meaning
/// without a model. Texts with no known concept all point along one other axis.
struct DictationFixtureEmbedding: DictationTextEmbedding {
    private static let concepts: [Set<String>] = [
        ["report", "summary", "informe", "reporte"], ["friday", "viernes"], ["notes", "notas", "note", "nota"],
        ["delete", "erase", "borres", "borrar", "elimina", "elimines"], ["send", "envía", "enviar"]
    ]

    var profile: String { "fixture-concepts-v1" }

    func isReady() async -> Bool { true }

    func embed(_ text: String) async throws -> [Float] {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        let counts = Self.concepts.map { concept in words.filter(concept.contains).count }
        var vector = [Float](repeating: 0, count: Self.concepts.count + 1)
        if let best = counts.max(), best > 0, let axis = counts.firstIndex(of: best) {
            vector[axis] = 1
        } else {
            vector[Self.concepts.count] = 1
        }
        return vector
    }
}
