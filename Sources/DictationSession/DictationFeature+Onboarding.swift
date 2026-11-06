import Foundation

extension DictationFeature {
    /// Installs what is missing, then loads the model once so Core ML compiles it for this app:
    /// files another app installed are not ready here until then.
    func prepareSpeechModel(attempt: Int) async throws {
        guard let models = environment.models else {
            try OnboardingModelPreparation.disposableFixtureResult(arguments: launchArguments, attempt: attempt)?.get()
            return
        }
        if modelState != .ready { modelState = .downloading }
        do {
            try await models.installMissing()
        } catch {
            modelState = .failed
            throw error
        }
        modelState = .ready
        await refreshReadiness()
        _ = try await warmEngine.acquire()
        warmEngine.releaseWhenIdle()
    }

    /// macOS posts no change notification for Accessibility, so a visible permission row asks again.
    func refreshPermissionsIfChanged() async {
        let microphone = environment.microphoneState() == .authorized
        guard microphone != microphoneIsAuthorized || environment.accessibilityIsGranted() != accessibilityIsGranted
        else { return }
        await refreshReadiness()
    }
}
