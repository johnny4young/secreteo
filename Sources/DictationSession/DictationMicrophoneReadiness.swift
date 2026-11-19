import MicCapture
import Foundation
import DictationKit
import SpeechCore

/// Session-owned first-frame admission and its bounded startup wait. Ready means
/// the first audible buffer, not the first buffer. Native cleanup stays with the
/// controller; this owner cannot release model leases.
@MainActor
final class DictationMicrophoneReadiness {
    /// About -80 dBFS: below any live microphone's noise floor, above digital silence.
    static let signalFloor: Float = 1e-4
    /// Outlasts a Bluetooth headset's switch to its call profile, so only a truly silent input waits this long.
    static let silentFallback: Double = 1.5

    private(set) var firstFrameAt: Date?
    private var hearsSignal = false
    private var silentSeconds: Double = 0
    private var accepting = true
    private var deadlineTask: Task<Void, Never>?
    private let now: () -> Date
    private let onReady: () -> Void
    private let onFailure: (Failure) -> Void

    enum Failure: Error {
        case permissionRequired
        case noAudio
        case invalidAudio
        case interrupted

        var message: String {
            switch self {
            case .permissionRequired:
                L10n.text("Allow microphone access in System Settings, then try dictation again.")
            case .noAudio:
                L10n.text("No microphone audio arrived. Check the microphone in Audio settings and try again.")
            case .invalidAudio:
                L10n.text("The microphone sent unusable audio. Check the input device and try again.")
            case .interrupted:
                L10n.text("Audio capture was interrupted. Nothing was inserted. Try dictating again.")
            }
        }
    }

    static func preparationMessage(for error: Error) -> String? {
        if let failure = error as? Failure { return failure.message }
        if case AudioCaptureError.noInputDevice = error {
            return L10n.text("No microphone is available. Choose an input in Audio settings and try again.")
        }
        return nil
    }

    init(now: @escaping () -> Date, onReady: @escaping () -> Void, onFailure: @escaping (Failure) -> Void) {
        self.now = now
        self.onReady = onReady
        self.onFailure = onFailure
    }

    func beginDeadline(wait: @escaping @Sendable () async throws -> Void) {
        deadlineTask = Task { [weak self] in
            do { try await wait() } catch { return }
            guard !Task.isCancelled, let self, accepting, firstFrameAt == nil else { return }
            reject(.noAudio)
        }
    }

    func finish() {
        accepting = false
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private func accept(arrivedAt: ContinuousClock.Instant, peak: Float, seconds: Double) -> Bool {
        guard accepting else { return false }
        if firstFrameAt == nil {
            // A main-actor stall before admission must not shorten the minimum capture.
            let lag = arrivedAt.duration(to: .now).components
            firstFrameAt = now().addingTimeInterval(-(Double(lag.seconds) + Double(lag.attoseconds) * 1e-18))
            deadlineTask?.cancel()
            deadlineTask = nil
        }
        if !hearsSignal {
            silentSeconds += seconds
            if peak > Self.signalFloor || silentSeconds >= Self.silentFallback {
                hearsSignal = true
                onReady()
            }
        }
        return true
    }

    private func reject(_ failure: Failure) {
        guard accepting else { return }
        finish()
        onFailure(failure)
    }

    private func rejectIfNoFirstFrame() {
        guard firstFrameAt == nil else { return }
        reject(.noAudio)
    }

    func failCapture() {
        reject(firstFrameAt == nil ? .noAudio : .interrupted)
    }

    func pump(
        stream: AsyncThrowingStream<AudioChunk, Error>,
        feed: AsyncStream<AudioChunk>.Continuation,
        mirror: @escaping @Sendable (AudioChunk) -> Void = { _ in },
        onInputEnded: @escaping @Sendable () async -> Void = {},
        onRelayDrop: @escaping @Sendable (Int) async -> Void = { _ in },
        updateMeter: @escaping @MainActor @Sendable (Float) -> Void
    ) -> Task<Void, Never> {
        Task.detached { [self] in
            do {
                for try await chunk in stream {
                    try Task.checkCancellation()
                    guard !chunk.samples.isEmpty else { continue }
                    let arrivedAt = ContinuousClock.now
                    guard chunk.channel == .microphone, chunk.sampleRate.isFinite, chunk.sampleRate > 0 else {
                        await reject(.invalidAudio)
                        break
                    }
                    var peak: Float = 0
                    for sample in chunk.samples {
                        guard sample.isFinite else {
                            await reject(.invalidAudio)
                            feed.finish()
                            return
                        }
                        peak = max(peak, abs(sample))
                    }
                    guard await accept(arrivedAt: arrivedAt, peak: peak, seconds: chunk.duration), !Task.isCancelled
                    else { break }
                    let relayed = feed.yield(chunk)
                    guard DictationRelayPolicy.admits(relayed, chunk: chunk) else {
                        if let lost = DictationRelayPolicy.lostFrames(relayed, chunk: chunk) { await onRelayDrop(lost) }
                        if !Task.isCancelled { await failCapture() }
                        feed.finish()
                        return
                    }
                    mirror(chunk)
                    await updateMeter(peak)
                }
            } catch {
                // An upstream CancellationError is not a user cancellation.
                if !Task.isCancelled { await failCapture() }
            }
            // A device can close or fail its stream before the deadline fires.
            // Finishing the feed alone would make the controller complete an
            // apparently successful, empty dictation without recovery guidance.
            await rejectIfNoFirstFrame()
            await onInputEnded()
            feed.finish()
        }
    }
}
