import Foundation
import LiveSpeech
import LocalModelStore
import Synchronization

/// Releases a warm speech detector user slot once, even if the owning task is cancelled.
final class SpeechDetectorRelease: Sendable {
    private let release: Mutex<(@Sendable () -> Void)?>

    init(_ release: @escaping @Sendable () -> Void) {
        self.release = Mutex(release)
    }

    func finish() {
        let action = release.withLock { current -> (@Sendable () -> Void)? in
            defer { current = nil }
            return current
        }
        action?()
    }

    deinit { finish() }
}

extension DictationSpeechGate {
    static let defaultsKey = "dictationSpeechGate"
    static let enabledByDefault = true
    /// Silero's reference threshold, below FluidAudio's 0.85 segmentation default:
    /// withholding quiet real speech costs more than letting noise through.
    static let speechProbabilityThreshold: Float = 0.5

    /// On unless the user turned it off; the detector downloads with the speech model,
    /// from Settings or onboarding, never when dictation is turned on.
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? enabledByDefault
    }

    static func heardSpeech(_ batch: VoiceActivityBatch) -> Bool {
        batch.observations.contains { $0.isSpeechActive || $0.speechProbability >= speechProbabilityThreshold }
    }

    /// Silero over the verified installation only; a missing model makes the
    /// verdict undetermined (paste as before), never a download.
    static func silero(
        acquire: @escaping @Sendable () async throws -> AcquiredSpeechDetector
    ) -> DictationSpeechGate {
        DictationSpeechGate {
            let acquired = try await acquire()
            return { chunk in
                heardSpeech(try await acquired.detector.process(chunk))
            }
        }
    }
}
