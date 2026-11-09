import DictationKit
import DictationStore
import Foundation
import SpeechCore

/// What search by meaning needs from the history database.
protocol DictationEmbeddingStore: Sendable {
    func saveDictationEmbedding(_ embedding: DictationEmbedding, profile: String) async throws -> Bool
    func dictationEmbeddings(profile: String, matching filter: DictationRecordFilter) async throws -> [DictationEmbedding]
    func dictationRecordsMissingEmbedding(profile: String, limit: Int) async throws -> [DictationRecord]
    func dictationRecords(ids: [DictationRecordID]) async throws -> [DictationRecord]
}

extension DictationStore: DictationEmbeddingStore {}

/// Keeps a vector for every saved dictation and ranks them by meaning. The library's
/// centered vectors stay in memory between searches and are rebuilt after any change.
actor DictationSemanticIndex {
    private struct Library {
        let mean: [Float]
        let centered: [DictationEmbedding]
    }

    static let backfillBatch = 50

    private let store: any DictationEmbeddingStore
    private let embedding: any DictationTextEmbedding
    private var library: Library?
    private var isBackfilling = false

    init(store: any DictationEmbeddingStore, embedding: any DictationTextEmbedding) {
        self.store = store
        self.embedding = embedding
    }

    /// Dictations close in meaning to the query among those the filter's application and
    /// delivery allow; nil when the model is not on this Mac.
    func ranking(for query: String, matching filter: DictationRecordFilter) async throws -> [DictationRecordID]? {
        guard await embedding.isReady() else { return nil }
        let library = try await currentLibrary()
        guard !library.centered.isEmpty else { return [] }
        let vector = DictationHybridSearch.centered(try await embedding.embed(query), mean: library.mean)
        var candidates = library.centered
        if filter.applicationName != nil || filter.onlyNotDelivered {
            let allowed = Set(try await store.dictationEmbeddings(profile: embedding.profile, matching: filter)
                .map(\.recordID))
            candidates = candidates.filter { allowed.contains($0.recordID) }
        }
        return DictationHybridSearch.semanticRanking(query: vector, candidates: candidates)
    }

    func records(_ ids: [DictationRecordID]) async throws -> [DictationRecord] {
        try await store.dictationRecords(ids: ids)
    }

    /// A store that refuses the vector, because the dictation is gone, keeps nothing.
    func index(_ record: DictationRecord) async {
        guard await embedding.isReady(), let vector = try? await embedding.embed(record.text) else { return }
        _ = try? await store.saveDictationEmbedding(.init(recordID: record.id, vector: vector), profile: embedding.profile)
        library = nil
    }

    /// Computes vectors for dictations saved before this model, newest first.
    func backfill() async {
        guard !isBackfilling, await embedding.isReady() else { return }
        isBackfilling = true
        defer { isBackfilling = false }
        while let missing = try? await store.dictationRecordsMissingEmbedding(
            profile: embedding.profile, limit: Self.backfillBatch), !missing.isEmpty {
            var saved = 0
            for record in missing {
                guard let vector = try? await embedding.embed(record.text),
                      (try? await store.saveDictationEmbedding(
                        .init(recordID: record.id, vector: vector), profile: embedding.profile)) == true
                else { continue }
                saved += 1
            }
            library = nil
            // A batch that saved nothing would come back unchanged forever.
            guard saved > 0 else { return }
        }
    }

    func invalidate() {
        library = nil
    }

    private func currentLibrary() async throws -> Library {
        if let library { return library }
        let all = try await store.dictationEmbeddings(profile: embedding.profile, matching: .all)
        let mean = DictationHybridSearch.mean(all.map(\.vector))
        let built = Library(
            mean: mean,
            centered: all.map { .init(recordID: $0.recordID, vector: DictationHybridSearch.centered($0.vector, mean: mean)) })
        library = built
        return built
    }
}
