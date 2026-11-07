import Foundation

extension DictationModels {
    /// Nothing installed, and a download that stops at 40% until the app quits.
    static var heldDownload: Self {
        Self(
            isVerified: { _ in false },
            wasVerified: { _ in false },
            remember: { _, _ in },
            install: { part, placedBytes in
                placedBytes(part == .speech ? 80 : 0)
                try await Task.sleep(for: .seconds(3_600))
            },
            size: { _ in 100 },
            collectUnused: {})
    }
}
