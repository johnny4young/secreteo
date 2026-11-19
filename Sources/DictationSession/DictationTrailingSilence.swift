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
    /// A session that talked the whole time learned speech, not its room, so quiet stays below this.
    static let loudestQuiet: Float = 0.01
    static let window: TimeInterval = 0.01

    private struct State {
        var floor: Float?
        /// Audio offered so far and when, so the gesture can be placed in audio time.
        var offeredEnd: TimeInterval = 0
        var offeredAt: ContinuousClock.Instant?
        var gestureAt: TimeInterval?
        var quiet: TimeInterval = 0
        var heardSound = false
        var silent = false
        var onSilence: (@Sendable () -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let now: @Sendable () -> ContinuousClock.Instant

    init(now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    var isSilent: Bool { state.withLock { $0.silent } }

    /// Called from the capture pump; never blocks it.
    func offer(_ chunk: AudioChunk) {
        guard chunk.sampleRate > 0, !chunk.samples.isEmpty else { return }
        let loudness = Self.loudestWindow(chunk)
        let start = chunk.timestamp
        let end = start + Double(chunk.samples.count) / chunk.sampleRate
        let instant = now()
        let fire: (@Sendable () -> Void)? = state.withLock { state in
            defer {
                state.offeredEnd = max(state.offeredEnd, end)
                state.offeredAt = instant
            }
            guard let gestureAt = state.gestureAt else {
                if loudness > 0 { state.floor = min(state.floor ?? loudness, loudness) }
                return nil
            }
            // A restarted stream pads with zeros, which says nothing about the room.
            guard !state.heardSound, !state.silent, loudness > 0 else { return nil }
            let threshold = max(Self.absoluteQuiet, min(Self.loudestQuiet, (state.floor ?? 0) * Self.floorMultiple))
            guard loudness <= threshold else {
                state.heardSound = true
                return nil
            }
            // Audio still in flight at the gesture was spoken before it.
            state.quiet += max(0, end - max(start, gestureAt))
            guard state.quiet >= Self.required else { return nil }
            state.silent = true
            defer { state.onSilence = nil }
            return state.onSilence
        }
        fire?()
    }

    /// Audio offered from now on is the tail.
    func finishRequested() {
        let instant = now()
        state.withLock { state in
            let pending = state.offeredAt.map { instant - $0 } ?? .zero
            let seconds = Double(pending.components.seconds) + Double(pending.components.attoseconds) * 1e-18
            state.gestureAt = state.offeredEnd + seconds
        }
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

    /// The loudest 10 ms, so a short sound inside a long buffer still counts. A short
    /// remainder joins the window before it, so a few samples never stand for 10 ms.
    static func loudestWindow(_ chunk: AudioChunk) -> Float {
        let size = max(1, Int(chunk.sampleRate * window))
        let count = chunk.samples.count
        let windows = max(1, count / size)
        var loudest: Float = 0
        for index in 0..<windows {
            let start = chunk.samples.startIndex + index * size
            let end = index == windows - 1 ? chunk.samples.endIndex : start + size
            var sum: Float = 0
            for sample in chunk.samples[start..<end] { sum += sample * sample }
            loudest = max(loudest, (sum / Float(end - start)).squareRoot())
        }
        return loudest
    }
}
