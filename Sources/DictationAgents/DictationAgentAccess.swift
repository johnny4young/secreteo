import DictationKit
import DictationStore
import Foundation
import SpeechCore

/// Reads for local agents such as the MCP server. Consent is checked by the
/// store in the same read as the rows, on every call.
public protocol DictationAgentStore: Sendable {
    func dictationRecordsForAgents(
        matching filter: DictationRecordFilter, offset: Int, limit: Int
    ) async throws -> DictationAgentRead<DictationRecordPage>
    func dictationRecordForAgents(_ id: DictationRecordID) async throws -> DictationAgentRead<DictationRecord?>
    func searchDictationsForAgents(
        matching filter: DictationRecordFilter, meaning: DictationMeaningQuery?, offset: Int, limit: Int
    ) async throws -> DictationAgentRead<DictationSearchPage>
    func dictationHistoryPolicy() async throws -> DictationHistoryPolicy
}

extension DictationStore: DictationAgentStore {}

public struct ReadDictationsForAgents {
    public struct Request: Sendable {
        public let filter: DictationRecordFilter
        public let offset: Int
        public let limit: Int

        public init(filter: DictationRecordFilter, offset: Int, limit: Int) {
            self.filter = filter
            self.offset = offset
            self.limit = limit
        }
    }

    private let store: any DictationAgentStore

    public init(store: any DictationAgentStore) {
        self.store = store
    }

    public func execute(_ request: Request) async throws -> DictationAgentRead<DictationRecordPage> {
        try await store.dictationRecordsForAgents(
            matching: request.filter, offset: request.offset, limit: request.limit)
    }
}

/// Words first, then meaning, as the history window searches. Without the model on this
/// Mac it matches words only.
public struct SearchDictationsForAgents {
    private let store: any DictationAgentStore
    private let embedding: (any DictationTextEmbedding)?

    public init(store: any DictationAgentStore, embedding: (any DictationTextEmbedding)?) {
        self.store = store
        self.embedding = embedding
    }

    public func execute(
        _ request: ReadDictationsForAgents.Request
    ) async throws -> DictationAgentRead<DictationSearchPage> {
        // The model never sees a query the user has not shared; the read below checks again.
        guard try await store.dictationHistoryPolicy().agentsCanRead else { return .notAllowed }
        let meaning = await DictationMeaningQuery.make(for: request.filter.query, using: embedding)
        return try await store.searchDictationsForAgents(
            matching: request.filter, meaning: meaning, offset: request.offset, limit: request.limit)
    }
}

public struct ReadDictationForAgents {
    private let store: any DictationAgentStore

    public init(store: any DictationAgentStore) {
        self.store = store
    }

    public func execute(_ request: DictationRecordID) async throws -> DictationAgentRead<DictationRecord?> {
        try await store.dictationRecordForAgents(request)
    }
}
