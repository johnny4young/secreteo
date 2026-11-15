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

    /// What a model's card says. The store reports bytes only for the whole install.
    enum PartStatus: Equatable {
        case missing
        case downloading
        case installed
        case warming(copied: Bool)
        case ready(copied: Bool)
    }

    private(set) var phase: Phase = .idle
    private(set) var attempt = 0
    private(set) var isWarming = false
    private(set) var speechWasCopied = false

    func prepare(using load: @MainActor () async throws -> Void) async {
        guard phase != .preparing, phase != .ready else { return }
        phase = .preparing
        isWarming = false
        attempt += 1
        do {
            try await load()
            phase = .ready
        } catch {
            phase = .failed(Failure.classify(error))
        }
    }

    func startedWarming(copiedFromPortavoz: Bool) {
        isWarming = true
        speechWasCopied = copiedFromPortavoz
    }

    func speechStatus(isInstalled: Bool) -> PartStatus {
        switch phase {
        case .ready: .ready(copied: speechWasCopied)
        case .preparing where isWarming: .warming(copied: speechWasCopied)
        case .preparing: isInstalled ? .installed : .downloading
        case .idle, .failed: isInstalled ? .installed : .missing
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
