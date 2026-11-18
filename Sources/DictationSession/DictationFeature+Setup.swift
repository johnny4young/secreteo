import Foundation

/// The next thing that keeps dictation from working, so every surface offers the same single fix.
enum DictationSetupStep: Equatable {
    case turnOn
    case allowMicrophone
    case allowAccessibility
    case downloadModel
    case downloadingModel
    case practice

    var title: String {
        switch self {
        case .turnOn: L10n.text("Turn On Dictation")
        case .allowMicrophone: L10n.text("Allow Microphone")
        case .allowAccessibility: L10n.text("Allow Accessibility…")
        case .downloadModel: L10n.text("Download Speech Model")
        case .downloadingModel: L10n.text("Downloading Speech Model…")
        case .practice: L10n.text("Try Dictation…")
        }
    }
}

extension DictationFeature {
    var setupStep: DictationSetupStep? {
        Self.setupStep(
            isEnabled: isEnabled, microphoneIsAuthorized: microphoneIsAuthorized,
            accessibilityIsGranted: accessibilityIsGranted, modelState: modelState,
            practiceIsComplete: practiceIsComplete)
    }

    /// Quick grants come before the download, and practice last because it needs everything else.
    nonisolated static func setupStep(
        isEnabled: Bool, microphoneIsAuthorized: Bool, accessibilityIsGranted: Bool,
        modelState: ModelState, practiceIsComplete: Bool
    ) -> DictationSetupStep? {
        if !isEnabled { return .turnOn }
        if !microphoneIsAuthorized { return .allowMicrophone }
        if !accessibilityIsGranted { return .allowAccessibility }
        switch modelState {
        case .missing, .failed: return .downloadModel
        case .downloading: return .downloadingModel
        case .ready: break
        }
        return practiceIsComplete ? nil : .practice
    }

    var practiceStartsComplete: Bool {
        (usesTemporaryMeetingStore && !launchArguments.contains("-seed-dictation-practice-missing"))
            || defaults.bool(forKey: ReadinessGap.practiceCompletionKey)
    }

    func refreshFnKey() {
        fnKeyIsFree = ModifierKeySetting.systemFnKeyIsFree(usage: environment.fnKeyUsage())
    }

    func openKeyboardSettings() {
        environment.openKeyboardSettings()
    }

    /// Runs the step. Practice happens in Settings, right under the readiness header.
    func perform(_ step: DictationSetupStep, openSettings: () -> Void) {
        switch step {
        case .turnOn: setEnabled(true)
        case .allowMicrophone: requestMicrophone()
        case .allowAccessibility: requestAccessibility()
        case .downloadModel: downloadModel()
        case .downloadingModel: break
        case .practice: openSettings()
        }
    }
}
