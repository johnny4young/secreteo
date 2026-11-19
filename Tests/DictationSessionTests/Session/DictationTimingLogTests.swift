import Foundation
import MicCapture
import SpeechCore
import XCTest

@testable import DictationSession

@MainActor
final class DictationTimingLogTests: XCTestCase {
    private let devIdentity = "com.johnny4young.secreteo.dev"

    func testOnlyAnAbsolutePathOutsideTheShippedIdentityOpensTheLog() {
        let path = "/private/tmp/timing.jsonl"
        XCTAssertEqual(DictationTimingLog(
            arguments: ["app", "-dictation-timing-log", path], bundleIdentifier: devIdentity)?.url.path, path)
        XCTAssertNotNil(DictationTimingLog(arguments: ["-dictation-timing-log", path], bundleIdentifier: nil))
        XCTAssertEqual(DictationTimingLog.shippedIdentity, "com.johnny4young.secreteo")
        XCTAssertNil(DictationTimingLog(
            arguments: ["-dictation-timing-log", path], bundleIdentifier: DictationTimingLog.shippedIdentity))
        XCTAssertNil(DictationTimingLog(arguments: ["-dictation-timing-log", "timing.jsonl"], bundleIdentifier: devIdentity))
        XCTAssertNil(DictationTimingLog(arguments: ["-dictation-timing-log", "/private/tmp/"], bundleIdentifier: devIdentity))
        XCTAssertNil(DictationTimingLog(arguments: ["-dictation-timing-log"], bundleIdentifier: devIdentity))
        XCTAssertNil(DictationTimingLog(arguments: ["app"], bundleIdentifier: devIdentity))
    }

    func testDeliveredSessionAppendsOneOwnerOnlyLineWithoutItsWords() async throws {
        let text = "Never write this sentence to the timing log"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("timing.jsonl")
        let log = try XCTUnwrap(DictationTimingLog(
            arguments: ["-dictation-timing-log", file.path], bundleIdentifier: devIdentity))

        for _ in 0..<2 {
            let harness = DictationControllerHarness(text: text)
            harness.lane = .parakeetUltra
            var dependencies = harness.dependencies
            dependencies.measurementSink = nil
            dependencies.timingLog = { log.append($0) }
            harness.controller.toggle(using: dependencies)
            await eventually { !harness.controller.partialText.isEmpty }
            harness.now = harness.now.addingTimeInterval(1)
            harness.controller.toggle(using: dependencies)
            await eventually { harness.insertions == [text] }
            harness.controller.cancel()
        }
        log.flush()

        let data = try Data(contentsOf: file)
        XCTAssertNil(String(data: data, encoding: .utf8)?.range(of: "timing log"))
        let lines = data.split(separator: 0x0A)
        XCTAssertEqual(lines.count, 2)
        let record = try JSONDecoder().decode(DictationSessionTimingRecord.self, from: Data(lines[0]))
        XCTAssertEqual(record.schemaVersion, 2)
        XCTAssertEqual(record.startedAt, 1_000)
        XCTAssertEqual(record.admission, "global")
        XCTAssertEqual(record.engine, "parakeetUltra")
        XCTAssertEqual(record.session.outcome, .dispatchReported)
        XCTAssertNotNil(record.session.elapsedSeconds["firstCaptionHandled"])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0])) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys), ["schemaVersion", "startedAt", "admission", "engine", "session", "audio", "diagnostics"])
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testRecordCarriesTheCaptureCountsAndTheOrdinarySinkStaysUnchanged() async throws {
        let harness = DictationControllerHarness(text: "Counted frames")
        var records: [DictationSessionTimingRecord] = []
        var dependencies = harness.dependencies
        let report = CaptureChannelReport(
            channel: .microphone, acceptedFrames: 48_000, paddingFrames: 1_600, rejectedFrames: 0)
        dependencies.makeMicrophone = { [microphone = harness.microphone] in
            .init(source: ReportingMicrophone(ControlledMicrophoneSession(microphone), report: report), warmUp: {})
        }
        dependencies.timingLog = { records.append($0) }
        harness.controller.toggle(using: dependencies)
        await eventually { !harness.controller.partialText.isEmpty }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)
        await eventually { records.count == 1 }
        harness.controller.cancel()

        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.audio.acceptedFrames, 48_000)
        XCTAssertEqual(record.audio.paddingFrames, 1_600)
        XCTAssertEqual(record.audio.lostFrames, 1_600)
        XCTAssertEqual(record.audio.relayDroppedChunks, 0)
        XCTAssertEqual(harness.measurements, [record.session], "The test sink sees the same receipt, unchanged")
    }

    func testAudioTheRelayCouldNotHoldIsCountedAsLost() async throws {
        let harness = DictationControllerHarness(text: "Too much pre-roll")
        let gate = PreparationGate()
        var records: [DictationSessionTimingRecord] = []
        var dependencies = harness.dependencies
        let load = dependencies.acquireRuntime
        dependencies.acquireRuntime = {
            await gate.wait()
            return try await load()
        }
        dependencies.timingLog = { records.append($0) }
        harness.controller.toggle(using: dependencies)
        await eventually { harness.controller.phase == .listening }
        for _ in 0...Int(DictationRelayPolicy.backlogLimit) {
            await harness.microphone.send(AudioChunk(
                channel: .microphone, samples: [Float](repeating: 0.25, count: 16_000),
                sampleRate: 16_000, timestamp: 0))
        }
        await eventually { records.count == 1 }
        gate.release()
        harness.controller.cancel()

        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.session.outcome, .pipelineFailed)
        XCTAssertEqual(record.audio.relayDroppedChunks, 1)
        XCTAssertEqual(record.audio.relayDroppedFrames, 16_000)
        XCTAssertNil(record.engine, "The model never became ready")
    }

    func testRecordExplainsTheMicrophoneTheFirstSoundAndTheTail() async throws {
        let harness = DictationControllerHarness(text: "Diagnosed")
        var records: [DictationSessionTimingRecord] = []
        var dependencies = harness.dependencies
        let make = dependencies.makeMicrophone
        dependencies.makeMicrophone = {
            var input = make()
            input.transport = .builtIn
            input.replacesBluetooth = true
            return input
        }
        dependencies.timingLog = { records.append($0) }
        harness.controller.toggle(using: dependencies)
        await eventually { !harness.controller.partialText.isEmpty }
        harness.now = harness.now.addingTimeInterval(1)
        harness.controller.toggle(using: dependencies)
        await eventually { records.count == 1 }
        harness.controller.cancel()

        let diagnostics = try XCTUnwrap(records.first?.diagnostics)
        XCTAssertEqual(diagnostics.inputTransport, .builtIn)
        XCTAssertTrue(diagnostics.replacedBluetooth)
        XCTAssertNotNil(diagnostics.firstAudibleSeconds)
        XCTAssertNotNil(diagnostics.tail)
    }

    func testDigitalSilenceIsNotTheFirstSound() throws {
        let start = ContinuousClock.now
        var now = start
        var record: DictationSessionTimingRecord?
        let recorder = DictationSessionMeasurementRecorder(now: { now }, sink: nil, recordSink: { record = $0 })
        recorder.noteBuffer(peak: 0)
        now = start.advanced(by: .milliseconds(300))
        recorder.noteBuffer(peak: DictationSessionDiagnostics.audiblePeak)
        now = start.advanced(by: .milliseconds(450))
        recorder.noteBuffer(peak: 0.02)
        now = start.advanced(by: .milliseconds(600))
        recorder.noteBuffer(peak: 0.5)
        recorder.finish(.empty)

        let first = try XCTUnwrap(record?.diagnostics.firstAudibleSeconds)
        XCTAssertEqual(first, 0.45, accuracy: 1e-9, "Zeros are a device not yet delivering sound")
    }

    func testUnobservedSessionBuildsNoRecorder() {
        var dependencies = DictationControllerHarness(text: "Unobserved").dependencies
        dependencies.measurementSink = nil
        XCTAssertNil(DictationSessionMeasurementRecorder.make(for: dependencies))
        dependencies.timingLog = { _ in }
        XCTAssertNotNil(DictationSessionMeasurementRecorder.make(for: dependencies))
    }

    private func eventually(
        _ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async {
        _ = await TestPolling.until(condition)
        XCTAssertTrue(condition(), "The session did not reach the expected state", file: file, line: line)
    }
}

/// Stands in for a capture that inserted padding over a device gap.
private actor ReportingMicrophone: CaptureReportingSource {
    nonisolated let channel = AudioChannel.microphone
    private let wrapped: ControlledMicrophoneSession
    nonisolated let captureReport: CaptureChannelReport

    init(_ wrapped: ControlledMicrophoneSession, report: CaptureChannelReport) {
        self.wrapped = wrapped
        captureReport = report
    }

    nonisolated func setCaptureFailureHandler(_ handler: @escaping @Sendable () -> Void) {
        wrapped.setCaptureFailureHandler(handler)
    }

    func start() async throws -> AsyncThrowingStream<AudioChunk, Error> { try await wrapped.start() }
    func stop() async { await wrapped.stop() }
}
