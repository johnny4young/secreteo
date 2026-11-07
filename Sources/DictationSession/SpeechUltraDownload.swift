import Foundation
import Observation

/// Parakeet Ultra is opt-in, so its download lives apart from the models dictation needs.
@MainActor
@Observable
final class SpeechUltraDownload {
    private(set) var state = DictationFeature.ModelState.missing
    /// Nil until the store reports bytes, so the bar starts indeterminate.
    private(set) var fraction: Double?
    @ObservationIgnored private(set) var generation = 0

    /// Hashes the files, after showing what an earlier launch remembered.
    func refresh(_ models: DictationModels) async {
        guard state != .downloading else { return }
        if await models.wasVerified(.speechUltra) { state = .ready }
        let verified = await models.isVerified(.speechUltra)
        // A cancelled check stops hashing and reports the files as bad, which says nothing about them.
        guard !Task.isCancelled, state != .downloading else { return }
        state = verified ? .ready : state == .failed ? .failed : .missing
        await models.remember(.speechUltra, verified)
    }

    /// `installed` runs once Ultra verifies, so a warm v3 model can make way.
    func download(_ models: DictationModels, installed: @escaping @MainActor () -> Void) {
        guard state != .downloading else { return }
        state = .downloading
        fraction = nil
        generation += 1
        let generation = generation
        Task { [weak self] in
            do {
                try await models.installMissing([.speechUltra]) { fraction in
                    Task { @MainActor in self?.progressed(fraction, generation: generation) }
                }
                self?.finish(.ready, generation: generation)
                installed()
            } catch {
                self?.finish(.failed, generation: generation)
            }
        }
    }

    /// Reports arrive on separate tasks, so a late one must not move the bar back or reach another download.
    func progressed(_ fraction: Double, generation: Int) {
        guard generation == self.generation, state == .downloading else { return }
        self.fraction = max(self.fraction ?? 0, fraction)
    }

    private func finish(_ state: DictationFeature.ModelState, generation: Int) {
        guard generation == self.generation else { return }
        self.state = state
        fraction = nil
    }
}
