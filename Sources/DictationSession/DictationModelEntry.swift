import Foundation
import LocalModelStore

/// One model in the shared folder, as Settings lists it.
struct DictationModelEntry: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let bytes: Int?
    /// Other apps that keep this model, by name.
    let sharedWith: [String]
    let isClaimedByThisApp: Bool

    init(id: String, name: String, bytes: Int?, sharedWith: [String], isClaimedByThisApp: Bool) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.sharedWith = sharedWith
        self.isClaimedByThisApp = isClaimedByThisApp
    }

    /// Claims list apps by name, so only one copy of this app's name is its own claim.
    init(_ entry: LocalModelStore.InventoryEntry, ownName: String) {
        var others = entry.claimants
        if entry.isClaimedByThisConsumer, let own = others.firstIndex(of: ownName) { others.remove(at: own) }
        self.init(
            id: entry.key, name: entry.displayName ?? entry.key, bytes: entry.logicalBytes,
            sharedWith: Array(Set(others)).sorted(), isClaimedByThisApp: entry.isClaimedByThisConsumer)
    }
}

enum DictationModelRemoval: Equatable, Sendable {
    case removed
    case keptForOthers
    /// A process still has it loaded; the next launch's collection deletes it.
    case deferred

    enum Failure: Error {
        case notThisAppsModel
    }

    init(_ outcome: LocalModelStore.RemovalOutcome) {
        switch outcome {
        case .removed: self = .removed
        case .keptForOthers: self = .keptForOthers
        case .deferred: self = .deferred
        }
    }
}

extension ModelManifest {
    /// The folder name the store gives this manifest, from the store's documented format.
    var shelfKey: String {
        "\(id)@\(revision.prefix(12))-\(digest.prefix(12))"
    }
}

extension LocalModelStore {
    /// Claims files that are already verified through the normal install path. If they turn out
    /// to be gone under the install lock, the first download event cancels the install before
    /// it sends a request, so adopting never downloads without the person asking.
    func ensureAvailableWithoutDownloading(_ manifest: ModelManifest) async throws {
        try await ensureAvailable(manifest) { event in
            // Reported on the install's own task, before its first request.
            if case .downloading = event { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
}
