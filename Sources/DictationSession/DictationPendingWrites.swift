import Foundation

/// Registers durable writes before their tasks start, so relaunch cannot overtake a queued save.
@MainActor
final class DictationPendingWrites {
    private var pending: Set<UUID> = []
    var onIdle: (() -> Void)?
    var hasPending: Bool { !pending.isEmpty }

    func begin() -> @MainActor () -> Void {
        let id = UUID()
        pending.insert(id)
        return { [weak self] in
            guard let self, pending.remove(id) != nil else { return }
            if pending.isEmpty { onIdle?() }
        }
    }
}
