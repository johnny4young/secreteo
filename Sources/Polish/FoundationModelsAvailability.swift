import Foundation
import FoundationModels

/// Whether Apple's on-device model can run here, with an English reason when it cannot.
public enum FoundationModelsAvailability {
    /// UI tests simulate a Mac without Apple Intelligence on any host.
    public static let simulatedUnavailabilityArgument = "-simulate-no-apple-intelligence"
    public static let deviceNotEligibleReason = "this device does not support Apple Intelligence"
    public static let appleIntelligenceDisabledReason =
        "Apple Intelligence is turned off (System Settings → Apple Intelligence & Siri)"
    public static let modelNotReadyReason =
        "the on-device model is still downloading; try again in a few minutes"

    /// nil when ready; otherwise a human-readable reason (Apple
    /// Intelligence off, model still downloading, unsupported device).
    public static func unavailabilityReason(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> String? {
        if arguments.contains(simulatedUnavailabilityArgument) {
            return appleIntelligenceDisabledReason
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return deviceNotEligibleReason
            case .appleIntelligenceNotEnabled:
                return appleIntelligenceDisabledReason
            case .modelNotReady:
                return modelNotReadyReason
            @unknown default:
                return "unknown reason"
            }
        }
    }
}
