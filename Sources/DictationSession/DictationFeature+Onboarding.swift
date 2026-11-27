import Foundation

extension DictationFeature {
    /// Installs what is missing, then loads Parakeet once so Core ML compiles it for this app:
    /// files another app installed are not ready here until then. Apple Speech loads no Parakeet.
    /// `stage` says what the wait is: files arriving, and from where, then the warm-up.
    func prepareSpeechModel(
        attempt: Int, stage: @MainActor (OnboardingModelPreparation.Stage) -> Void = { _ in }
    ) async throws {
        guard environment.models != nil else {
            try OnboardingModelPreparation.disposableFixtureResult(arguments: launchArguments, attempt: attempt)?.get()
            return
        }
        if speechModelIsRequired, !speechModelIsInstalled, let models = environment.models {
            stage(.installing(copying: await models.comesFromPortavoz(.speech)))
        }
        try await installModels()
        // Before the files are hashed again, so the capsule never empties between the two waits.
        let copied = environment.models?.wasCopiedFromPortavoz(.speech) ?? false
        if speechModelIsRequired { stage(.warming(copied: copied)) }
        await refreshReadiness()
        guard speechModelIsRequired else { return }
        _ = try await warmEngine.acquire()
        warmEngine.releaseWhenIdle()
    }

    /// macOS posts no change notification for Accessibility or the Globe key, so visible setup rows poll.
    func refreshPermissionsIfChanged() async {
        let microphone = environment.microphoneState() == .authorized
        let fnIsFree = ModifierKeySetting.systemFnKeyIsFree(usage: environment.fnKeyUsage())
        guard microphone != microphoneIsAuthorized
            || environment.accessibilityIsGranted() != accessibilityIsGranted
            || fnIsFree != fnKeyIsFree
        else { return }
        await refreshReadiness()
    }
}
