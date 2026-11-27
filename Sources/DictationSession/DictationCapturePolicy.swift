import Foundation
import DictationKit
import SpeechCore

/// Pure capture-edge policy. The minimum is measured from the moment the
/// first nonempty microphone buffer arrives, never from model preparation or panel
/// presentation, so a slow cold start cannot turn a tap into a valid capture.
struct DictationCapturePolicy {
    static let minimumCapture: TimeInterval = 0.75
    /// Push-to-talk holds already proved intent, so short replies ("Sí", "OK") are not dropped.
    static let minimumHoldCapture: TimeInterval = 0.25

    enum FinishDecision: Equatable {
        case cancel
        case stopAfterTail
    }

    static func finishDecision(
        captureStartedAt: Date?, now: Date, isHeld: Bool = false
    ) -> FinishDecision {
        let minimum = isHeld ? minimumHoldCapture : minimumCapture
        guard let captureStartedAt,
            now.timeIntervalSince(captureStartedAt) >= minimum
        else { return .cancel }
        return .stopAfterTail
    }
}

/// The relay also holds speech captured while the model loads. Its bound is
/// queued audio time; the chunk count is only a backstop.
enum DictationRelayPolicy {
    // Room for 30 s of 128-frame buffers at 48 kHz, so the time bound decides first.
    static let capacity = 16_384
    static let backlogLimit: TimeInterval = 30

    static func admits(
        _ result: AsyncStream<AudioChunk>.Continuation.YieldResult, chunk: AudioChunk
    ) -> Bool {
        guard case .enqueued(let remaining) = result else { return false }
        let queued = Double(capacity - remaining) * Double(chunk.samples.count) / chunk.sampleRate
        return queued <= backlogLimit
    }

    /// Frames a refused yield cost the session. A finished relay means it already ended.
    static func lostFrames(
        _ result: AsyncStream<AudioChunk>.Continuation.YieldResult, chunk: AudioChunk
    ) -> Int? {
        switch result {
        case .dropped(let evicted): evicted.samples.count
        case .enqueued: chunk.samples.count
        case .terminated: nil
        @unknown default: nil
        }
    }
}

enum DictationSessionError: LocalizedError {
    case unexpectedCompletion

    var errorDescription: String? {
        L10n.text("The dictation session ended unexpectedly. Nothing was typed.")
    }
}
