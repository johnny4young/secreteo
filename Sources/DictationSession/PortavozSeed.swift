import CryptoKit
import Foundation
import LocalModelStore

/// Whether an install takes a model's files from Portavoz's own folder.
enum PortavozSeed {
    /// The store tries its payload and a download it kept before a seed, so a file in either
    /// place means the seed may not be the source. A seed counts only when every file hashes right.
    static func suppliesEveryFile(of manifest: ModelManifest, seed: URL, payload: URL) -> Bool {
        let files = FileManager.default
        let kept = payload.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("partial/\(manifest.shelfKey)", isDirectory: true)
        guard !manifest.artifacts.isEmpty else { return false }
        for artifact in manifest.artifacts {
            if files.fileExists(atPath: payload.appendingPathComponent(artifact.path).path) { return false }
            if files.fileExists(atPath: kept.appendingPathComponent(artifact.sha256).path) { return false }
        }
        return manifest.artifacts.allSatisfy { sha256(of: seed.appendingPathComponent($0.path)) == $0.sha256 }
    }

    private static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
