import CoreML
import FluidAudio
import Foundation
import LocalModelStore
import SpeechCore

public enum VoiceActivityDetectionError: Error, Sendable {
    case modelNotInstalled
    case invalidAudio
    case wrongChannel
    case invalidModelOutput
    case concurrentUse
}

public struct VoiceActivityObservation: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case speechStart(TimeInterval)
        case speechEnd(TimeInterval)
    }

    public let frameStart: TimeInterval
    public let frameEnd: TimeInterval
    public let speechProbability: Float
    public let isSpeechActive: Bool
    public let event: Event?
}

public struct VoiceActivityBatch: Sendable {
    /// A rate change or missing/out-of-order source audio invalidates the old
    /// model context. Callers must also clear any silence countdown.
    public let didResetForDiscontinuity: Bool
    public let observations: [VoiceActivityObservation]
}

/// Loaded, leased Silero Core ML weights shared across per-session detectors.
/// `VadManager` is an actor and `VadStreamState` lives per detector, so one loaded
/// model serves both speech gating and auto-stop and stays warm between dictations.
public final class SileroVoiceActivityModel: Sendable {
    private let modelLease: LocalModelStore.ModelLease
    private let infer: SileroVoiceActivityDetector.Inference

    public static func load(
        from store: LocalModelStore,
        computeUnits: MLComputeUnits = .cpuOnly
    ) async throws -> SileroVoiceActivityModel {
        try await loadLeased(from: store, manifest: ModelCatalog.sileroVAD) { directory in
            let url = directory.appendingPathComponent(ModelCatalog.sileroVADBundleDirectory, isDirectory: true)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = computeUnits
            let model = try await MLModel.load(contentsOf: url, configuration: configuration)
            let manager = VadManager(config: VadConfig(computeUnits: computeUnits), vadModel: model)
            return { frame, state in try await manager.processStreamingChunk(frame, state: state) }
        }
    }

    static func loadLeased(
        from store: LocalModelStore, manifest: ModelManifest,
        prepare: @Sendable (URL) async throws -> SileroVoiceActivityDetector.Inference
    ) async throws -> SileroVoiceActivityModel {
        let lease: LocalModelStore.ModelLease
        do {
            lease = try await store.lease(manifest)
        } catch LocalModelStore.LocalModelStoreError.notInstalled {
            throw VoiceActivityDetectionError.modelNotInstalled
        }
        try Task.checkCancellation()
        let infer = try await prepare(lease.directory)
        try Task.checkCancellation()
        return SileroVoiceActivityModel(modelLease: lease, infer: infer)
    }

    init(modelLease: LocalModelStore.ModelLease, infer: @escaping SileroVoiceActivityDetector.Inference) {
        self.modelLease = modelLease
        self.infer = infer
    }

    /// Captures `self` inside the inference closure so the store lease outlives
    /// both the detector and any in-flight inference even after a warm cache drops it.
    public func makeDetector(channel: AudioChannel) -> SileroVoiceActivityDetector {
        SileroVoiceActivityDetector(channel: channel) { [self] frame, state in
            try await self.infer(frame, state)
        }
    }
}

/// Recording/dictation-scoped Silero stream over mono capture chunks. A caller
/// consumes this actor from an off-callback task; it never edits or gates the
/// original capture stream. The model is loaded only from ModelStore's fully
/// verified installation and never through FluidAudio's downloading ModelHub.
public actor SileroVoiceActivityDetector {
    typealias Inference = @Sendable ([Float], VadStreamState) async throws -> VadStreamResult

    private static let sampleRate = Double(VadManager.sampleRate)
    private static let frameSize = VadManager.chunkSize
    private static let maximumInputSamples = 262_144
    // Twice the input cap, plus the streaming carry, admits 8 kHz upsampling.
    private static let maximumOutputSamples = 2 * maximumInputSamples + 1
    // Host timestamps mark the source frame, not callback arrival. A missing
    // 512-sample packet at 16 kHz is 32 ms; it must not look continuous to an
    // eventual silence-stop consumer.
    private static let continuityTolerance: TimeInterval = 0.002

    private let channel: AudioChannel
    private let infer: Inference
    private var resampler = StreamingLinearResampler()
    private var modelState = VadStreamState.initial()
    private var pending: [Float] = []
    private var baseTimestamp: TimeInterval?
    private var expectedTimestamp: TimeInterval?
    private var sourceRate: Double?
    private var isProcessing = false

    /// No implicit download: the user-facing model setup must explicitly call
    /// ModelStore.ensureAvailable after consent before this loader can succeed.
    public static func load(
        from store: LocalModelStore,
        channel: AudioChannel,
        computeUnits: MLComputeUnits = .cpuOnly
    ) async throws -> SileroVoiceActivityDetector {
        let model = try await SileroVoiceActivityModel.load(from: store, computeUnits: computeUnits)
        return model.makeDetector(channel: channel)
    }

    static func loadLeased(
        from store: LocalModelStore, manifest: ModelManifest, channel: AudioChannel,
        prepare: @Sendable (URL) async throws -> Inference
    ) async throws -> SileroVoiceActivityDetector {
        let model = try await SileroVoiceActivityModel.loadLeased(from: store, manifest: manifest, prepare: prepare)
        return model.makeDetector(channel: channel)
    }

    init(channel: AudioChannel, infer: @escaping Inference) {
        self.channel = channel
        self.infer = infer
    }

    /// One ordered producer owns each detector. Reentrant concurrent calls
    /// fail rather than interleaving explicit Silero state across audio chunks.
    public func process(_ chunk: AudioChunk) async throws -> VoiceActivityBatch {
        guard !isProcessing else { throw VoiceActivityDetectionError.concurrentUse }
        isProcessing = true
        defer { isProcessing = false }

        guard chunk.channel == channel else { throw VoiceActivityDetectionError.wrongChannel }
        let duration = try Self.validatedDuration(of: chunk)
        guard !chunk.samples.isEmpty else {
            return VoiceActivityBatch(
                didResetForDiscontinuity: false, observations: [])
        }

        let rateChanged = sourceRate.map { $0 != chunk.sampleRate } ?? false
        let timeChanged = expectedTimestamp.map {
            abs($0 - chunk.timestamp) > Self.continuityTolerance
        } ?? false
        let discontinuity = rateChanged || timeChanged
        var nextResampler = discontinuity ? StreamingLinearResampler() : resampler
        let nextState = discontinuity ? VadStreamState.initial() : modelState
        var nextPending = discontinuity ? [] : pending
        let nextBase = discontinuity ? chunk.timestamp : (baseTimestamp ?? chunk.timestamp)

        let outputBound = (Double(chunk.samples.count) * Self.sampleRate / chunk.sampleRate)
            .rounded(.down) + 1
        guard outputBound <= Double(Self.maximumOutputSamples) else {
            throw VoiceActivityDetectionError.invalidAudio
        }
        let converted: [Float]
        do {
            converted = try nextResampler.resample(
                chunk.samples, from: chunk.sampleRate, to: Self.sampleRate,
                maximumOutputSamples: Int(outputBound))
        } catch {
            throw VoiceActivityDetectionError.invalidAudio
        }
        nextPending.append(contentsOf: converted)
        let processed = try await inferCompleteFrames(
            nextPending, state: nextState, baseTimestamp: nextBase)

        resampler = nextResampler
        modelState = processed.state
        pending = processed.remaining
        baseTimestamp = nextBase
        expectedTimestamp = chunk.timestamp + duration
        sourceRate = chunk.sampleRate
        return VoiceActivityBatch(
            didResetForDiscontinuity: discontinuity,
            observations: processed.observations)
    }

    private static func validatedDuration(of chunk: AudioChunk) throws -> TimeInterval {
        guard chunk.sampleRate.isFinite, chunk.sampleRate > 0,
              chunk.timestamp.isFinite, chunk.timestamp >= 0,
              chunk.samples.count <= maximumInputSamples,
              chunk.samples.allSatisfy(\.isFinite)
        else { throw VoiceActivityDetectionError.invalidAudio }
        guard !chunk.samples.isEmpty else { return 0 }
        let duration = Double(chunk.samples.count) / chunk.sampleRate
        guard duration.isFinite, duration > 0,
              (chunk.timestamp + duration).isFinite
        else { throw VoiceActivityDetectionError.invalidAudio }
        return duration
    }

    private func inferCompleteFrames(
        _ samples: [Float],
        state initialState: VadStreamState,
        baseTimestamp: TimeInterval
    ) async throws -> (
        remaining: [Float], state: VadStreamState,
        observations: [VoiceActivityObservation]
    ) {
        var state = initialState
        var observations: [VoiceActivityObservation] = []
        var consumed = 0
        while samples.count - consumed >= Self.frameSize {
            try Task.checkCancellation()
            let frame = Array(samples[consumed..<(consumed + Self.frameSize)])
            let result = try await infer(frame, state)
            try Task.checkCancellation()
            guard result.probability.isFinite,
                  (0...1).contains(result.probability),
                  result.state.processedSamples
                    == state.processedSamples + Self.frameSize,
                  result.event.map({
                      $0.sampleIndex >= 0
                          && $0.sampleIndex <= result.state.processedSamples
                  }) ?? true
            else { throw VoiceActivityDetectionError.invalidModelOutput }
            let start = baseTimestamp + Double(state.processedSamples) / Self.sampleRate
            let end = baseTimestamp + Double(result.state.processedSamples) / Self.sampleRate
            guard start.isFinite, end.isFinite else {
                throw VoiceActivityDetectionError.invalidAudio
            }
            let event: VoiceActivityObservation.Event? = result.event.map { signal in
                let time = baseTimestamp + Double(signal.sampleIndex) / Self.sampleRate
                switch signal.kind {
                case .speechStart: return .speechStart(time)
                case .speechEnd: return .speechEnd(time)
                }
            }
            observations.append(VoiceActivityObservation(
                frameStart: start,
                frameEnd: end,
                speechProbability: result.probability,
                isSpeechActive: result.state.triggered,
                event: event))
            state = result.state
            consumed += Self.frameSize
        }
        return (Array(samples.dropFirst(consumed)), state, observations)
    }
}
