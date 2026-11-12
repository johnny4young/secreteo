import CryptoKit
import Foundation
import LocalModelStore

extension DictationModels {
    /// Two small synthetic models in a disposable store: one this app keeps alone, one it
    /// shares with a fixture app. Their files come from a local folder, so nothing downloads.
    static func shelf(store: LocalModelStore, root: URL) -> Self {
        let seeded = Task { try? await ShelfFixture.seed(store, root: root) }
        return Self(
            isVerified: { _ in true },
            wasVerified: { _ in true },
            remember: { _, _ in },
            install: { _, _ in },
            size: { _ in 1 },
            collectUnused: {},
            inventory: {
                _ = await seeded.value
                return await store.inventory().map { DictationModelEntry($0, ownName: store.consumer.displayName) }
            },
            release: { key in
                guard let manifest = ShelfFixture.manifests.first(where: { $0.shelfKey == key }) else {
                    throw DictationModelRemoval.Failure.notThisAppsModel
                }
                return DictationModelRemoval(try await store.remove(manifest))
            },
            changes: { store.changes() })
    }
}

private enum ShelfFixture {
    static let files: [(id: String, name: String, bytes: Data)] = [
        ("sample-speech", "Sample Speech Model", Data(repeating: 7, count: 48_000)),
        ("sample-detector", "Sample Voice Detector", Data(repeating: 9, count: 16_000))
    ]

    static let manifests: [ModelManifest] = files.map { file in
        let digest = SHA256.hash(data: file.bytes).map { String(format: "%02x", $0) }.joined()
        return ModelManifest(
            id: file.id, displayName: file.name, resolveBase: URL(string: "https://example.invalid")!,
            revision: "fixture",
            artifacts: [ModelArtifact(path: "model.bin", sha256: digest, sizeBytes: file.bytes.count)],
            minimumRAMGB: 1, license: "MIT")
    }

    static func seed(_ store: LocalModelStore, root: URL) async throws {
        let seeds = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: seeds) }
        let other = try LocalModelStore(
            location: .directory(root),
            consumer: StoreConsumer(bundleID: "com.example.shelf-fixture", displayName: "Portavoz"))
        for (file, manifest) in zip(files, manifests) {
            let folder = seeds.appendingPathComponent(file.id, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try file.bytes.write(to: folder.appendingPathComponent("model.bin"))
            try await store.ensureAvailable(manifest, seeds: [folder])
        }
        try await other.ensureAvailable(manifests[0], seeds: [seeds.appendingPathComponent(files[0].id)])
    }
}
