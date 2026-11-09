import CryptoKit
import Foundation
import LocalModelStore

/// Two consumers of one scratch store, with a synthetic model already installed.
struct ModelLeaseFixture: Sendable {
    let root: URL
    let directory: URL
    let store: LocalModelStore
    let peer: LocalModelStore
    var manifest: ModelManifest { Self.manifest }

    static let bytes = Data("synthetic model".utf8)
    static let manifest = ModelManifest(
        id: "test", displayName: "Test", resolveBase: URL(string: "https://example.invalid")!, revision: "a",
        artifacts: [ModelArtifact(
            path: "model.bin",
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: bytes.count)],
        minimumRAMGB: 1, license: "MIT")

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try LocalModelStore(
            location: .directory(root),
            consumer: StoreConsumer(bundleID: "com.example.secreteo-test", displayName: "Test"))
        peer = try LocalModelStore(
            location: .directory(root),
            consumer: StoreConsumer(bundleID: "com.example.peer-test", displayName: "Peer"))
        let seed = root.appendingPathComponent("seed")
        try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try Self.bytes.write(to: seed.appendingPathComponent("model.bin"))
        directory = try await store.ensureAvailable(Self.manifest, seeds: [seed])
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}
