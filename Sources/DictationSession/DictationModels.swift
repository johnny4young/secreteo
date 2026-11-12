import Darwin
import Foundation
import Synchronization
import LiveSpeech
import LocalModelStore

/// The models a dictation uses. A disposable launch has none, except a UI test fixture.
struct DictationModels: Sendable {
    enum Part: CaseIterable, Sendable {
        case speech
        case speechDetector
        /// Installed only when the person chooses it.
        case speechUltra

        /// What dictation needs before it can start.
        static let required: [Self] = [.speech, .speechDetector]
    }

    /// Hashes the files, unless they are unchanged since a hash in this process.
    var isVerified: @Sendable (Part) async -> Bool
    /// Whether the files look as they did after a hash on an earlier launch. Reads no contents.
    var wasVerified: @Sendable (Part) async -> Bool
    var remember: @Sendable (Part, _ isVerified: Bool) async -> Void
    /// Reports how many of the part's bytes are in place, which a resumed download starts above zero.
    var install: @Sendable (Part, _ placedBytes: @escaping @Sendable (Int) -> Void) async throws -> Void
    /// The pinned size, so a small part counts for little in the overall progress.
    var size: @Sendable (Part) -> Int
    /// Retires this app's claims on models it no longer pins and clears what nobody needs.
    /// `Part` is that list, so every model this app installs must be a case of it.
    var collectUnused: @Sendable () async -> Void
    /// Writes this app's claim on verified files another app installed. Never downloads.
    var adopt: @Sendable (Part) async -> Void = { _ in }
    /// Every model in the shared folder and the apps that keep it.
    var inventory: @Sendable () async -> [DictationModelEntry] = { [] }
    /// Drops only this app's claim. The files stay while another app keeps them.
    var release: @Sendable (_ key: String) async throws -> DictationModelRemoval = { _ in .removed }
    /// Fires when any process changes the shared folder.
    var changes: @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } }

    /// Throws the first failure, so the caller can say what went wrong.
    /// `progress` gets the share of the missing bytes in place, from 0 to 1, once per whole percent:
    /// the store reports every chunk, and the bar shows no finer steps.
    func installMissing(
        _ parts: [Part] = Part.required, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        var missing: [Part] = []
        for part in parts where await !isVerified(part) {
            missing.append(part)
        }
        let total = missing.reduce(0) { $0 + size($1) }
        var done = 0
        let lastPercent = Mutex(-1)
        for part in missing {
            let before = done
            try await install(part) { placed in
                guard total > 0 else { return }
                let fraction = min(Double(before + placed) / Double(total), 1)
                let percent = Int(fraction * 100)
                guard lastPercent.withLock({ last in
                    defer { last = max(last, percent) }
                    return percent > last
                }) else { return }
                progress(fraction)
            }
            done += size(part)
        }
    }

    /// Portavoz before the shared store keeps the same pinned files here. The store only clones
    /// from it, and only files that hash right.
    static var portavozModels: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Portavoz/Models", isDirectory: true)
    }

    /// `manifests` lets a test pin files it can write; the app keeps the catalog's.
    static func live(
        store: LocalModelStore, defaults: UserDefaults, seedRoot: URL,
        manifests: @escaping @Sendable (Part) -> ModelManifest = \.manifest
    ) -> Self {
        // UserDefaults is thread-safe.
        nonisolated(unsafe) let defaults = defaults
        @Sendable func fingerprint(_ part: Part) async -> String? {
            guard let directory = try? await store.directory(for: manifests(part)) else { return nil }
            return VerifiedModelRecord.fingerprint(of: manifests(part), in: directory)
        }
        return Self(
            isVerified: { await store.verifiedInstallation(manifests($0)) != nil },
            wasVerified: { part in
                guard let known = defaults.string(forKey: part.recordKey) else { return false }
                return await fingerprint(part) == known
            },
            remember: { part, isVerified in
                defaults.set(isVerified ? await fingerprint(part) : nil, forKey: part.recordKey)
            },
            install: { part, placedBytes in
                _ = try await store.ensureAvailable(manifests(part), seeds: [part.seed(in: seedRoot)]) { event in
                    switch event {
                    case .downloading(let state): placedBytes(state.completedBytes)
                    case .waitingForOtherProcess(let completed, _): placedBytes(completed)
                    case .verifying: break
                    }
                }
            },
            size: { manifests($0).totalSizeBytes },
            // Never worth failing a launch over, and the next launch tries again.
            collectUnused: {
                try? await store.reconcileClaims(keeping: Part.allCases.map(manifests))
                _ = try? await store.collectGarbage()
            },
            adopt: { part in
                guard await store.verifiedInstallation(manifests(part)) != nil else { return }
                // Its own task, because a vetoed download cancels the task it runs on.
                _ = await Task { try await store.ensureAvailableWithoutDownloading(manifests(part)) }.result
            },
            inventory: {
                await store.inventory().map { DictationModelEntry($0, ownName: store.consumer.displayName) }
            },
            release: { key in
                guard let part = Part.allCases.first(where: { manifests($0).shelfKey == key }) else {
                    throw DictationModelRemoval.Failure.notThisAppsModel
                }
                defaults.set(nil, forKey: part.recordKey)
                return DictationModelRemoval(try await store.remove(manifests(part)))
            },
            changes: { store.changes() })
    }
}

extension DictationModels.Part {
    /// The folder Portavoz installs this part in, under `seedRoot`.
    func seed(in seedRoot: URL) -> URL {
        let folder = switch self {
        case .speech: "parakeet-tdt-0.6b-v3"
        case .speechDetector: "silero-vad-coreml"
        case .speechUltra: "parakeet-ultra"
        }
        return seedRoot.appendingPathComponent(folder, isDirectory: true)
    }

    var manifest: ModelManifest {
        switch self {
        case .speech: ModelCatalog.parakeetTdtV3
        case .speechDetector: ModelCatalog.sileroVAD
        case .speechUltra: ModelCatalog.parakeetUltra
        }
    }

    var recordKey: String {
        switch self {
        case .speech: "dictationVerifiedSpeechModel"
        case .speechDetector: "dictationVerifiedSpeechDetector"
        case .speechUltra: "dictationVerifiedSpeechUltra"
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
