import Foundation
import os
import DictationKit
import LocalModelStore
import SpeechCore
import Synchronization
import XCTest

@testable import DictationSession
@testable import LiveSpeech
@testable import DictationKit

final class DictationSpeechGateTests: XCTestCase {
    private func chunk(_ index: Int = 0) -> AudioChunk {
        AudioChunk(channel: .microphone, samples: [Float](repeating: 0.1, count: 4_096),
                   sampleRate: 16_000, timestamp: Double(index) * 0.256)
    }

    func testCompletePassWithoutSpeechIsNoSpeech() async {
        let gate = DictationSpeechGate { { _ in false } }
        for index in 0..<10 { gate.offer(chunk(index)) }
        let verdict = await gate.verdict(within: .seconds(2))
        XCTAssertEqual(verdict, .noSpeech)
    }

    func testFirstSpeechDecidesAndLaterAudioIsNotAnalyzed() async {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let gate = DictationSpeechGate {
            { _ in calls.withLock { $0 += 1; return $0 == 3 } }
        }
        for index in 0..<3 { gate.offer(chunk(index)) }
        let speech = await waitUntil { calls.withLock { $0 } == 3 }
        XCTAssertTrue(speech)
        for index in 3..<20 { gate.offer(chunk(index)) }
        let verdict = await gate.verdict(within: .seconds(2))
        XCTAssertEqual(verdict, .speech)
        XCTAssertEqual(calls.withLock { $0 }, 3, "Speech ends the analysis")
    }

    func testEveryFailureModeFailsOpen() async {
        struct Failure: Error {}
        let unavailable = DictationSpeechGate { throw Failure() }
        unavailable.offer(chunk())
        let unavailableVerdict = await unavailable.verdict(within: .seconds(2))
        XCTAssertEqual(unavailableVerdict, .undetermined, "A missing model is not silence")

        let failing = DictationSpeechGate { { _ in throw Failure() } }
        failing.offer(chunk())
        let failingVerdict = await failing.verdict(within: .seconds(2))
        XCTAssertEqual(failingVerdict, .undetermined, "A detector error is not silence")

        let cancelled = DictationSpeechGate { { _ in false } }
        cancelled.offer(chunk())
        cancelled.cancel()
        let cancelledVerdict = await cancelled.verdict(within: .seconds(2))
        XCTAssertEqual(cancelledVerdict, .undetermined)
    }

    func testDroppedAudioForfeitsTheNoSpeechVerdict() async {
        let release = OSAllocatedUnfairLock(initialState: false)
        let gate = DictationSpeechGate {
            while !release.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
            return { _ in false }
        }
        for index in 0...DictationSpeechGate.capacity { gate.offer(chunk(index)) }
        release.withLock { $0 = true }
        let verdict = await gate.verdict(within: .seconds(5))
        XCTAssertEqual(verdict, .undetermined, "Audio the detector never saw cannot prove silence")
    }

    func testSlowAnalysisTimesOutAsUndetermined() async {
        let gate = DictationSpeechGate {
            { _ in
                try await Task.sleep(for: .seconds(30))
                return false
            }
        }
        gate.offer(chunk())
        let start = ContinuousClock.now
        let verdict = await gate.verdict(within: .milliseconds(100))
        XCTAssertEqual(verdict, .undetermined)
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
    }

    /// The detector arrives with the speech model from Settings or onboarding, because auto stop
    /// needs it with the gate off, so turning on dictation downloads nothing either way.
    @MainActor
    func testTurningOnDictationDownloadsNoModelWhateverTheGate() async throws {
        // A disposable launch stores the choice in the process-wide volatile domain.
        let key = DictationController.defaultsKey
        addTeardownBlock { Self.forget(key) }
        for gateIsOn in [false, true] {
            let suite = "speech-gate-prepare-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(gateIsOn, forKey: DictationSpeechGate.defaultsKey)
            let models = MissingModels()
            let feature = try DictationFeature(
                usesTemporaryStore: true, arguments: ["-use-temp-store"], defaults: defaults,
                environment: .disposable(permissionsAreMissing: false, models: models.models))

            feature.setEnabled(true)

            let checked = await TestPolling.until {
                models.remembered.withLock { $0 } == DictationModels.Part.required.count
            }
            XCTAssertTrue(checked)
            XCTAssertEqual(models.installs.withLock { $0 }, [], "Gate on: \(gateIsOn)")
            XCTAssertEqual(feature.modelState, .missing)
        }
    }

    @MainActor
    func testDisposableCompositionNeverDownloadsTheDetector() async throws {
        let suite = "speech-gate-disposable-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let feature = try DictationFeature(usesTemporaryStore: true, arguments: ["-use-temp-store"], defaults: defaults)
        XCTAssertNil(feature.environment.models)

        feature.downloadModel()
        try await feature.installModels()

        XCTAssertEqual(feature.modelState, .missing)
        let detector = await feature.modelStore.verifiedInstallation(ModelCatalog.sileroVAD)
        XCTAssertNil(detector)
    }

    private nonisolated static func forget(_ key: String) {
        let defaults = UserDefaults.standard
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        domain.removeValue(forKey: key)
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async -> Bool {
        return await TestPolling.until(condition)
    }
}

/// Nothing installed, and every install asked of it recorded.
private final class MissingModels: Sendable {
    let installs = Mutex<[DictationModels.Part]>([])
    let remembered = Mutex(0)

    var models: DictationModels {
        DictationModels(
            isVerified: { _ in false },
            wasVerified: { _ in false },
            remember: { _, _ in self.remembered.withLock { $0 += 1 } },
            install: { part, _ in self.installs.withLock { $0.append(part) } },
            size: { _ in 100 },
            collectUnused: {})
    }
}

@MainActor
final class DictationSpeechGateSileroTests: XCTestCase {
    private func batch(_ probability: Float, triggered: Bool = false) -> VoiceActivityBatch {
        VoiceActivityBatch(didResetForDiscontinuity: false, observations: [
            VoiceActivityObservation(frameStart: 0, frameEnd: 0.256, speechProbability: probability,
                                     isSpeechActive: triggered, event: nil)
        ])
    }

    func testQuietSpeechCountsFromSileroReferenceThreshold() async {
        XCTAssertTrue(DictationSpeechGate.heardSpeech(batch(0.6)), "Below FluidAudio's 0.85 is still speech")
        XCTAssertTrue(DictationSpeechGate.heardSpeech(batch(0.5)))
        XCTAssertTrue(DictationSpeechGate.heardSpeech(batch(0.2, triggered: true)), "A triggered frame is speech")
        XCTAssertFalse(DictationSpeechGate.heardSpeech(batch(0.49)))
        XCTAssertFalse(DictationSpeechGate.heardSpeech(VoiceActivityBatch(didResetForDiscontinuity: true, observations: [])))
    }

    func testGateIsOnUnlessTheUserTurnedItOff() async throws {
        let suite = "speech-gate-default-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(DictationSpeechGate.isEnabled(in: defaults))
        defaults.set(false, forKey: DictationSpeechGate.defaultsKey)
        XCTAssertFalse(DictationSpeechGate.isEnabled(in: defaults))
    }
}
