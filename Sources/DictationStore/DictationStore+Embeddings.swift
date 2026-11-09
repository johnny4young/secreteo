import DictationKit
import Foundation
import GRDB
import SpeechCore

extension DictationStore {
    /// Saves or replaces a dictation's vector. False when the dictation is gone, so a
    /// vector computed after a delete is never kept.
    public func saveDictationEmbedding(_ embedding: DictationEmbedding, profile: String) async throws -> Bool {
        // SQLite's length() counts code points, so the guard does too.
        guard embedding.isValid,
              (1...DictationEmbedding.maximumProfileLength).contains(profile.unicodeScalars.count) else {
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

    /// Vectors made by `profile` for the dictations the filter allows. Its words are
    /// ignored: search by meaning ranks what words would not match.
    public func dictationEmbeddings(
        profile: String, matching filter: DictationRecordFilter = .all
    ) async throws -> [DictationEmbedding] {
        var wordless = filter
        wordless.query = ""
        guard let (filters, filterArguments) = Self.dictationFilterConditions(wordless) else { return [] }
        let conditions = ["dictationEmbedding.profile = ?"] + filters
        let arguments: StatementArguments = [profile] + filterArguments
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
        let found = try await database.read { database in
            // SQLite bounds the arguments of one statement, so long lists go in pages.
            try stride(from: 0, to: ids.count, by: Self.maximumDictationPageSize).flatMap { start in
                let page = ids[start..<min(start + Self.maximumDictationPageSize, ids.count)]
                let placeholders = Array(repeating: "?", count: page.count).joined(separator: ", ")
                return try Row.fetchAll(
                    database, sql: Self.dictationColumns + "\nWHERE id IN (\(placeholders))",
                    arguments: StatementArguments(page.map(\.rawValue.uuidString))
                ).map(Self.dictationRecord(from:))
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// Little-endian 32-bit floats, the layout of every Mac Secreteo runs on.
    static func encode(_ vector: [Float]) -> Data {
        vector.map(\.bitPattern.littleEndian).withUnsafeBytes { Data($0) }
    }

    static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { bytes in
            (0..<data.count / 4).map { index in
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
            }
        }
    }
}
