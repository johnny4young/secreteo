import AppKit
import ApplicationServices
import DictationOwnership
import LiveSpeech
import MicCapture

/// What the feature asks of the system, which a disposable launch and a test replace.
struct DictationFeatureEnvironment {
    var microphoneState: @Sendable () -> MicrophonePermissionState
    var accessibilityIsGranted: @Sendable () -> Bool
    var askForMicrophone: @Sendable () async -> Void
    /// Calls back once the grant arrives, so readiness need not wait for the next poll.
    var askForAccessibility: @MainActor (_ onGranted: @escaping @MainActor () -> Void) -> Void
    var openMicrophoneSettings: @MainActor () -> Void
    /// macOS's “Press 🌐 key to” choice, nil when it was never set.
    var fnKeyUsage: @Sendable () -> Int? = { nil }
    var openKeyboardSettings: @MainActor () -> Void = {}
    /// Nil when no real model is involved.
    var models: DictationModels?
    /// Portavoz's saved settings, read only when Settings asks.
    var portavozPreferences: @MainActor () -> [String: Any] = { [:] }

    static func live(microphone: MicrophonePermissionClient, models: DictationModels) -> Self {
        Self(
            microphoneState: { microphone.state() },
            accessibilityIsGranted: { AXIsProcessTrusted() },
            askForMicrophone: { _ = await microphone.authorizeIfNeeded() },
            askForAccessibility: { onGranted in
                AccessibilityGrantGuide.shared.show(
                    opensSystemSettings: true, isGranted: { AXIsProcessTrusted() }, onGranted: onGranted)
            },
            openMicrophoneSettings: {
                let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
            },
            fnKeyUsage: { ModifierKeySetting.systemFnUsage() },
            openKeyboardSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            },
            models: models,
            portavozPreferences: {
                UserDefaults.standard.persistentDomain(forName: PortavozPreferenceImport.domain) ?? [:]
            })
    }

    /// A disposable launch reads its fixtures from its arguments.
    static func disposable(arguments: [String], shelf: () -> DictationModels) -> Self {
        disposable(
            permissionsAreMissing: arguments.contains("-seed-dictation-permissions-missing"),
            seedsPortavozPreferences: arguments.contains("-seed-portavoz-preferences"),
            fnKeyIsFree: arguments.contains("-seed-fn-key-free"),
            models: arguments.contains("-seed-model-download-held") ? .heldDownload
                : arguments.contains("-seed-model-shelf") ? shelf() : nil)
    }

    /// A disposable launch never reads a real Portavoz install, only the fixture.
    static func disposable(
        permissionsAreMissing: Bool, seedsPortavozPreferences: Bool = false, fnKeyIsFree: Bool = false,
        models: DictationModels? = nil
    ) -> Self {
        Self(
            microphoneState: { permissionsAreMissing ? .notDetermined : .authorized },
            accessibilityIsGranted: { !permissionsAreMissing },
            askForMicrophone: {},
            // Shows the guide so it can be tested, without opening System Settings.
            askForAccessibility: { onGranted in
                AccessibilityGrantGuide.shared.show(
                    opensSystemSettings: false, isGranted: { !permissionsAreMissing }, onGranted: onGranted)
            },
            openMicrophoneSettings: {},
            fnKeyUsage: { fnKeyIsFree ? 0 : nil },
            models: models,
            portavozPreferences: { seedsPortavozPreferences ? PortavozPreferenceImport.fixture : [:] })
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
