import Foundation
import GRDB
import Testing

@testable import DictationStore

@Suite
struct DictationStoreSchemaTests {
    @Test
    func v1CreatesEveryTableWithEveryConsentOff() async throws {
        let store = try DictationStore.inMemory()
        try await store.database.read { database in
            #expect(try String.fetchAll(database, sql: "SELECT identifier FROM grdb_migrations") == ["v1"])
            let history = try #require(try Row.fetchOne(database, sql: "SELECT * FROM dictationHistoryPolicy"))
            #expect(history["isEnabled"] == false)
            #expect(history["keepsOriginal"] == false)
            #expect(history["exposesToAgents"] == false)
            #expect(history["retentionDays"] == 30)
            #expect(try Bool.fetchOne(database, sql: "SELECT isEnabled FROM dictationStatsPolicy") == false)
            #expect(try Set(database.columns(in: "dictationRecord").map(\.name)) == [
                "id", "createdAt", "durationMs", "text", "originalText", "mode", "language",
                "engine", "applicationName", "applicationBundleID", "delivery"
            ])
            for table in ["dictationRecordSearch", "dictationStatsDay", "dictationStatsCounted"] {
                #expect(try database.tableExists(table), "\(table)")
            }
        }
    }

    @Test
    func anUpgradeKeepsTheRowsAndRunsOnlyTheNewMigration() async throws {
        try await withScratch { url in
            let first = try DictationStore(databaseURL: url)
            try await insertRecord("Una nota de prueba.", into: first)
            try first.database.close()

            let upgraded = try DictationStore(databaseURL: url, migrator: Self.migrator(addingV2: true))
            #expect(try await strings(upgraded, "SELECT identifier FROM grdb_migrations") == ["v1", "v2"])
            #expect(try await strings(upgraded, "SELECT text FROM dictationRecord") == ["Una nota de prueba."])
            #expect(try await strings(upgraded, "SELECT name FROM pragma_table_info('dictationRecord')")
                .contains("testColumn"))
        }
    }

    @Test
    func aFailedUpgradeLeavesThePreviousVersionWhole() async throws {
        try await withScratch { url in
            let first = try DictationStore(databaseURL: url)
            try await insertRecord("Sigue aquí.", into: first)
            try first.database.close()

            var failing = DictationSchema.migrator()
            failing.registerMigration("v2") { database in
                try database.execute(sql: "DELETE FROM dictationRecord")
                throw DatabaseError(resultCode: .SQLITE_ABORT, message: "synthetic failure")
            }
            #expect(throws: DatabaseError.self) { try DictationStore(databaseURL: url, migrator: failing) }

            let reopened = try DictationStore(databaseURL: url)
            #expect(try await strings(reopened, "SELECT identifier FROM grdb_migrations") == ["v1"])
            #expect(try await strings(reopened, "SELECT text FROM dictationRecord") == ["Sigue aquí."])
        }
    }

    @Test
    func anOlderBuildRefusesADatabaseFromANewerOneAndLeavesItUntouched() async throws {
        try await withScratch { url in
            let newer = try DictationStore(databaseURL: url, migrator: Self.migrator(addingV2: true))
            try await insertRecord("Escrito por una versión nueva.", into: newer)
            try newer.database.close()
            let before = try Data(contentsOf: url)

            #expect(throws: DictationStoreError.newerSchema) { try DictationStore(databaseURL: url) }
            #expect(try Data(contentsOf: url) == before, "the app refuses without writing")
            #expect(throws: DictationStoreError.newerSchema) { try DictationStore.openForReading(at: url) }
            #expect(try Data(contentsOf: url) == before, "a reader never writes")

            let again = try DictationStore(databaseURL: url, migrator: Self.migrator(addingV2: true))
            #expect(try await strings(again, "SELECT identifier FROM grdb_migrations") == ["v1", "v2"])
            #expect(try await strings(again, "SELECT text FROM dictationRecord") == ["Escrito por una versión nueva."])
        }
    }

    @Test
    func anotherProcessReadsWhileTheAppHoldsTheStoreButCannotWrite() async throws {
        try await withScratch { url in
            #expect(throws: DictationStoreError.notCreated) { try DictationStore.openForReading(at: url) }
            let app = try DictationStore(databaseURL: url)
            try await insertRecord("Visible para el lector.", into: app)

            let reader = try DictationStore.openForReading(at: url)
            #expect(try await strings(reader, "SELECT text FROM dictationRecord") == ["Visible para el lector."])
            await #expect(throws: DatabaseError.self) {
                try await reader.database.write { try $0.execute(sql: "DELETE FROM dictationRecord") }
            }
            #expect(throws: DictationStoreError.needsUpgrade) {
                try DictationStore.openForReading(at: url, migrator: Self.migrator(addingV2: true))
            }
        }
    }

    @Test
    func agentAccessCannotBeStoredWhileTheHistoryIsOff() async throws {
        let store = try DictationStore.inMemory()
        await #expect(throws: DatabaseError.self) {
            try await store.database.write {
                try $0.execute(sql: "UPDATE dictationHistoryPolicy SET isEnabled = 0, exposesToAgents = 1")
            }
        }
        try await store.database.write {
            try $0.execute(sql: "UPDATE dictationHistoryPolicy SET isEnabled = 1, exposesToAgents = 1")
        }
    }

    @Test
    func anExistingFileIsMadeOwnerOnly() async throws {
        try await withScratch { url in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o644])
            _ = try DictationStore(databaseURL: url)
            #expect(try permissions(of: url) == 0o600)
        }
    }

    @Test
    func theFilesAreOwnerOnlyAndErasedTextLeavesNoBytesBehind() async throws {
        try await withScratch { url in
            let store = try DictationStore(databaseURL: url)
            let token = "zebracornio\(UUID().uuidString.prefix(8).lowercased())"
            try await insertRecord("Esta nota se queda.", into: store)
            try await insertRecord("Recuerda \(token) mañana.", into: store)
            #expect(store.checkpoint())
            #expect(try bytes(near: url).contains(Data(token.utf8)), "the probe must reach the file first")

            try await store.database.write {
                try $0.execute(sql: "DELETE FROM dictationRecord WHERE text LIKE ?", arguments: ["%\(token)%"])
            }
            #expect(store.checkpoint())

            #expect(!(try bytes(near: url).contains(Data(token.utf8))))
            #expect(try permissions(of: url) == 0o600)
            #expect(try permissions(of: url.deletingLastPathComponent()) == 0o700)
            let secureDelete = try await store.database.read { try Int.fetchOne($0, sql: "PRAGMA secure_delete") }
            #expect(secureDelete == 1)
        }
    }

    @Test
    func theDefaultLocationIsTheAppsOwnFolder() {
        let url = DictationStore.defaultURL(bundleIdentifier: "com.johnny4young.secreteo")
        #expect(url.lastPathComponent == "Dictations.sqlite")
        #expect(url.deletingLastPathComponent().lastPathComponent == "com.johnny4young.secreteo")
        #expect(url.path.contains("/Library/Application Support/"))
    }

    // MARK: Helpers

    private static func migrator(addingV2: Bool) -> DatabaseMigrator {
        var migrator = DictationSchema.migrator()
        if addingV2 {
            migrator.registerMigration("v2") { database in
                try database.alter(table: "dictationRecord") { $0.add(column: "testColumn", .text) }
            }
        }
        return migrator
    }

    private func insertRecord(_ text: String, into store: DictationStore) async throws {
        try await store.database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO dictationRecord (id, createdAt, durationMs, text, mode, engine, delivery)
                    VALUES (?, ?, 1000, ?, 'literal', 'parakeet', 'verified')
                    """,
                arguments: [UUID().uuidString, Date(timeIntervalSince1970: 1_800_000_000), text])
        }
    }

    private func strings(_ store: DictationStore, _ sql: String) async throws -> [String] {
        try await store.database.read { try String.fetchAll($0, sql: sql) }
    }

    private func bytes(near url: URL) throws -> Data {
        try ["", "-wal", "-shm"].reduce(into: Data()) { data, suffix in
            let file = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: file.path) { data += try Data(contentsOf: file) }
        }
    }

    private func permissions(of url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func withScratch(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root.appendingPathComponent("private", isDirectory: true).appendingPathComponent("Dictations.sqlite"))
    }
}
