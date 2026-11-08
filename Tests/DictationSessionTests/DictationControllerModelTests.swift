import Foundation
import LiveSpeech
import LocalModelStore
import os
import XCTest

@testable import DictationSession

@MainActor
final class DictationControllerModelTests: XCTestCase {
    struct Cell: Encodable {
        let caseID: String
        let audioSHA256: String
        let group: String
        let cohort: String
        let shape: String
        let split: String
        let critical: Bool
        let pass: Int
        let repetitions: Int
        let inputSeconds: Double
        let runtimeState: String
        let proposedOutputScore: DictationModelProbe.Score
        let controller: DictationSessionMeasurement
        let footprint: DictationFootprintObservation.Receipt
        let inputCompleted: Bool
        let fedFrames: Int
        let pipelineCompleted: Bool
        let work: [ParakeetLiveWorkSample]
    }

    struct Receipt: Encodable {
        let kind = "dictation-controller-model-observation"
        let schemaVersion = 1
        let corpusSHA256 = DictationModelFixture.sourceDigest
        let manifestSHA256: String
        let modelID: String
        let modelRevision: String
        let modelVerificationSeconds: Double
        let modelLoadSeconds: Double
        let modelLoadAttempts: Int
        let loadState = "lazy-shared-engine-uncontrolled-coreml-disk-cache"
        let localeMode = "automatic-literal-no-vocabulary"
        let feed = "realtime-100ms-public-pcm-controller-stop"
        let evaluationTarget = "proposed-output-including-cancelled-and-failed-attempts"
        let qualityMeasured = true
        let controllerMeasured = true
        let verifiedDeliveryMeasured = false
        let platformChecksMeasured = false
        let memoryMeasured = true
        let memoryScope = "sampled-whole-xctest-process-not-allocation-attribution"
        let backendWindowFailureCoverageMeasured = false
        let repetitions: Int
        let cells: [Cell]
    }

    func testInstalledParakeetThroughControllerOnExplicitPublicCells() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SECRETEO_DICTATION_CONTROLLER"] == "1",
              let audio = environment["SECRETEO_DICTATION_BASELINE_AUDIO"] else {
            throw XCTSkip("explicit installed-model controller observation not requested")
        }
        #if DEBUG
        XCTFail("Real controller model observations require Release to contain vendor diagnostics")
        #else
        do {
            guard let ids = environment["SECRETEO_DICTATION_BASELINE_CASES"],
                  let output = environment["SECRETEO_DICTATION_BASELINE_OUTPUT"], output.hasPrefix("/"),
                  !FileManager.default.fileExists(atPath: output),
                  let repetitions = Int(environment["SECRETEO_DICTATION_REPETITIONS"] ?? "1"),
                  (1...12).contains(repetitions) else { throw DictationModelProbe.Failure.invalidInput }
            let fixture = try DictationModelFixture(
                audioRoot: URL(fileURLWithPath: audio), selectedIDs: ids.components(separatedBy: ","))
            for id in fixture.selectedIDs { _ = try fixture.sequence(id, repetitions: repetitions) }
            guard let models = environment["SECRETEO_DICTATION_BASELINE_MODELS"], models.hasPrefix("/") else {
                throw DictationModelProbe.Failure.invalidInput
            }
            let store = try LocalModelStore(
                location: .directory(URL(fileURLWithPath: models, isDirectory: true)),
                consumer: StoreConsumer(bundleID: "com.example.secreteo-tests", displayName: "Secreteo tests"))
            if environment["SECRETEO_DICTATION_BASELINE_INSTALL"] == "1" {
                _ = try await store.ensureAvailable(ModelCatalog.parakeetTdtV3)
            }
            let start = ContinuousClock.now
            guard let installation = await store.verifiedInstallation(ModelCatalog.parakeetTdtV3) else {
                throw DictationModelProbe.Failure.invalidInput
            }
            let verification = DictationModelProbe.seconds(start.duration(to: .now))
            let runtime = Runtime(directory: installation.directory)
            var cells: [Cell] = []
            for pass in 1...2 {
                for id in fixture.selectedIDs {
                    cells.append(try await observe(id, pass: pass, repetitions: repetitions, fixture: fixture, runtime: runtime))
                }
            }
            try PrivateJSONWriter.write(Receipt(
                manifestSHA256: fixture.manifestDigest, modelID: installation.manifestID,
                modelRevision: installation.manifestRevision, modelVerificationSeconds: verification,
                modelLoadSeconds: runtime.loadSeconds, modelLoadAttempts: runtime.freshRequests, repetitions: repetitions, cells: cells),
                to: URL(fileURLWithPath: output))
        } catch {
            XCTFail("controller model observation did not complete; no qualified receipt")
        }
        #endif
    }

    private func observe(
        _ id: String, pass: Int, repetitions: Int, fixture: DictationModelFixture, runtime: Runtime
    ) async throws -> Cell {
        let sequence = try fixture.sequence(id, repetitions: repetitions)
        let family = sequence.family
        // Reuse is what the controller recorded, as the validator reads it, not what the cache holds.
        let state = runtime.ready ? "reused-engine" : "first-engine-load"
        if !runtime.ready { runtime.freshRequests += 1 }
        let samples = OSAllocatedUnfairLock<[ParakeetLiveWorkSample]>(initialState: [])
        let result = try await DictationControllerModelProbe.run(samples: sequence.samples, acquireRuntime: {
            let engine = try await runtime.acquire()
            return LiveTranscriptionRuntime(engine: engine.observingLiveWork { value in
                samples.withLock { $0.append(value) }
            }, completion: {})
        })
        if result.measurement.elapsedSeconds["runtimeReady"] != nil { runtime.ready = true }
        let observations = samples.withLock { $0 }
        guard observations.count <= 1 else { throw DictationModelProbe.Failure.invalidInput }
        let pipelineCompleted = result.inputCompleted && result.frames == sequence.samples.count
            && [.empty, .deliveryRejected].contains(result.measurement.outcome)
            && observations.first.map {
                $0.valid && $0.outcome == .completed && $0.inputFrames == sequence.samples.count
                    && $0.rejectedBuffers == 0 && $0.finishCalls == 1
                    && $0.inputChunks == (sequence.samples.count + 1_599) / 1_600
            } == true
        return Cell(
            caseID: id, audioSHA256: sequence.entry.audioSHA256, group: family.group,
            cohort: family.cohort, shape: family.shape, split: family.split, critical: family.critical,
            pass: pass, repetitions: repetitions, inputSeconds: Double(sequence.samples.count) / 16_000, runtimeState: state,
            proposedOutputScore: try DictationModelProbe.score(
                hypothesis: result.proposedText, legacyCleanedText: result.proposedText, references: sequence.references),
            controller: result.measurement, footprint: result.footprint, inputCompleted: result.inputCompleted,
            fedFrames: result.frames, pipelineCompleted: pipelineCompleted, work: observations)
    }

    /// A cancelled cell's cold load runs on and the next cell joins it, so loads never overlap.
    @MainActor
    private final class Runtime {
        private let shared: DictationSharedModelLoad<ParakeetEngine>
        var ready = false
        var freshRequests = 0
        var loadSeconds: Double { shared.waitSeconds }

        init(directory: URL) {
            shared = DictationSharedModelLoad { try await ParakeetEngine.load(fromVerifiedDirectory: directory) }
        }

        func acquire() async throws -> ParakeetEngine { try await shared.acquire() }
    }

}
