import DictationOwnership
import Foundation
import MicCapture
import Observation
import Synchronization
import XCTest

@testable import DictationSession

@MainActor
final class DictationFeatureTests: XCTestCase {
    private final class System: Sendable {
        let microphone = Mutex(MicrophonePermissionState.notDetermined)
        let accessibility = Mutex(false)
        let modelIsInstalled = Mutex(true)
        let asked = Mutex(0)
        let opened = Mutex(0)
        /// When set, a model check waits here until the test releases it.
        let modelGate = Mutex<AsyncStream<Void>?>(nil)

        func environment() -> DictationFeatureEnvironment {
            DictationFeatureEnvironment(
                microphoneState: { self.microphone.withLock { $0 } },
                accessibilityIsGranted: { self.accessibility.withLock { $0 } },
                askForMicrophone: { self.asked.withLock { $0 += 1 } },
                askForAccessibility: {},
                openMicrophoneSettings: { self.opened.withLock { $0 += 1 } },
                modelIsVerified: {
                    if let gate = self.modelGate.withLock({ $0 }) {
                        for await _ in gate { break }
                    }
                    return self.modelIsInstalled.withLock { $0 }
                })
        }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "DictationFeatureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeFeature(
        _ system: System = System(), defaults: UserDefaults? = nil
    ) throws -> DictationFeature {
        try DictationFeature(
            usesTemporaryStore: true, arguments: [], defaults: defaults ?? makeDefaults(),
            environment: system.environment())
    }

    func testAPermissionGrantedLaterRedrawsWhatObservesIt() async throws {
        let system = System()
        let feature = try makeFeature(system)
        XCTAssertFalse(feature.microphoneIsAuthorized)
        XCTAssertFalse(feature.accessibilityIsGranted)

        let changed = Mutex(0)
        withObservationTracking {
            _ = feature.microphoneIsAuthorized
        } onChange: { changed.withLock { $0 += 1 } }
        withObservationTracking {
            _ = feature.accessibilityIsGranted
        } onChange: { changed.withLock { $0 += 1 } }

        system.microphone.withLock { $0 = .authorized }
        system.accessibility.withLock { $0 = true }
        await feature.refreshReadiness()

        XCTAssertEqual(changed.withLock { $0 }, 2)
        XCTAssertTrue(feature.microphoneIsAuthorized)
        XCTAssertTrue(feature.accessibilityIsGranted)
    }

    func testADeniedMicrophoneLeadsToSystemSettingsBecauseMacOSWillNotAskAgain() throws {
        for state in [MicrophonePermissionState.denied, .restricted] {
            let system = System()
            system.microphone.withLock { $0 = state }
            try makeFeature(system).requestMicrophone()
            XCTAssertEqual(system.opened.withLock { $0 }, 1)
            XCTAssertEqual(system.asked.withLock { $0 }, 0)
        }
    }

    func testAnUndecidedMicrophoneIsAskedAndTheAnswerIsShown() async throws {
        let system = System()
        let feature = try makeFeature(system)
        system.microphone.withLock { $0 = .authorized }
        feature.requestMicrophone()
        await waitUntil { feature.microphoneIsAuthorized }
        XCTAssertEqual(system.asked.withLock { $0 }, 1)
        XCTAssertEqual(system.opened.withLock { $0 }, 0)
    }

    func testACancelledModelCheckDoesNotReportTheModelMissing() async throws {
        let system = System()
        let feature = try makeFeature(system)
        await feature.refreshReadiness()
        XCTAssertEqual(feature.modelState, .ready)

        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        system.modelGate.withLock { $0 = gate }
        system.modelIsInstalled.withLock { $0 = false }
        let check = Task { await feature.refreshReadiness() }
        await Task.yield()
        check.cancel()
        release.finish()
        await check.value
        XCTAssertEqual(feature.modelState, .ready)

        system.modelGate.withLock { $0 = nil }
        await feature.refreshReadiness()
        XCTAssertEqual(feature.modelState, .missing, "A check that finishes still reports the truth")
    }

    func testOnlyAMissingPermissionSetsTheFastReadinessPace() {
        XCTAssertEqual(DictationFeature.readinessPollDelay(missing: "microphone"), .seconds(2))
        XCTAssertEqual(DictationFeature.readinessPollDelay(missing: "accessibility"), .seconds(2))
        XCTAssertEqual(DictationFeature.readinessPollDelay(missing: ReadinessGap.missingModel), .seconds(30))
        XCTAssertEqual(DictationFeature.readinessPollDelay(missing: nil), .seconds(30))
    }

    func testAShortcutConflictIsShownAsTheShortcutAndNotARetry() throws {
        let feature = try makeFeature()
        feature.recordHandoff(.triggerConflict)
        XCTAssertTrue(feature.shortcutIsUnavailable)
        XCTAssertFalse(feature.lastHandoffFailed)

        feature.recordHandoff(.timedOut)
        XCTAssertFalse(feature.shortcutIsUnavailable)
        XCTAssertTrue(feature.lastHandoffFailed)

        feature.recordHandoff(.completed(generation: 1))
        XCTAssertFalse(feature.shortcutIsUnavailable)
        XCTAssertFalse(feature.lastHandoffFailed)

        feature.recordHandoff(.triggerConflict)
        feature.recordHandoff(nil)
        XCTAssertFalse(feature.shortcutIsUnavailable, "Turning dictation off clears it")
    }

    func testPasteRowsAreOfferedOnlyToTheOwner() throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: DictationController.defaultsKey)
        let feature = try makeFeature(defaults: defaults)
        feature.controller.lastText.remember("Send the report.", alternate: "Send it.", isOriginal: false)
        XCTAssertFalse(feature.canPasteLast, "Not started, so not the owner")
        XCTAssertFalse(feature.canPasteUnpolished)

        feature.start()
        XCTAssertTrue(feature.canPasteLast)
        XCTAssertTrue(feature.canPasteUnpolished)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
final class WarmModelTests: XCTestCase {
    private struct Model: Sendable {}

    func testALoadThatEndsAfterOwnershipMovedIsNotKept() async throws {
        let mayKeep = Mutex(true)
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        let warm = WarmModel<Model>(mayKeep: { mayKeep.withLock { $0 } }, load: {
            for await _ in gate { break }
            return Model()
        })
        let acquired = Task { try await warm.acquire() }
        await Task.yield()
        mayKeep.withLock { $0 = false }
        warm.release()
        release.finish()
        _ = try await acquired.value
        XCTAssertFalse(warm.isHoldingModel, "Two apps must not each keep a model warm")
    }

    func testAModelIsReusedAndGivenBackWhenIdle() async throws {
        let loads = Mutex(0)
        let warm = WarmModel<Model>(idleLimit: .milliseconds(10), mayKeep: { true }, load: {
            loads.withLock { $0 += 1 }
            return Model()
        })
        _ = try await warm.acquire()
        _ = try await warm.acquire()
        XCTAssertEqual(loads.withLock { $0 }, 1)
        XCTAssertTrue(warm.isHoldingModel)

        warm.releaseWhenIdle()
        for _ in 0..<200 where warm.isHoldingModel {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(warm.isHoldingModel)
    }
}
