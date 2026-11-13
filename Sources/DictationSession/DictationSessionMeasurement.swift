import Foundation
import DictationKit
import MicCapture
import SpeechCore

/// Developer-requested, content-free observation of the controller, not a claim
/// about microphone hardware, ASR quality or text verified in another process.
struct DictationSessionMeasurement: Codable, Equatable, Sendable {
    enum Point: String, Codable, CaseIterable, Sendable {
        case runtimeReady
        case microphoneReady
        case firstBufferHandled
        case firstCaptionHandled
        case stopRequested
        case inputEnded
        case transcriptionEnded
        case textPrepared
        case deliveryStarted
        case deliveryReturned
    }

    enum Outcome: String, Codable, Sendable {
        case permissionDenied
        case cancelled
        case pipelineFailed
        case empty
        case noSpeech
        // This observer records the controller port, not native verification evidence.
        case dispatchReported
        case deliveryRejected
    }

    let schemaVersion: Int
    let elapsedSeconds: [String: Double]
    let terminalSeconds: Double
    let outcome: Outcome
    let verifiedDeliveryMeasured: Bool
}

/// Frame counts for one session. Nil means the source cannot prove the count.
struct DictationSessionAudioCounts: Codable, Equatable, Sendable {
    var acceptedFrames: Int64?
    /// Silence the capture inserted over a device gap: audio that never arrived.
    var paddingFrames: Int64?
    var rejectedFrames: Int64?
    /// Audio the relay to the model could not keep, which also fails the session.
    var relayDroppedChunks = 0
    var relayDroppedFrames: Int64 = 0
    var captureFailure: CaptureFailure?

    var lostFrames: Int64? {
        guard let paddingFrames, let rejectedFrames else { return nil }
        return paddingFrames + rejectedFrames + relayDroppedFrames
    }
}

/// One line of the timing log: times, counts and an outcome, never audio or text.
struct DictationSessionTimingRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    /// Wall clock at the start, so an outside observer can line sessions up with its own events.
    let startedAt: Double
    let admission: String
    let engine: String?
    let session: DictationSessionMeasurement
    let audio: DictationSessionAudioCounts
}

/// One bounded accumulator per observed session. Retired tasks may retain it,
/// but cannot amend or emit a second receipt after cancellation/restart.
@MainActor
final class DictationSessionMeasurementRecorder {
    typealias Clock = () -> ContinuousClock.Instant
    typealias Sink = (DictationSessionMeasurement) -> Void
    typealias RecordSink = (DictationSessionTimingRecord) -> Void

    private let now: Clock
    private var sink: Sink?
    private var recordSink: RecordSink?
    private let started: ContinuousClock.Instant
    private let startedAt: Date
    private let admission: String
    private var points: [String: Double] = [:]
    private var audio = DictationSessionAudioCounts()
    private var engine: String?
    private var captureReport: (@Sendable () -> CaptureChannelReport)?

    init(
        now: @escaping Clock, sink: Sink?, recordSink: RecordSink? = nil,
        startedAt: Date = Date(), admission: String = "global"
    ) {
        self.now = now
        self.sink = sink
        self.recordSink = recordSink
        self.startedAt = startedAt
        self.admission = admission
        started = now()
    }

    /// Nil when nobody asked to observe this session.
    static func make(for dependencies: DictationSessionDependencies) -> DictationSessionMeasurementRecorder? {
        guard dependencies.measurementSink != nil || dependencies.timingLog != nil else { return nil }
        return DictationSessionMeasurementRecorder(
            now: dependencies.measurementClock, sink: dependencies.measurementSink,
            recordSink: dependencies.timingLog, startedAt: dependencies.now(),
            admission: dependencies.admissionKind == .practice ? "practice" : "global")
    }

    private var isOpen: Bool { sink != nil || recordSink != nil }

    func record(_ point: DictationSessionMeasurement.Point) {
        guard isOpen, points[point.rawValue] == nil else { return }
        points[point.rawValue] = elapsed()
    }

    func observeCapture(_ source: any AudioCaptureSource) {
        guard isOpen, let reporting = source as? any CaptureReportingSource else { return }
        captureReport = { reporting.captureReport }
    }

    func noteEngine(_ lane: String) {
        guard isOpen else { return }
        engine = lane
    }

    func noteRelayDrop(frames: Int) {
        guard isOpen else { return }
        audio.relayDroppedChunks += 1
        audio.relayDroppedFrames += Int64(frames)
    }

    func finish(_ outcome: DictationSessionMeasurement.Outcome) {
        guard isOpen else { return }
        let measurement = DictationSessionMeasurement(
            schemaVersion: 1, elapsedSeconds: points, terminalSeconds: elapsed(),
            outcome: outcome, verifiedDeliveryMeasured: false)
        let sink = sink, recordSink = recordSink
        self.sink = nil
        self.recordSink = nil
        sink?(measurement)
        guard let recordSink else { return }
        var audio = audio
        if let report = captureReport?() {
            audio.acceptedFrames = report.acceptedFrames
            audio.paddingFrames = report.paddingFrames
            audio.rejectedFrames = report.rejectedFrames
            audio.captureFailure = report.failure
        }
        recordSink(DictationSessionTimingRecord(
            schemaVersion: DictationSessionTimingRecord.currentSchemaVersion,
            startedAt: startedAt.timeIntervalSince1970, admission: admission, engine: engine,
            session: measurement, audio: audio))
    }

    func finishDelivery(_ result: DictationDeliveryOutcome) {
        record(.deliveryReturned)
        switch result {
        case .verified, .dispatched: finish(.dispatchReported)
        case .refused(.cancelled): finish(.cancelled)
        default: finish(.deliveryRejected)
        }
    }

    private func elapsed() -> Double {
        let value = started.duration(to: now()).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}
