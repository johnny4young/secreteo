import Darwin
import DictationOwnership
import Foundation
import LiveSpeech
import LocalModelStore
import MicCapture
import Observation
import Synchronization
import XCTest

@testable import DictationSession

@MainActor
final class DictationFeatureTests: XCTestCase {
    private struct InstallFailed: Error {}

    private final class System: Sendable {
        let microphone = Mutex(MicrophonePermissionState.notDetermined)
        let accessibility = Mutex(false)
        let verified = Mutex<Set<DictationModels.Part>>([.speech, .speechDetector])
        let remembered = Mutex<Set<DictationModels.Part>>([])
        let failsToInstall = Mutex<Set<DictationModels.Part>>([])
        let installed = Mutex<[DictationModels.Part]>([])
        let collections = Mutex(0)
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
                models: DictationModels(
                    isVerified: { part in
                        if let gate = self.modelGate.withLock({ $0 }) {
                            for await _ in gate { break }
                        }
                        return self.verified.withLock { $0.contains(part) }
                    },
                    wasVerified: { part in self.remembered.withLock { $0.contains(part) } },
                    remember: { part, isVerified in
                        self.remembered.withLock { remembered in
                            if isVerified { remembered.insert(part) } else { remembered.remove(part) }
                        }
                    },
                    install: { part in
                        if self.failsToInstall.withLock({ $0.contains(part) }) { throw InstallFailed() }
                        self.installed.withLock { $0.append(part) }
                        self.verified.withLock { _ = $0.insert(part) }
                    },
                    collectUnused: { self.collections.withLock { $0 += 1 } }))
        }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "DictationFeatureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeFeature(
        _ system: System = System(), defaults: UserDefaults? = nil, arguments: [String] = []
    ) throws -> DictationFeature {
        try DictationFeature(
            usesTemporaryStore: true, arguments: arguments, defaults: defaults ?? makeDefaults(),
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
        system.verified.withLock { $0 = [] }
        let check = Task { await feature.refreshReadiness() }
        await Task.yield()
        check.cancel()
        release.finish()
        await check.value
        XCTAssertEqual(feature.modelState, .ready)
        XCTAssertEqual(system.remembered.withLock { $0 }, [.speech, .speechDetector], "Nor is it forgotten")

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

    @MainActor
    private final class Registrations {
        private final class Registration: GlobalHotkeyRegistration {
            let onUnregister: @MainActor () -> Void
            init(onUnregister: @escaping @MainActor () -> Void) { self.onUnregister = onUnregister }
            func unregister() { onUnregister() }
        }

        var settings: [HotkeySetting] = []
        var active = 0
        var isTaken = false
        var press: () -> Void = {}

        var registrar: DictationShortcut.Registrar {
            { @MainActor [self] setting, press, _ in
                guard !isTaken else { return nil }
                settings.append(setting)
                active += 1
                self.press = press
                return Registration { [self] in active -= 1 }
            }
        }
    }

    private func pasteLastFeature(arguments: [String] = []) throws -> (DictationFeature, Registrations) {
        let defaults = makeDefaults()
        defaults.set(true, forKey: DictationController.defaultsKey)
        let feature = try makeFeature(defaults: defaults, arguments: arguments)
        let registrations = Registrations()
        feature.pasteLastRegistrar = registrations.registrar
        // A disposable launch stores choices in the process-wide volatile domain.
        addTeardownBlock { Self.forgetPasteLastChoice() }
        return (feature, registrations)
    }

    private nonisolated static func forgetPasteLastChoice() {
        let defaults = UserDefaults.standard
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        domain.removeValue(forKey: PasteLastShortcut.defaultsKey)
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    func testThePasteLastShortcutIsOffUntilChosen() throws {
        let (feature, registrations) = try pasteLastFeature()
        feature.start()
        XCTAssertEqual(registrations.active, 0)

        feature.pasteLastShortcutBinding.wrappedValue = true

        XCTAssertEqual(registrations.settings, [PasteLastShortcut.setting])
        XCTAssertEqual(registrations.active, 1)

        feature.pasteLastShortcutBinding.wrappedValue = false

        XCTAssertEqual(registrations.active, 0)
    }

    func testThePasteLastShortcutNeedsDictationToBeOn() throws {
        let (feature, registrations) = try pasteLastFeature()
        feature.start()
        feature.pasteLastShortcutBinding.wrappedValue = true

        feature.defaults.set(false, forKey: DictationController.defaultsKey)
        feature.triggersChanged()

        XCTAssertEqual(registrations.active, 0)
    }

    func testATakenPasteLastShortcutIsShownUntilItIsTurnedOff() throws {
        let (feature, registrations) = try pasteLastFeature()
        feature.start()
        registrations.isTaken = true

        feature.pasteLastShortcutBinding.wrappedValue = true
        XCTAssertTrue(feature.pasteLastShortcutIsUnavailable)

        feature.pasteLastShortcutBinding.wrappedValue = false
        XCTAssertFalse(feature.pasteLastShortcutIsUnavailable)
    }

    func testRecordingAShortcutFreesPasteLastAndThenRestoresIt() throws {
        let (feature, registrations) = try pasteLastFeature()
        feature.start()
        feature.pasteLastShortcutBinding.wrappedValue = true

        feature.shortcutRecording(true)
        XCTAssertEqual(registrations.active, 0)

        feature.shortcutRecording(false)
        XCTAssertEqual(registrations.active, 1)
    }

    func testNothingRearmsTheKeysWhileAShortcutIsBeingRecorded() throws {
        let (feature, registrations) = try pasteLastFeature()
        feature.start()
        feature.pasteLastShortcutBinding.wrappedValue = true
        feature.shortcutRecording(true)

        feature.pasteLastShortcutBinding.wrappedValue = false
        feature.pasteLastShortcutBinding.wrappedValue = true
        feature.triggersChanged()

        XCTAssertEqual(registrations.active, 0)
        XCTAssertFalse(feature.pasteLastShortcutIsUnavailable, "Freed on purpose, so not a conflict")

        feature.shortcutRecording(false)
        XCTAssertEqual(registrations.active, 1)
    }

    func testPressingThePasteLastShortcutDeliversTheLastDictation() async throws {
        let (feature, registrations) = try pasteLastFeature(
            arguments: ["-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-verified"])
        feature.start()
        feature.pasteLastShortcutBinding.wrappedValue = true
        let text = "Send the report."
        feature.controller.lastText.remember(text)

        registrations.press()

        let verified = DictationController.Phase.verified(text.split(separator: " ").count)
        await waitUntil { feature.controller.phase == verified }
        XCTAssertEqual(feature.controller.phase, verified)
        feature.controller.cancel()
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

    func testAMissingDetectorIsOfferedWithoutHoldingDictationBack() async throws {
        let system = System()
        system.verified.withLock { $0 = [.speech] }
        let feature = try makeFeature(system)
        await feature.refreshReadiness()
        XCTAssertEqual(feature.modelState, .missing, "Parakeet in the shared store must not hide the detector")
        XCTAssertTrue(feature.readiness.modelIsInstalled.withLock { $0 })
    }

    func testPrewarmReadsItsChoicesFromPreferences() throws {
        let defaults = makeDefaults()
        let feature = try makeFeature(defaults: defaults)
        XCTAssertFalse(feature.prewarmConditions.prewarmEnabled)
        XCTAssertEqual(feature.prewarmConditions.profile, .balanced)
        XCTAssertTrue(feature.prewarmConditions.temporaryStore)

        defaults.set(true, forKey: DictationPrewarmPolicy.defaultsKey)
        defaults.set(DictationModelMemory.lightweight.rawValue, forKey: DictationModelMemory.key)

        XCTAssertTrue(feature.prewarmConditions.prewarmEnabled)
        XCTAssertEqual(feature.prewarmConditions.profile, .lightweight)
    }

    func testMemoryPressureHoldsOffPrewarmUntilItEnds() throws {
        let feature = try makeFeature()

        feature.memoryPressureChanged(isUnderPressure: true)
        XCTAssertTrue(feature.prewarmConditions.underPressure)

        feature.memoryPressureChanged(isUnderPressure: false)
        XCTAssertFalse(feature.prewarmConditions.underPressure)
    }

    func testAnUnknownMemoryProfileIsBalanced() throws {
        let defaults = makeDefaults()
        XCTAssertEqual(DictationModelMemory.current(in: defaults), .balanced)

        defaults.set("not a profile", forKey: DictationModelMemory.key)

        XCTAssertEqual(DictationModelMemory.current(in: defaults), .balanced)
        XCTAssertLessThan(DictationModelMemory.lightweight.idleLimit, DictationModelMemory.balanced.idleLimit)
    }

    func testAFailedDetectorDownloadIsShownAndCanBeRetried() async throws {
        let system = System()
        system.verified.withLock { $0 = [] }
        system.failsToInstall.withLock { $0 = [.speechDetector] }
        let feature = try makeFeature(system)

        feature.downloadModel()
        await waitUntil { feature.modelState == .failed }
        await feature.refreshReadiness()
        XCTAssertEqual(feature.modelState, .failed)
        XCTAssertTrue(feature.readiness.modelIsInstalled.withLock { $0 }, "Dictation still works without it")

        system.failsToInstall.withLock { $0 = [] }
        feature.downloadModel()
        await waitUntil { feature.modelState == .ready }
        XCTAssertEqual(system.installed.withLock { $0 }, [.speech, .speech, .speechDetector])
    }

    func testAFailedSpeechDownloadLeavesDictationNotReady() async throws {
        let system = System()
        system.verified.withLock { $0 = [] }
        system.failsToInstall.withLock { $0 = [.speech] }
        let feature = try makeFeature(system)
        feature.downloadModel()
        await waitUntil { feature.modelState == .failed }
        await feature.refreshReadiness()
        XCTAssertEqual(system.installed.withLock { $0 }, [])
        XCTAssertFalse(feature.readiness.modelIsInstalled.withLock { $0 })
    }

    func testAModelHashedOnAnEarlierLaunchIsReadyBeforeThisLaunchsHashEnds() async throws {
        let system = System()
        system.remembered.withLock { $0 = [.speech, .speechDetector] }
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        system.modelGate.withLock { $0 = gate }
        let feature = try makeFeature(system)
        XCTAssertFalse(feature.readiness.modelIsInstalled.withLock { $0 })

        feature.start()
        await waitUntil { feature.modelState == .ready }
        XCTAssertTrue(feature.readiness.modelIsInstalled.withLock { $0 })
        release.finish()
    }

    func testABadHashTakesBackARememberedModelAndForgetsIt() async throws {
        let system = System()
        system.remembered.withLock { $0 = [.speech, .speechDetector] }
        system.verified.withLock { $0 = [] }
        let feature = try makeFeature(system)

        feature.start()
        await waitUntil { system.remembered.withLock { $0.isEmpty } }
        XCTAssertEqual(feature.modelState, .missing)
        XCTAssertFalse(feature.readiness.modelIsInstalled.withLock { $0 })
    }

    func testARememberedDetectorAloneShowsNothing() async throws {
        let system = System()
        system.remembered.withLock { $0 = [.speechDetector] }
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        system.modelGate.withLock { $0 = gate }
        let feature = try makeFeature(system)
        feature.start()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(feature.modelState, .missing)
        XCTAssertFalse(feature.readiness.modelIsInstalled.withLock { $0 })
        release.finish()
    }

    func testACorruptOwnershipFileOffersResetAndThenDictationCanBeTaken() async throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: DictationController.defaultsKey)
        let feature = try makeFeature(defaults: defaults, arguments: ["-seed-dictation-corrupt-ownership"])
        feature.start()
        await waitUntil { feature.canResetOwnership }
        XCTAssertFalse(feature.canDictate)
        XCTAssertFalse(feature.canTakeOwnership)

        feature.resetOwnership()
        await waitUntil { feature.canTakeOwnership }
        XCTAssertFalse(feature.canResetOwnership)
        XCTAssertFalse(feature.lastResetFailed)
    }

    func testResetIsNotOfferedForAnyOtherRefusal() async throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: DictationController.defaultsKey)
        let legacy = try makeFeature(defaults: defaults, arguments: ["-seed-dictation-legacy-peer"])
        legacy.start()
        await waitUntil { legacy.unavailableMessage != nil }
        XCTAssertFalse(legacy.canResetOwnership)
        XCTAssertFalse(try makeFeature().canResetOwnership)
    }

    func testAResetThatCouldNotRunIsShown() throws {
        let feature = try makeFeature()
        for change in [OwnershipChange.busy, .failed] {
            feature.recordReset(change)
            XCTAssertTrue(feature.lastResetFailed)
            feature.recordReset(.changed(generation: 1))
            XCTAssertFalse(feature.lastResetFailed)
        }
        feature.recordReset(.noChange)
        XCTAssertFalse(feature.lastResetFailed, "Another app's reset fixed the file just the same")
    }

    func testStartingCollectsUnusedModels() async throws {
        let system = System()
        let feature = try makeFeature(system)

        feature.start()

        await waitUntil { system.collections.withLock { $0 } > 0 }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
final class VerifiedModelRecordTests: XCTestCase {
    private func makeScratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerifiedModelRecordTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func manifest(pinning digit: String = "0") -> ModelManifest {
        ModelManifest(
            id: "test", displayName: "Test", resolveBase: URL(string: "https://example.invalid")!, revision: "a",
            artifacts: [ModelArtifact(path: "nested/model.bin", sha256: String(repeating: digit, count: 64), sizeBytes: 1)],
            minimumRAMGB: 1, license: "MIT")
    }

    func testAnyChangeToTheFilesChangesTheRecord() throws {
        let directory = try makeScratch()
        let file = directory.appendingPathComponent("nested/model.bin")
        XCTAssertNil(VerifiedModelRecord.fingerprint(of: manifest(), in: directory), "Nothing there yet")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: file)

        let original = try XCTUnwrap(VerifiedModelRecord.fingerprint(of: manifest(), in: directory))
        XCTAssertEqual(VerifiedModelRecord.fingerprint(of: manifest(), in: directory), original)
        XCTAssertNotEqual(VerifiedModelRecord.fingerprint(of: manifest(pinning: "1"), in: directory), original)

        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("b".utf8))
        try handle.close()
        let edited = try XCTUnwrap(VerifiedModelRecord.fingerprint(of: manifest(), in: directory))
        XCTAssertNotEqual(edited, original, "Same size, new bytes")

        // Moves only the change time, which is the one stamp a tool cannot set back.
        XCTAssertEqual(setxattr(file.path, "com.example.test", "a", 1, 0, 0), 0)
        let touched = try XCTUnwrap(VerifiedModelRecord.fingerprint(of: manifest(), in: directory))
        XCTAssertNotEqual(touched, edited)

        try Data().write(to: directory.appendingPathComponent("nested/added"))
        XCTAssertNotEqual(VerifiedModelRecord.fingerprint(of: manifest(), in: directory), touched, "An added entry")

        try FileManager.default.removeItem(at: file)
        XCTAssertNil(VerifiedModelRecord.fingerprint(of: manifest(), in: directory))
    }

    private func scratchDefaults() throws -> UserDefaults {
        let name = "VerifiedModelRecordTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    func testCollectingRetiresAClaimOnAModelNoLongerPinned() async throws {
        let scratch = try makeScratch()
        let consumer = StoreConsumer(bundleID: "com.example.test", displayName: "Test")
        let store = try LocalModelStore(location: .directory(scratch), consumer: consumer)
        let version = scratch.appendingPathComponent("v1.noindex")
        let model = version.appendingPathComponent("models/old@rev-digest/payload")
        let claim = version.appendingPathComponent("claims/old@rev-digest/\(consumer.bundleID).json")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: claim.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {"consumer":"\(consumer.bundleID)","displayName":"Test",\
        "firstClaimedAt":"2026-11-02T12:00:00Z","lastUsedAt":"2026-11-02T12:00:00Z"}
        """.utf8).write(to: claim)
        let models = DictationModels.live(store: store, defaults: try scratchDefaults())

        await models.collectUnused()

        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: claim)) as? [String: Any]
        XCTAssertTrue(written?["retiredAt"] is String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.path), "A retired claim keeps protecting the model")
    }

    func testCollectingClearsAModelNobodyClaims() async throws {
        let scratch = try makeScratch()
        let store = try LocalModelStore(
            location: .directory(scratch),
            consumer: StoreConsumer(bundleID: "com.example.test", displayName: "Test"))
        let model = scratch.appendingPathComponent("v1.noindex/models/old@rev-digest/payload")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        let models = DictationModels.live(store: store, defaults: try scratchDefaults())

        await models.collectUnused()

        XCTAssertFalse(FileManager.default.fileExists(atPath: model.path))
    }

    func testCollectingCreatesNothingWhenNoStoreExists() async throws {
        let scratch = try makeScratch().appendingPathComponent("never-created")
        let store = try LocalModelStore(
            location: .directory(scratch),
            consumer: StoreConsumer(bundleID: "com.example.test", displayName: "Test"))
        let models = DictationModels.live(store: store, defaults: try scratchDefaults())

        await models.collectUnused()

        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.path))
    }

    func testTheLiveModelsRememberBetweenLaunchesOnlyWhatStaysUnchanged() async throws {
        let name = "VerifiedModelRecordTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let store = try LocalModelStore(
            location: .directory(try makeScratch()),
            consumer: StoreConsumer(bundleID: "com.example.test", displayName: "Test"))
        let models = DictationModels.live(store: store, defaults: defaults)
        let directory = try await store.directory(for: ModelCatalog.sileroVAD)
        for artifact in ModelCatalog.sileroVAD.artifacts {
            let file = directory.appendingPathComponent(artifact.path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("a".utf8).write(to: file)
        }

        let wasVerifiedBefore = await models.wasVerified(.speechDetector)
        XCTAssertFalse(wasVerifiedBefore)
        await models.remember(.speechDetector, true)
        let wasVerified = await models.wasVerified(.speechDetector)
        XCTAssertTrue(wasVerified)
        let isVerified = await models.isVerified(.speechDetector)
        XCTAssertFalse(isVerified, "The record says nothing to a real hash")

        let otherLaunch = DictationModels.live(store: store, defaults: defaults)
        let otherLaunchRemembers = await otherLaunch.wasVerified(.speechDetector)
        XCTAssertTrue(otherLaunchRemembers)

        await models.remember(.speechDetector, false)
        let forgotten = await models.wasVerified(.speechDetector)
        XCTAssertFalse(forgotten)

        await models.remember(.speechDetector, true)
        let file = directory.appendingPathComponent(try XCTUnwrap(ModelCatalog.sileroVAD.artifacts.first).path)
        try Data("b".utf8).write(to: file)
        let wasVerifiedAfterEdit = await models.wasVerified(.speechDetector)
        XCTAssertFalse(wasVerifiedAfterEdit)
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
        let warm = WarmModel<Model>(idleLimit: { .milliseconds(10) }, mayKeep: { true }, load: {
            loads.withLock { $0 += 1 }
            return Model()
        })
        _ = try await warm.acquire()
        _ = try await warm.acquire()
        XCTAssertEqual(loads.withLock { $0 }, 1)
        XCTAssertTrue(warm.isHoldingModel)

        warm.releaseWhenIdle()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(warm.isHoldingModel, "The other user still has it")

        warm.releaseWhenIdle()
        await waitForRelease(of: warm)
        XCTAssertFalse(warm.isHoldingModel)
    }

    func testAShorterLimitAppliesToAModelAlreadyWaiting() async throws {
        let limit = Mutex(Duration.seconds(3_600))
        let warm = WarmModel<Model>(idleLimit: { limit.withLock { $0 } }, mayKeep: { true }, load: { Model() })
        _ = try await warm.acquire()
        warm.releaseWhenIdle()

        limit.withLock { $0 = .milliseconds(10) }
        warm.idleLimitChanged()

        await waitForRelease(of: warm)
        XCTAssertFalse(warm.isHoldingModel)
    }

    func testAFailedLoadLeavesAModelFreeToBeGivenBack() async throws {
        let fails = Mutex(false)
        let warm = WarmModel<Model>(idleLimit: { .milliseconds(10) }, mayKeep: { true }, load: {
            if fails.withLock({ $0 }) { throw CancellationError() }
            return Model()
        })
        _ = try await warm.acquire()
        warm.release()
        fails.withLock { $0 = true }

        _ = try? await warm.acquire()
        fails.withLock { $0 = false }
        warm.releaseWhenIdle()
        _ = try await warm.acquire()
        warm.releaseWhenIdle()

        await waitForRelease(of: warm)
        XCTAssertFalse(warm.isHoldingModel)
    }

    private func waitForRelease(of warm: WarmModel<Model>) async {
        for _ in 0..<200 where warm.isHoldingModel {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
