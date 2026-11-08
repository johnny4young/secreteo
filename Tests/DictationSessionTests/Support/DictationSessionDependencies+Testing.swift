@testable import DictationSession

extension DictationSessionDependencies {
    /// Skips the real stop tail but still honors cancellation, as the sleep does.
    static let immediateStopTail: @MainActor (Duration) async throws -> Void = { _ in
        await Task.yield()
        try Task.checkCancellation()
    }

    func skippingStopTail() -> Self {
        var dependencies = self
        dependencies.waitForStopTail = Self.immediateStopTail
        return dependencies
    }
}
