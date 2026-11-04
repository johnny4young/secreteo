import Foundation
import LiveSpeech
import LocalModelStore

extension DictationSpeechGate {
    static let defaultsKey = "dictationSpeechGate"
    static let enabledByDefault = true
    /// Silero's reference threshold, below FluidAudio's 0.85 segmentation default:
    /// withholding quiet real speech costs more than letting noise through.
    static let speechProbabilityThreshold: Float = 0.5

    /// On unless the user turned it off; the detector itself downloads only
    /// when dictation is turned on or from Settings.
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? enabledByDefault
    }

    static func heardSpeech(_ batch: VoiceActivityBatch) -> Bool {
        batch.observations.contains { $0.isSpeechActive || $0.speechProbability >= speechProbabilityThreshold }
    }

    /// Silero over the verified installation only; a missing model makes the
    /// verdict undetermined (paste as before), never a download.
    static func silero(store: LocalModelStore) -> DictationSpeechGate {
        DictationSpeechGate {
            let detector = try await SileroVoiceActivityDetector.load(from: store, channel: .microphone)
            return { chunk in heardSpeech(try await detector.process(chunk)) }
        }
    }
}
