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
        let meaning = DictationHybridSearch.isSearchable(filter.query) ? meaning : nil
        return try await database.read { database in
            guard try Self.dictationHistoryPolicy(in: database).agentsCanRead else { return .notAllowed }
            var wordTotal = 0
            var records: [DictationRecord] = []
            if let (conditions, arguments) = filtered {
                let filters = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
                wordTotal = try Int.fetchOne(
                    database, sql: "SELECT COUNT(*) FROM dictationRecord \(filters)", arguments: arguments) ?? 0
                if start < wordTotal {
                    var pageArguments = arguments
                    pageArguments += [size, start]
                    records = try Row.fetchAll(
                        database,
                        sql: Self.dictationColumns + "\n\(filters)\nORDER BY createdAt DESC, id DESC LIMIT ? OFFSET ?",
                        arguments: pageArguments
                    ).map(Self.dictationRecord(from:))
                }
            }
            var meaningIDs: [DictationRecordID] = []
            if let meaning {
                let candidates = try Self.dictationEmbeddings(in: database, profile: meaning.profile, matching: filter)
                let ranking = DictationHybridSearch.semanticRanking(query: meaning.vector, candidates: candidates)
                meaningIDs = try Self.meaningOnly(in: database, ranking: ranking, wordFilter: filtered)
            }
            let end = start > Int.max - size ? Int.max : start + size
            let meaningStart = max(start, wordTotal) - wordTotal
            let meaningEnd = min(end - wordTotal, meaningIDs.count)
            if meaningStart < meaningEnd {
                records += try Self.dictationRecords(in: database, ids: Array(meaningIDs[meaningStart..<meaningEnd]))
            }
            return .allowed(DictationSearchPage(
                page: DictationRecordPage(total: wordTotal + meaningIDs.count, offset: start, records: records),
                meaningMatches: meaningIDs.count))
        }
    }

    /// The best-ranked dictations that the word filter does not match, checking the ranking
    /// in pages until enough are found instead of listing every word match.
    private static func meaningOnly(
        in database: Database, ranking: [DictationRecordID],
        wordFilter: (conditions: [String], arguments: StatementArguments)?
    ) throws -> [DictationRecordID] {
        guard let wordFilter else { return Array(ranking.prefix(DictationHybridSearch.semanticLimit)) }
        var found: [DictationRecordID] = []
        for start in stride(from: 0, to: ranking.count, by: maximumDictationPageSize) {
            let page = Array(ranking[start..<min(start + maximumDictationPageSize, ranking.count)])
            let placeholders = Array(repeating: "?", count: page.count).joined(separator: ", ")
            let conditions = wordFilter.conditions + ["id IN (\(placeholders))"]
            var arguments = wordFilter.arguments
            arguments += StatementArguments(page.map(\.rawValue.uuidString))
            let words = try String.fetchAll(
                database, sql: "SELECT id FROM dictationRecord WHERE " + conditions.joined(separator: " AND "),
                arguments: arguments
            ).compactMap { UUID(uuidString: $0).map(DictationRecordID.init(rawValue:)) }
            found += DictationHybridSearch.meaningOnly(page, after: words)
            if found.count >= DictationHybridSearch.semanticLimit { break }
        }
        return Array(found.prefix(DictationHybridSearch.semanticLimit))
    }
}
