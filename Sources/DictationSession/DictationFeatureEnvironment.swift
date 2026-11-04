import AppKit
import ApplicationServices
import DictationOwnership
import LiveSpeech
import LocalModelStore
import MicCapture

/// What the feature asks of the system, which a disposable launch and a test replace.
struct DictationFeatureEnvironment {
    var microphoneState: @Sendable () -> MicrophonePermissionState
    var accessibilityIsGranted: @Sendable () -> Bool
    var askForMicrophone: @Sendable () async -> Void
    var askForAccessibility: @MainActor () -> Void
    var openMicrophoneSettings: @MainActor () -> Void
    /// Nil when no real model is involved.
    var modelIsVerified: (@Sendable () async -> Bool)?

    static func live(microphone: MicrophonePermissionClient, modelStore: LocalModelStore) -> Self {
        Self(
            microphoneState: { microphone.state() },
            accessibilityIsGranted: { AXIsProcessTrusted() },
            askForMicrophone: { _ = await microphone.authorizeIfNeeded() },
            askForAccessibility: { _ = TextInserter.canInsert(promptIfNeeded: true) },
            openMicrophoneSettings: {
                let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
            },
            modelIsVerified: { await modelStore.verifiedInstallation(ModelCatalog.parakeetTdtV3) != nil })
    }

    static func disposable(permissionsAreMissing: Bool) -> Self {
        Self(
            microphoneState: { permissionsAreMissing ? .notDetermined : .authorized },
            accessibilityIsGranted: { !permissionsAreMissing },
            askForMicrophone: {},
            askForAccessibility: {},
            openMicrophoneSettings: {},
            modelIsVerified: nil)
    }
}

/// Why turning dictation on or taking it over did not work, when the user can act on it.
enum HandoffProblem: Equatable {
    case shortcutTaken
    case failed

    /// Not ready yet, or another owner in place, is not a failure: Settings shows what to do next.
    init?(_ outcome: HandoffOutcome) {
        switch outcome {
        case .triggerConflict: self = .shortcutTaken
        case .timedOut, .targetNotReady, .busy, .ioError: self = .failed
        case .completed, .alreadyOwner, .notConfirmed, .notAvailable, .superseded, .cancelled: return nil
        }
    }
}
