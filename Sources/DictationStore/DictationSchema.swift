import DictationKit
import GRDB

/// Forward-only migrations. v1 is the final shape of history, search and statistics,
/// with every consent off. Each later version adds a migration and never edits one.
enum DictationSchema {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try createHistory(in: database)
            try createSearch(in: database)
            try createStats(in: database)
        }
        return migrator
    }

    /// One consent row and the saved dictations. No audio, window titles or surrounding text.
    private static func createHistory(in database: Database) throws {
        try database.create(table: "dictationHistoryPolicy") { table in
            table.primaryKey("id", .integer).check(sql: "id = 1")
            table.column("isEnabled", .boolean).notNull().check(sql: "isEnabled IN (0, 1)")
            table.column("keepsOriginal", .boolean).notNull().check(sql: "keepsOriginal IN (0, 1)")
            table.column("retentionDays", .integer).notNull().check(sql: "retentionDays IN (7, 30, 90)")
            table.column("generation", .integer).notNull().check(sql: "generation >= 0")
            // Read by the MCP server, which runs in another process.
            table.column("exposesToAgents", .boolean).notNull().check(sql: "exposesToAgents IN (0, 1)")
            // Agents never read a history that is off, whatever wrote the row.
            table.check(sql: "isEnabled = 1 OR exposesToAgents = 0")
        }
        try database.execute(sql: """
            INSERT INTO dictationHistoryPolicy
                (id, isEnabled, keepsOriginal, retentionDays, generation, exposesToAgents)
            VALUES (1, 0, 0, 30, 0, 0)
            """)
        let label = DictationRecord.maximumLabelLength
        try database.create(table: "dictationRecord") { table in
            table.primaryKey("id", .text).check(sql: "length(id) = 36")
            table.column("createdAt", .datetime).notNull()
            table.column("durationMs", .integer).notNull().check(sql: "durationMs >= 0")
            table.column("text", .text).notNull().check(
                sql: "length(trim(text)) > 0 AND length(text) <= \(DictationRecord.maximumTextLength)")
            table.column("originalText", .text).check(
                sql: "originalText IS NULL OR length(originalText) <= \(DictationRecord.maximumTextLength)")
            table.column("mode", .text).notNull().check(sql: "mode IN ('literal', 'clean', 'polish')")
            table.column("language", .text).check(sql: "language IS NULL OR language IN ('es', 'en')")
            table.column("engine", .text).notNull().check(sql: "length(engine) BETWEEN 1 AND \(label)")
            table.column("applicationName", .text).check(
                sql: "applicationName IS NULL OR length(applicationName) <= \(label)")
            table.column("applicationBundleID", .text).check(
                sql: "applicationBundleID IS NULL OR length(applicationBundleID) <= \(label)")
            table.column("delivery", .text).notNull().check(
                sql: "delivery IN ('verified', 'dispatched', 'not-delivered')")
        }
        try database.create(
            index: "dictationRecord_on_createdAt_id", on: "dictationRecord", columns: ["createdAt", "id"])
    }

    /// Kept in step with every insert, update and delete by GRDB's triggers. Secure delete
    /// removes a deleted dictation's words from the index instead of leaving them until a merge.
    private static func createSearch(in database: Database) throws {
        try database.create(virtualTable: "dictationRecordSearch", using: FTS5()) { table in
            table.synchronize(withTable: "dictationRecord")
            table.tokenizer = .unicode61()
            table.column("text")
            table.column("originalText")
        }
        try database.execute(sql: """
            INSERT INTO dictationRecordSearch (dictationRecordSearch, rank) VALUES ('secure-delete', 1)
            """)
    }

    /// Their own consent, daily totals per app, and the recently counted dictations
    /// that keep a retry from counting twice. Never any text.
    private static func createStats(in database: Database) throws {
        try database.create(table: "dictationStatsPolicy") { table in
            table.primaryKey("id", .integer).check(sql: "id = 1")
            table.column("isEnabled", .boolean).notNull().check(sql: "isEnabled IN (0, 1)")
        }
        try database.execute(sql: "INSERT INTO dictationStatsPolicy (id, isEnabled) VALUES (1, 0)")
        try database.create(table: "dictationStatsDay") { table in
            table.column("day", .text).notNull().check(sql: "length(day) = 10")
            table.column("applicationName", .text).notNull()
                .check(sql: "length(applicationName) <= \(DictationRecord.maximumLabelLength)")
            table.column("dictations", .integer).notNull().check(sql: "dictations >= 0")
            table.column("words", .integer).notNull().check(sql: "words >= 0")
            table.column("spokenMs", .integer).notNull().check(sql: "spokenMs >= 0")
            table.column("notDelivered", .integer).notNull().check(sql: "notDelivered >= 0")
            table.primaryKey(["day", "applicationName"])
        }
        try database.create(table: "dictationStatsCounted") { table in
            table.primaryKey("dictationID", .text).check(sql: "length(dictationID) = 36")
            table.column("day", .text).notNull().check(sql: "length(day) = 10")
            table.column("applicationName", .text).notNull()
                .check(sql: "length(applicationName) <= \(DictationRecord.maximumLabelLength)")
            table.column("delivered", .boolean).notNull().check(sql: "delivered IN (0, 1)")
            table.column("countedAt", .datetime).notNull()
        }
    }
}
