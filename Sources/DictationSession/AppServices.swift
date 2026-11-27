import DictationKit
import Foundation
import LiveSpeech
import LocalModelStore
import MicCapture
import SpeechCore

/// A session-scoped Silero detector backed by a shared warm model.
/// Dropping this value releases its warm-model user slot automatically.
struct AcquiredSpeechDetector: Sendable {
    let detector: SileroVoiceActivityDetector
    private let releaseToken: SpeechDetectorRelease

    init(detector: SileroVoiceActivityDetector, release: @escaping @Sendable () -> Void) {
        self.detector = detector
        releaseToken = SpeechDetectorRelease(release)
    }

    func finish() {
        releaseToken.finish()
    }
}

/// What the session asks of the app's composition root, which lives outside this target.
@MainActor
protocol AppServices: AnyObject, Sendable {
    var defaults: UserDefaults { get }
    var dictationAdmission: DictationAdmission { get }
    var dictationTriggersMayArm: Bool { get }
    var usesTemporaryMeetingStore: Bool { get }
    var dictationShortcutRegistrar: DictationShortcut.Registrar? { get }
    var microphonePermissions: MicrophonePermissionClient { get }
    var modelStore: LocalModelStore { get }
    var dictationPolisher: any DictationTextPolishing { get }
    func makeDictationSessionDependencies() -> DictationSessionDependencies
    func acquireLiveTranscriptionRuntime(for purpose: LiveSpeechPurpose) async throws -> LiveTranscriptionRuntime
    func acquireSpeechDetector(channel: AudioChannel) async throws -> AcquiredSpeechDetector
}
