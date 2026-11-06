import Darwin
import Foundation
import LiveSpeech
import LocalModelStore

/// The models a dictation uses, which a disposable launch does not have.
struct DictationModels: Sendable {
    enum Part: CaseIterable, Sendable {
        case speech
        case speechDetector
    }

    /// Hashes the files, unless they are unchanged since a hash in this process.
    var isVerified: @Sendable (Part) async -> Bool
    /// Whether the files look as they did after a hash on an earlier launch. Reads no contents.
    var wasVerified: @Sendable (Part) async -> Bool
    var remember: @Sendable (Part, _ isVerified: Bool) async -> Void
    var install: @Sendable (Part) async throws -> Void
    /// Retires this app's claims on models it no longer pins and clears what nobody needs.
    /// `Part` is that list, so every model this app installs must be a case of it.
    var collectUnused: @Sendable () async -> Void

    /// Throws the first failure, so the caller can say what went wrong.
    func installMissing() async throws {
        for part in Part.allCases {
            guard await !isVerified(part) else { continue }
            try await install(part)
        }
    }

    /// Portavoz before the shared store keeps the same pinned files here. The store only clones
    /// from it, and only files that hash right.
    static var portavozModels: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Portavoz/Models", isDirectory: true)
    }

    static func live(store: LocalModelStore, defaults: UserDefaults, seedRoot: URL) -> Self {
        // UserDefaults is thread-safe.
        nonisolated(unsafe) let defaults = defaults
        @Sendable func fingerprint(_ part: Part) async -> String? {
            guard let directory = try? await store.directory(for: part.manifest) else { return nil }
            return VerifiedModelRecord.fingerprint(of: part.manifest, in: directory)
        }
        return Self(
            isVerified: { await store.verifiedInstallation($0.manifest) != nil },
            wasVerified: { part in
                guard let known = defaults.string(forKey: part.recordKey) else { return false }
                return await fingerprint(part) == known
            },
            remember: { part, isVerified in
                defaults.set(isVerified ? await fingerprint(part) : nil, forKey: part.recordKey)
            },
            install: { part in
                _ = try await store.ensureAvailable(part.manifest, seeds: [part.seed(in: seedRoot)], progress: nil)
            },
            // Never worth failing a launch over, and the next launch tries again.
            collectUnused: {
                try? await store.reconcileClaims(keeping: Part.allCases.map(\.manifest))
                _ = try? await store.collectGarbage()
            })
    }
}

extension DictationModels.Part {
    /// The folder Portavoz installs this part in, under `seedRoot`.
    func seed(in seedRoot: URL) -> URL {
        switch self {
        case .speech: seedRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
        case .speechDetector: seedRoot.appendingPathComponent("silero-vad-coreml", isDirectory: true)
        }
    }
}

private extension DictationModels.Part {
    var manifest: ModelManifest {
        switch self {
        case .speech: ModelCatalog.parakeetTdtV3
        case .speechDetector: ModelCatalog.sileroVAD
        }
    }

    var recordKey: String {
        switch self {
        case .speech: "dictationVerifiedSpeechModel"
        case .speechDetector: "dictationVerifiedSpeechDetector"
        }
    }
}

/// What a model's files looked like after a hash, kept between launches. It only decides what
/// to show while this launch's first hash runs: a load still needs the store's own verification.
enum VerifiedModelRecord {
    static func fingerprint(of manifest: ModelManifest, in directory: URL) -> String? {
        var paths = Set([""])
        for artifact in manifest.artifacts {
            paths.insert(artifact.path)
            var parent = (artifact.path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                paths.insert(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        var lines = [manifest.digest]
        for path in paths.sorted() {
            let url = path.isEmpty ? directory : directory.appendingPathComponent(path)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { return nil }
            let modified = "\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"
            let changed = "\(info.st_ctimespec.tv_sec).\(info.st_ctimespec.tv_nsec)"
            lines.append("\(path) \(info.st_mode) \(info.st_ino) \(info.st_size) \(modified) \(changed)")
        }
        return lines.joined(separator: "\n")
    }
}
