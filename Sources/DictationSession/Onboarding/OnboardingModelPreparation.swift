import Foundation
import LocalModelStore
import Observation

/// Presentation-only state for explicit onboarding preparation. DictationFeature
/// continues to own shared model loads, leases, and idle release on every exit.
@MainActor
@Observable
final class OnboardingModelPreparation {
    enum Failure: Equatable {
        case network
        case storage
        case cancelled
        case unavailable

        var message: String {
            switch self {
            case .network:
                L10n.text("Models could not be downloaded. Check your connection and try again.")
            case .storage:
                L10n.text("Models could not be saved. Check available disk space and try again.")
            case .cancelled:
                L10n.text("Model preparation was interrupted. You can try again.")
            case .unavailable:
                L10n.text("Models could not be prepared. Try again, or continue setup and download them later.")
            }
        }

        static func classify(_ error: any Error) -> Self {
            if error is CancellationError { return .cancelled }
            if let storeError = error as? LocalModelStore.LocalModelStoreError {
                switch storeError {
                case .outOfSpace: return .storage
                case .downloadFailed: return .network
                default: break
                }
            }
            // Writes outside LocalModelStore can still surface a raw disk-space cause.
            if LocalModelStore.isOutOfSpace(error as NSError) { return .storage }
            if let error = error as? URLError {
                switch error.code {
                case .cancelled:
                    return .cancelled
                case .timedOut, .cannotFindHost, .cannotConnectToHost,
                     .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet,
                     .secureConnectionFailed, .dataNotAllowed, .internationalRoamingOff:
                    return .network
                default:
                    return .unavailable
                }
            }
            // Never render arbitrary error descriptions, model paths or URLs.
            return .unavailable
        }
    }

    enum Phase: Equatable {
        case idle
        case preparing
        case ready
        case failed(Failure)
    }

    /// What the wait is for. Warming up is the longer one, and has no number to show.
    enum Stage: Equatable {
        case installing(copying: Bool)
        case warming(copied: Bool)
    }

    /// What a model's card says. The store reports bytes only for the whole install.
    enum PartStatus: Equatable {
        case missing
        case downloading
        case copying
        case installed(copied: Bool)
        case ready(copied: Bool)
    }

    private(set) var phase: Phase = .idle
    private(set) var attempt = 0
    private(set) var stage = Stage.installing(copying: false)
    /// The furthest the download got in this attempt, kept when the store stops reporting.
    private(set) var downloaded: Double?

    var isWarming: Bool {
        if case .warming = stage { return true }
        return false
    }

    private var speechWasCopied: Bool { stage == .warming(copied: true) }

    func prepare(using load: @MainActor () async throws -> Void) async {
        guard phase != .preparing, phase != .ready else { return }
        phase = .preparing
        stage = .installing(copying: false)
        downloaded = nil
        attempt += 1
        do {
            try await load()
            phase = .ready
        } catch {
            phase = .failed(Failure.classify(error))
        }
    }

    func entered(_ stage: Stage) {
        guard phase == .preparing else { return }
        self.stage = stage
    }

    /// The store clears its fraction when it finishes, which must not empty the capsule.
    func downloaded(_ fraction: Double?) {
        guard phase == .preparing, let fraction else { return }
        downloaded = max(downloaded ?? 0, fraction)
    }

    /// The share of the missing bytes in place. Nil while the store has reported none, and
    /// while warming up, which has no measure: no made-up number.
    var fraction: Double? { isWarming ? nil : downloaded }

    func speechStatus(isInstalled: Bool) -> PartStatus {
        switch phase {
        case .ready: .ready(copied: speechWasCopied)
        case .preparing where isWarming: .installed(copied: speechWasCopied)
        case .preparing where isInstalled: .installed(copied: false)
        case .preparing: stage == .installing(copying: true) ? .copying : .downloading
        case .idle, .failed: isInstalled ? .installed(copied: false) : .missing
        }
    }

    /// The detector needs no warm-up, so installed is ready.
    func detectorStatus(isInstalled: Bool) -> PartStatus {
        if isInstalled || phase == .ready || (phase == .preparing && isWarming) { return .ready(copied: false) }
        return phase == .preparing ? .downloading : .missing
    }

    /// Only the disposable UI-test store may replace model preparation. The
    /// fixture never starts a model download, even on its successful retry.
    static func disposableFixtureResult(
        arguments: [String], attempt: Int
    ) -> Result<Void, Error>? {
        guard arguments.contains("-use-temp-store"),
              arguments.contains("-simulate-onboarding-model-recovery") else { return nil }
        return attempt == 1 ? .failure(URLError(.notConnectedToInternet)) : .success(())
    }
}
