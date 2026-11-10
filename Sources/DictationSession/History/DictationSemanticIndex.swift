import DictationKit
import DictationStore
import Foundation
import SpeechCore

/// What search by meaning needs from the history database.
protocol DictationEmbeddingStore: Sendable {
    func saveDictationEmbedding(_ embedding: DictationEmbedding, profile: String) async throws -> Bool
    func dictationEmbeddings(
        profile: String, matching filter: DictationRecordFilter
    ) async throws -> [DictationEmbedding]
    func dictationEmbeddingIDs(
        profile: String, matching filter: DictationRecordFilter
    ) async throws -> Set<DictationRecordID>
    func dictationRecordsMissingEmbedding(
        profile: String, before cursor: DictationRecord?, limit: Int
    ) async throws -> [DictationRecord]
    func dictationRecords(ids: [DictationRecordID]) async throws -> [DictationRecord]
}

extension DictationStore: DictationEmbeddingStore {}

/// Keeps a vector for every saved dictation and ranks them by meaning. The library's
/// vectors stay in memory between searches and are reread after any change.
actor DictationSemanticIndex {
    static let backfillBatch = 50

    private let store: any DictationEmbeddingStore
    private let embedding: any DictationTextEmbedding
    private var library: [DictationEmbedding]?
    /// Bumped on every change, so a read that started before one is never cached.
    private var generation = 0
    private var backfilling: Task<Void, Never>?
    /// Dictations the model could not embed this launch, so a backfill does not retry them forever.
    private var unembeddable: Set<DictationRecordID> = []
    private var onChange: (@Sendable () async -> Void)?

    init(store: any DictationEmbeddingStore, embedding: any DictationTextEmbedding) {
        self.store = store
        self.embedding = embedding
    }

    /// Called after new vectors are saved, so a search on screen can add what they find.
    func setChangeHandler(_ handler: @escaping @Sendable () async -> Void) {
        onChange = handler
    }

    /// Dictations close in meaning to the query among those the filter allows; nil when
    /// the query has nothing to mean or the model is not on this Mac.
    func ranking(for query: String, matching filter: DictationRecordFilter) async throws -> [DictationRecordID]? {
        guard DictationHybridSearch.isSearchable(query), await embedding.isReady() else { return nil }
        var candidates = try await currentLibrary()
        guard !candidates.isEmpty else { return [] }
        let vector = try await embedding.embed(query)
        if filter.applicationName != nil || filter.onlyNotDelivered || filter.recordID != nil {
            let allowed = try await store.dictationEmbeddingIDs(profile: embedding.profile, matching: filter)
            candidates = candidates.filter { allowed.contains($0.recordID) }
        }
        return DictationHybridSearch.semanticRanking(query: vector, candidates: candidates)
    }

    func records(_ ids: [DictationRecordID]) async throws -> [DictationRecord] {
        try await store.dictationRecords(ids: ids)
    }

    /// A store that refuses the vector, because the dictation is gone, keeps nothing.
    func index(_ record: DictationRecord) async {
        guard await embedding.isReady(), let vector = try? await embedding.embed(record.text),
              (try? await store.saveDictationEmbedding(
                .init(recordID: record.id, vector: vector), profile: embedding.profile)) == true
        else { return }
        invalidate()
        await onChange?()
    }

    /// Computes vectors for dictations saved before this model, newest first. A second
    /// call waits for the one already running.
    func backfill() async {
        if let backfilling { return await backfilling.value }
        let task = Task { await runBackfill() }
        backfilling = task
        await task.value
        backfilling = nil
    }

    func invalidate() {
        generation += 1
        library = nil
    }

    private func runBackfill() async {
        guard await embedding.isReady() else { return }
        var savedAny = false
        var cursor: DictationRecord?
        while true {
            guard let batch = try? await store.dictationRecordsMissingEmbedding(
                profile: embedding.profile, before: cursor, limit: Self.backfillBatch), let last = batch.last
            else { break }
            cursor = last
            for record in batch where !unembeddable.contains(record.id) {
                guard let vector = try? await embedding.embed(record.text),
                      (try? await store.saveDictationEmbedding(
                        .init(recordID: record.id, vector: vector), profile: embedding.profile)) == true
                else {
                    unembeddable.insert(record.id)
                    continue
                }
                savedAny = true
            }
            invalidate()
        }
        if savedAny { await onChange?() }
    }

    private func currentLibrary() async throws -> [DictationEmbedding] {
        if let library { return library }
        let started = generation
        let all = try await store.dictationEmbeddings(profile: embedding.profile, matching: .all)
        if generation == started { library = all }
        return all
    }
}
