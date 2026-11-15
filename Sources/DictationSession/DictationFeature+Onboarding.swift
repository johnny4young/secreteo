import Foundation

extension DictationFeature {
    /// Installs what is missing, then loads Parakeet once so Core ML compiles it for this app:
    /// files another app installed are not ready here until then. Apple Speech loads no Parakeet.
    /// `warming` runs once the files are in place, with whether Parakeet was copied from Portavoz.
    func prepareSpeechModel(
        attempt: Int, warming: @MainActor (_ copiedFromPortavoz: Bool) -> Void = { _ in }
    ) async throws {
        guard environment.models != nil else {
            try OnboardingModelPreparation.disposableFixtureResult(arguments: launchArguments, attempt: attempt)?.get()
            return
        }
        try await installModels()
        await refreshReadiness()
        guard speechModelIsRequired else { return }
        warming(environment.models?.wasCopiedFromPortavoz(.speech) ?? false)
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
