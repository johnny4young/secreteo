import DictationKit
import Foundation
import SpeechCore
import Testing

@testable import DictationStore

/// Deleting, deleting all and retention leave no trace of the words in the files.
@Suite
struct DictationHistoryErasureTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    enum Erase: CaseIterable {
        case one, all, retention, retentionOnSave
    }

    @Test(arguments: Erase.allCases)
    func erasedWordsLeaveNoBytesBehind(_ erase: Erase) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-erase-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(DictationStore.fileName)
        let store = try DictationStore(databaseURL: url)
        _ = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: true, retentionDays: 7, at: now)
        let token = "zebracornio\(UUID().uuidString.prefix(8).lowercased())"
        let old = now.addingTimeInterval(-10 * 86_400)
        let expires = erase == .retention || erase == .retentionOnSave
        let secret = record("Recuerda \(token) mañana.", original: "eh \(token)", at: expires ? old : now)
        _ = try await store.recordDictation(record("Esta nota se queda.", at: now), admittedGeneration: 0, at: old)
        _ = try await store.recordDictation(secret, admittedGeneration: 0, at: old)
        // A vector is derived from the words, so it must go with them.
        let vector = (0..<16).map { Float(9_001 + $0) + 0.123_45 }
        #expect(try await store.saveDictationEmbedding(.init(recordID: secret.id, vector: vector), profile: "probe"))
        let vectorBytes = DictationStore.encode(vector)
        #expect(await store.checkpoint())
        #expect(try bytes(near: url).contains(Data(token.utf8)), "the probe must reach the file first")
        #expect(try bytes(near: url).contains(vectorBytes), "the vector probe must reach the file first")

        switch erase {
        case .one: _ = try await store.deleteDictationRecord(secret.id)
        case .all: try await store.deleteAllDictationRecords()
        case .retention: try await store.purgeExpiredDictationRecords(at: now)
        case .retentionOnSave: _ = try await store.recordDictation(record("Otra nota.", at: now), admittedGeneration: 0, at: now)
        }

        #expect(!(try bytes(near: url).contains(Data(token.utf8))))
        #expect(!(try bytes(near: url).contains(vectorBytes)))
    }

    private func record(_ text: String, original: String? = nil, at createdAt: Date) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: createdAt, duration: 1, text: text, originalText: original,
            mode: .clean, language: "es", engine: "parakeet", applicationName: "Notes",
            applicationBundleID: nil, delivery: .verified)
    }

    private func bytes(near url: URL) throws -> Data {
        try ["", "-wal", "-shm"].reduce(into: Data()) { data, suffix in
            let file = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: file.path) { data += try Data(contentsOf: file) }
        }
    }
}
