import DictationKit
import DictationStore
import Foundation
import SpeechCore
import XCTest

@testable import DictationAgents

final class DictationMCPCommandTests: XCTestCase {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAClientSetUpBeforeTheAppRanStartsReadingOnceTheHistoryExists() async throws {
        let url = try scratch().appendingPathComponent(DictationStore.fileName)
        let tool = try XCTUnwrap(DictationToolbox.tools(reader: .opening(url, embedding: nil)).first { $0.name == "list_dictations" })

        do {
            _ = try await tool.handler(Data("{}".utf8))
            XCTFail("no database yet")
        } catch {
            XCTAssertEqual(error as? DictationMCPError, .notCreated)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the helper never creates the database")

        let store = try DictationStore(databaseURL: url)
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, exposesToAgents: true)
        _ = try await store.recordDictation(
            DictationRecord(
                id: DictationRecordID(), createdAt: Date(), duration: 1, text: "Envía el informe.", originalText: nil,
                mode: .literal, language: nil, engine: "parakeet", applicationName: "Mail",
                applicationBundleID: nil, delivery: .verified),
            admittedGeneration: policy.generation)

        let answer = try await tool.handler(Data("{}".utf8))
        XCTAssertTrue(answer.hasPrefix("secreteo-dictations/1 total=1"), answer)
        XCTAssertTrue(answer.contains("Envía el informe."))
    }

    func testTheHelperSearchesByMeaningOnlyWithVectorsTheAppSaved() async throws {
        let url = try scratch().appendingPathComponent(DictationStore.fileName)
        let embedding = KeywordEmbedding()
        let store = try DictationStore(databaseURL: url)
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, exposesToAgents: true)
        for text in ["Revisa la acción pendiente.", "No borres estas notas.", "Toma más notas."] {
            let record = DictationRecord(
                id: DictationRecordID(), createdAt: Date(), duration: 1, text: text, originalText: nil,
                mode: .literal, language: nil, engine: "parakeet", applicationName: "Mail",
                applicationBundleID: nil, delivery: .verified)
            _ = try await store.recordDictation(record, admittedGeneration: policy.generation)
            if text.hasPrefix("No borres") {
                _ = try await store.saveDictationEmbedding(
                    .init(recordID: record.id, vector: try await embedding.embed(text)), profile: embedding.profile)
            }
        }
        let tool = try XCTUnwrap(
            DictationToolbox.tools(reader: .opening(url, embedding: embedding)).first { $0.name == "search_dictations" })

        let answer = try await tool.handler(Data(#"{"query":"pendiente"}"#.utf8))
        XCTAssertTrue(answer.hasPrefix("secreteo-dictations/1 total=2 range=1-2 next_offset=none by_meaning=1"), answer)
        XCTAssertTrue(answer.contains("No borres estas notas."))
        XCTAssertFalse(answer.contains("Toma más notas."), "a dictation with no saved vector matches by words only")
        let saved = try await store.dictationEmbeddings(profile: embedding.profile)
        XCTAssertEqual(saved.count, 1, "the helper never writes a vector")
    }

    func testTheDatabaseIsTheEnclosingAppsUnlessOneIsNamed() throws {
        let app = try scratch().appendingPathComponent("Secreteo Dev.app", isDirectory: true)
        let helpers = app.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "com.johnny4young.secreteo.dev", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = helpers.appendingPathComponent("secreteo-mcp")

        XCTAssertEqual(
            DictationMCPCommand.databaseURL(arguments: [], executable: executable),
            DictationStore.defaultURL(bundleIdentifier: "com.johnny4young.secreteo.dev"))
        XCTAssertEqual(
            DictationMCPCommand.databaseURL(arguments: ["--db", "/tmp/x.sqlite"], executable: executable).path,
            "/tmp/x.sqlite")
        XCTAssertEqual(
            DictationMCPCommand.databaseURL(arguments: [], executable: URL(fileURLWithPath: "/usr/local/bin/x")),
            DictationStore.defaultURL(bundleIdentifier: "com.johnny4young.secreteo"))
    }
}
