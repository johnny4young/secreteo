import Foundation
import os
import SpeechCore

/// Ends the stop tail early when the audio after the finish gesture is already silent.
/// Any sound above the room's level after the gesture keeps the full tail, so a last word
/// still being spoken is never cut.
final class DictationTrailingSilence: Sendable {
    /// Silence this long after the gesture ends the tail.
    static let required: TimeInterval = 0.1
    /// Sound twice the quietest stretch heard before the gesture counts as speech.
    static let floorMultiple: Float = 2
    /// Quiet enough on any microphone, for a session that never heard its room.
    static let absoluteQuiet: Float = 0.0015
    static let window: TimeInterval = 0.01

    private struct State {
        var floor: Float?
        var stopped = false
        var quiet: TimeInterval = 0
        var heardSound = false
        var silent = false
        var onSilence: (@Sendable () -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var isSilent: Bool { state.withLock { $0.silent } }

    /// Called from the capture pump; never blocks it.
    func offer(_ chunk: AudioChunk) {
        guard chunk.sampleRate > 0, !chunk.samples.isEmpty else { return }
        let loudness = Self.loudestWindow(chunk)
        let duration = Double(chunk.samples.count) / chunk.sampleRate
        let fire: (@Sendable () -> Void)? = state.withLock { state in
            guard state.stopped else {
                if loudness > 0 { state.floor = min(state.floor ?? loudness, loudness) }
                return nil
            }
            guard !state.heardSound, !state.silent else { return nil }
            let threshold = max(Self.absoluteQuiet, (state.floor ?? 0) * Self.floorMultiple)
            guard loudness <= threshold else {
                state.heardSound = true
                return nil
            }
            state.quiet += duration
            guard state.quiet >= Self.required else { return nil }
            state.silent = true
            defer { state.onSilence = nil }
            return state.onSilence
        }
        fire?()
    }

    /// Audio offered from now on is the tail.
    func finishRequested() {
        state.withLock { $0.stopped = true }
    }

    /// Runs once the tail is silent, at once if it already is.
    func onSilence(_ action: @escaping @Sendable () -> Void) {
        let now = state.withLock { state in
            if state.silent { return true }
            state.onSilence = action
            return false
        }
        if now { action() }
    }

    /// The loudest 10 ms, so a short sound inside a long buffer still counts.
    static func loudestWindow(_ chunk: AudioChunk) -> Float {
        let size = max(1, Int(chunk.sampleRate * window))
        var loudest: Float = 0
        var start = chunk.samples.startIndex
        while start < chunk.samples.endIndex {
            let end = min(start + size, chunk.samples.endIndex)
            var sum: Float = 0
            for sample in chunk.samples[start..<end] { sum += sample * sample }
            loudest = max(loudest, (sum / Float(end - start)).squareRoot())
            start = end
        }
        return loudest
    }
}
