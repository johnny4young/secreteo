import DictationKit
import Foundation
import GRDB
import SpeechCore

extension DictationStore {
    /// Saves or replaces a dictation's vector. False when the dictation is gone, so a
    /// vector computed after a delete is never kept.
    public func saveDictationEmbedding(_ embedding: DictationEmbedding, profile: String) async throws -> Bool {
        guard embedding.isValid, (1...DictationEmbedding.maximumProfileLength).contains(profile.count) else {
            throw DictationStoreError.invalidDictationRecord("invalid embedding")
        }
        let blob = Self.encode(embedding.vector)
        return try await database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO dictationEmbedding (recordID, profile, vector)
                    SELECT id, ?, ? FROM dictationRecord WHERE id = ?
                    ON CONFLICT(recordID) DO UPDATE SET profile = excluded.profile, vector = excluded.vector
                    """,
                arguments: [profile, blob, embedding.recordID.rawValue.uuidString])
            return database.changesCount > 0
        }
    }

    /// Vectors made by `profile` for the dictations the filter's application and delivery
    /// allow. Its words are ignored: search by meaning ranks what words would not match.
    public func dictationEmbeddings(
        profile: String, matching filter: DictationRecordFilter = .all
    ) async throws -> [DictationEmbedding] {
        var conditions = ["dictationEmbedding.profile = ?"]
        var arguments: StatementArguments = [profile]
        if let application = filter.applicationName {
            conditions.append("dictationRecord.applicationName = ?")
            arguments += [application]
        }
        if filter.onlyNotDelivered {
            conditions.append("dictationRecord.delivery = ?")
            arguments += [DictationRecordDelivery.notDelivered.rawValue]
        }
        let sql = """
            SELECT dictationEmbedding.recordID, dictationEmbedding.vector
            FROM dictationEmbedding JOIN dictationRecord ON dictationRecord.id = dictationEmbedding.recordID
            WHERE \(conditions.joined(separator: " AND "))
            ORDER BY dictationRecord.createdAt DESC, dictationRecord.id DESC
            """
        return try await database.read { [arguments] database in
            try Row.fetchAll(database, sql: sql, arguments: arguments).map { row in
                let rawID: String = row["recordID"]
                guard let uuid = UUID(uuidString: rawID) else {
                    throw DictationStoreError.invalidPersistedUUID(
                        table: "dictationEmbedding", column: "recordID", value: rawID)
                }
                return DictationEmbedding(
                    recordID: DictationRecordID(rawValue: uuid), vector: Self.decode(row["vector"]))
            }
        }
    }

    /// The newest dictations with no vector from `profile`, to compute in the background.
    public func dictationRecordsMissingEmbedding(profile: String, limit: Int) async throws -> [DictationRecord] {
        guard (1...Self.maximumDictationPageSize).contains(limit) else { return [] }
        let sql = Self.dictationColumns + """

            WHERE NOT EXISTS (
                SELECT 1 FROM dictationEmbedding
                WHERE dictationEmbedding.recordID = dictationRecord.id AND dictationEmbedding.profile = ?)
            ORDER BY createdAt DESC, id DESC LIMIT ?
            """
        return try await database.read { database in
            try Row.fetchAll(database, sql: sql, arguments: [profile, limit]).map(Self.dictationRecord(from:))
        }
    }

    /// These dictations in the order given; any no longer saved are left out.
    public func dictationRecords(ids: [DictationRecordID]) async throws -> [DictationRecord] {
        guard !ids.isEmpty, ids.count <= Self.maximumDictationPageSize else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let sql = Self.dictationColumns + "\nWHERE id IN (\(placeholders))"
        let arguments = StatementArguments(ids.map(\.rawValue.uuidString))
        let found = try await database.read { database in
            try Row.fetchAll(database, sql: sql, arguments: arguments).map(Self.dictationRecord(from:))
        }
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    static func encode(_ vector: [Float]) -> Data {
        var data = Data(capacity: vector.count * 4)
        for value in vector {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func decode(_ data: Data) -> [Float] {
        stride(from: 0, to: data.count - data.count % 4, by: 4).map { offset in
            let bits = data[data.startIndex + offset..<data.startIndex + offset + 4]
                .enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
            return Float(bitPattern: bits)
        }
    }
}
