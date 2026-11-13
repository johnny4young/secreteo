import Foundation
import GRDB
import DictationKit
import SpeechCore

extension DictationStore {
    /// A page for a local agent. Agent consent is read in the same transaction
    /// as the rows, so a revoked consent never returns content.
    public func dictationRecordsForAgents(
        matching filter: DictationRecordFilter, offset: Int, limit: Int
    ) async throws -> DictationAgentRead<DictationRecordPage> {
        let start = max(0, offset)
        let size = min(max(1, limit), Self.maximumDictationPageSize)
        let filtered = Self.dictationFilterConditions(filter)
        return try await database.read { database in
            guard try Self.dictationHistoryPolicy(in: database).agentsCanRead else { return .notAllowed }
            guard let (conditions, arguments) = filtered else {
                return .allowed(DictationRecordPage(total: 0, offset: start, records: []))
            }
            let filters = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let total = try Int.fetchOne(
                database, sql: "SELECT COUNT(*) FROM dictationRecord \(filters)", arguments: arguments) ?? 0
            var pageArguments = arguments
            pageArguments += [size, start]
            let records = try Row.fetchAll(
                database,
                sql: Self.dictationColumns + "\n\(filters)\nORDER BY createdAt DESC, id DESC LIMIT ? OFFSET ?",
                arguments: pageArguments
            ).map(Self.dictationRecord(from:))
            return .allowed(DictationRecordPage(total: total, offset: start, records: records))
        }
    }

    public func dictationRecordForAgents(
        _ id: DictationRecordID
    ) async throws -> DictationAgentRead<DictationRecord?> {
        try await database.read { database in
            guard try Self.dictationHistoryPolicy(in: database).agentsCanRead else { return .notAllowed }
            let row = try Row.fetchOne(
                database, sql: Self.dictationColumns + "\nWHERE id = ?", arguments: [id.rawValue.uuidString])
            return .allowed(try row.map(Self.dictationRecord(from:)))
        }
    }

    /// Word matches, then the dictations close in meaning that hold none of the words, as
    /// the history window lists them. Consent, both rankings and the rows come from one read.
    public func searchDictationsForAgents(
        matching filter: DictationRecordFilter, meaning: DictationMeaningQuery?, offset: Int, limit: Int
    ) async throws -> DictationAgentRead<DictationSearchPage> {
        let start = max(0, offset)
        let size = min(max(1, limit), Self.maximumDictationPageSize)
        let filtered = Self.dictationFilterConditions(filter)
        return try await database.read { database in
            guard try Self.dictationHistoryPolicy(in: database).agentsCanRead else { return .notAllowed }
            var wordIDs: [DictationRecordID] = []
            if let (conditions, arguments) = filtered {
                let filters = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
                wordIDs = try String.fetchAll(
                    database, sql: "SELECT id FROM dictationRecord \(filters) ORDER BY createdAt DESC, id DESC",
                    arguments: arguments
                ).compactMap { UUID(uuidString: $0).map(DictationRecordID.init(rawValue:)) }
            }
            var meaningIDs: [DictationRecordID] = []
            if let meaning, DictationHybridSearch.isSearchable(filter.query) {
                let candidates = try Self.dictationEmbeddings(in: database, profile: meaning.profile, matching: filter)
                let ranking = DictationHybridSearch.semanticRanking(query: meaning.vector, candidates: candidates)
                meaningIDs = DictationHybridSearch.meaningOnly(ranking, after: wordIDs)
            }
            let all = wordIDs + meaningIDs
            let shown = start < all.count ? Array(all[start..<min(start + size, all.count)]) : []
            let records = try Self.dictationRecords(in: database, ids: shown)
            return .allowed(DictationSearchPage(
                page: DictationRecordPage(total: all.count, offset: start, records: records),
                meaningMatches: meaningIDs.count))
        }
    }
}
