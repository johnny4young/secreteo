import Foundation
import GRDB
import SpeechCore
import Synchronization

public enum DictationStoreError: Error, Equatable {
    /// A newer Secreteo wrote this database. This build neither migrates nor writes it.
    case newerSchema
    /// The database has not been created by the app yet.
    case notCreated
    /// The app has not upgraded the database to this build's schema yet.
    case needsUpgrade
    case invalidDictationRecord(String)
    case invalidPersistedUUID(table: String, column: String, value: String)
    case invalidPersistedValue(table: String, column: String, value: String)
}

/// Secreteo's own database for dictation history, search and statistics.
public final class DictationStore: Sendable {
    public static let fileName = "Dictations.sqlite"

    let database: any DatabaseWriter
    /// Dictations deleted one by one in this run, so a retry still on screen cannot save them again.
    /// Changed only when a write commits; never on disk.
    let deletedRecordIDs = Mutex<Set<DictationRecordID>>([])

    /// In the app's Application Support folder, which the cask's `zap` removes.
    public static func defaultURL(bundleIdentifier: String) -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Creates or upgrades the database. A database from a newer build is refused untouched.
    public convenience init(databaseURL: URL) throws {
        try self.init(databaseURL: databaseURL, migrator: DictationSchema.migrator())
    }

    convenience init(databaseURL: URL, migrator: DatabaseMigrator) throws {
        try Self.createPrivateFile(at: databaseURL)
        // Read-only first: opening a writer would already change a newer database.
        if try Self.readOnly(at: databaseURL, { try migrator.hasBeenSuperseded($0) }) == true {
            throw DictationStoreError.newerSchema
        }
        let pool = try DatabasePool(path: databaseURL.path, configuration: Self.configuration(readonly: false))
        try self.init(writer: pool, migrator: migrator)
    }

    /// Opens an existing database without migrating it, for another process such as the MCP server.
    public static func openForReading(at databaseURL: URL) throws -> DictationStore {
        try openForReading(at: databaseURL, migrator: DictationSchema.migrator())
    }

    static func openForReading(at databaseURL: URL, migrator: DatabaseMigrator) throws -> DictationStore {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { throw DictationStoreError.notCreated }
        let pool = try DatabasePool(path: databaseURL.path, configuration: configuration(readonly: true))
        try pool.read { database in
            if try migrator.hasBeenSuperseded(database) { throw DictationStoreError.newerSchema }
            guard try !migrator.appliedIdentifiers(database).isEmpty else { throw DictationStoreError.notCreated }
            guard try migrator.hasCompletedMigrations(database) else { throw DictationStoreError.needsUpgrade }
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

    /// Moves the write-ahead log into the database and truncates it, so erased text no longer
    /// sits in the log. Waits for readers up to the busy timeout and says whether it finished.
    @discardableResult
    func checkpoint() async -> Bool {
        let result = try? await database.writeWithoutTransaction { try $0.checkpoint(.truncate) }
        return result?.walFrameCount == 0
    }

    static func configuration(readonly: Bool) -> Configuration {
        var configuration = Configuration()
        configuration.readonly = readonly
        configuration.label = "DictationStore"
        // Another process may be reading; wait for it instead of failing at once.
        configuration.busyMode = .timeout(2)
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
        if manager.fileExists(atPath: url.path) {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else if !manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    private static func readOnly<T>(at url: URL, _ read: (Database) throws -> T) throws -> T? {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { return nil }
        let probe = try DatabaseQueue(path: url.path, configuration: configuration(readonly: true))
        defer { try? probe.close() }
        return try probe.read(read)
    }
}
