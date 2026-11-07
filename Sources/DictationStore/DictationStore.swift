import Foundation
import GRDB

public enum DictationStoreError: Error, Equatable {
    /// A newer Secreteo wrote this database. This build neither migrates nor writes it.
    case newerSchema
    /// The database has not been created by the app yet.
    case notCreated
    case invalidDictationRecord(String)
    case invalidPersistedUUID(table: String, column: String, value: String)
    case invalidPersistedValue(table: String, column: String, value: String)
}

/// Secreteo's own database for dictation history, search and statistics.
public final class DictationStore: Sendable {
    public static let fileName = "Dictations.sqlite"

    let database: any DatabaseWriter

    /// In the app's Application Support folder, which the cask's `zap` removes.
    public static func defaultURL(bundleIdentifier: String) -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Creates or upgrades the database. A database from a newer build is refused untouched.
    public convenience init(databaseURL: URL) throws {
        try Self.createPrivateFile(at: databaseURL)
        let pool = try DatabasePool(path: databaseURL.path, configuration: Self.configuration(readonly: false))
        try self.init(writer: pool, migrator: DictationSchema.migrator())
    }

    /// Opens an existing database without migrating it, for another process such as the MCP server.
    public static func openForReading(at databaseURL: URL) throws -> DictationStore {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { throw DictationStoreError.notCreated }
        let pool = try DatabasePool(path: databaseURL.path, configuration: configuration(readonly: true))
        let migrator = DictationSchema.migrator()
        try pool.read { database in
            if try migrator.hasBeenSuperseded(database) { throw DictationStoreError.newerSchema }
            guard try migrator.hasCompletedMigrations(database) else { throw DictationStoreError.notCreated }
        }
        return DictationStore(reader: pool)
    }

    /// Ephemeral store for tests.
    public static func inMemory() throws -> DictationStore {
        try DictationStore(writer: DatabaseQueue(configuration: configuration(readonly: false)))
    }

    init(writer: any DatabaseWriter, migrator: DatabaseMigrator = DictationSchema.migrator()) throws {
        if try writer.read({ try migrator.hasBeenSuperseded($0) }) { throw DictationStoreError.newerSchema }
        try migrator.migrate(writer)
        database = writer
    }

    private init(reader: DatabasePool) {
        database = reader
    }

    /// Moves the write-ahead log into the database and truncates it, so erased text
    /// no longer sits in the log. Readers can hold it back; the next call retries.
    func checkpoint() {
        database.writeWithoutTransaction { database in
            _ = try? database.checkpoint(.truncate)
        }
    }

    static func configuration(readonly: Bool) -> Configuration {
        var configuration = Configuration()
        configuration.readonly = readonly
        configuration.label = "DictationStore"
        configuration.prepareDatabase { database in
            // Deleted text is overwritten with zeros instead of left in free pages.
            try database.execute(sql: "PRAGMA secure_delete = ON")
        }
        return configuration
    }

    /// Owner-only before SQLite opens it, so the log and shared-memory files inherit the mode.
    private static func createPrivateFile(at url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
    }
}
