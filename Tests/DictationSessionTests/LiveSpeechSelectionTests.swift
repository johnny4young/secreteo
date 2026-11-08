import Foundation
import DictationKit
import LiveSpeech
import LocalModelStore
import Synchronization
import XCTest

@testable import DictationSession

@MainActor
final class LiveSpeechSelectionTests: XCTestCase {
    func testAbsentOrCorruptPreferencesDefaultDictationToUltra() async throws {
        let suite = "live-speech-selection-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LiveSpeechSelection.dictation(defaults: defaults), .parakeetUltra)
        defaults.set("unknown-engine", forKey: LiveSpeechSelection.dictationKey)
        XCTAssertEqual(LiveSpeechSelection.dictation(defaults: defaults), .parakeetUltra)
        defaults.set(LiveSpeechSelection.parakeet.rawValue, forKey: LiveSpeechSelection.dictationKey)
        XCTAssertEqual(LiveSpeechSelection.dictation(defaults: defaults), .parakeet,
                       "an explicit Parakeet choice survives the new default")
    }

    /// Until Ultra is downloaded, its default reads v3 for readiness and for the load.
    func testTheDefaultUltraNeitherDownloadsNorBlocksDictation() async throws {
        let suite = "live-speech-ultra-default-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LiveSpeechPurpose.dictation.selectedEngine(in: defaults), .parakeetUltra)
        let installs = Mutex(0)
        let models = DictationModels(
            isVerified: { _ in true }, wasVerified: { _ in true }, remember: { _, _ in },
            install: { _, _ in installs.withLock { $0 += 1 } }, size: { _ in 100 }, collectUnused: {})
        let feature = try DictationFeature(
            usesTemporaryStore: true, arguments: ["-use-temp-store"], defaults: defaults,
            environment: .disposable(permissionsAreMissing: false, models: models))

        await feature.refreshReadiness()
        XCTAssertEqual(feature.modelState, .ready, "dictation keeps Parakeet until Ultra is downloaded")
        XCTAssertTrue(feature.readiness.modelIsReady.withLock { $0 })

        do {
            _ = try await feature.acquireLiveTranscriptionRuntime(for: .dictation)
            XCTFail("The scratch store holds no model, and a load never downloads one")
        } catch {
            XCTAssertTrue(error is DictationFeatureError)
        }
        XCTAssertEqual(installs.withLock { $0 }, 0, "a default is not consent to download 613 MB")
        let ultra = await feature.modelStore.verifiedInstallation(ModelCatalog.parakeetUltra)
        XCTAssertNil(ultra)
    }

    func testAppleSpeechNeedsOnlyTheDetectorAndChoosingParakeetAsksForIt() async throws {
        let suite = "live-speech-apple-readiness-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(LiveSpeechSelection.appleSpeech.rawValue, forKey: LiveSpeechSelection.dictationKey)
        let verified = Mutex<Set<DictationModels.Part>>([])
        let installed = Mutex<[DictationModels.Part]>([])
        let models = DictationModels(
            isVerified: { part in verified.withLock { $0.contains(part) } }, wasVerified: { _ in false },
            remember: { _, _ in },
            install: { part, _ in
                installed.withLock { $0.append(part) }
                verified.withLock { _ = $0.insert(part) }
            },
            size: { _ in 100 }, collectUnused: {})
        let feature = try DictationFeature(
            usesTemporaryStore: true, arguments: ["-use-temp-store"], defaults: defaults,
            environment: .disposable(permissionsAreMissing: false, models: models))

        await feature.refreshReadiness()
        XCTAssertEqual(feature.modelState, .missing, "The speech gate and auto-stop still use the detector")
        XCTAssertTrue(feature.readiness.modelIsReady.withLock { $0 }, "Without it the gate fails open")
        XCTAssertTrue(feature.canPractice)

        try await feature.installModels()
        XCTAssertEqual(installed.withLock { $0 }, [.speechDetector], "Apple Speech never loads Parakeet")
        await feature.refreshReadiness()
        XCTAssertEqual(feature.modelState, .ready)

        feature.speechEngineBinding.wrappedValue = .parakeet
        XCTAssertEqual(feature.modelState, .missing)
        XCTAssertFalse(feature.readiness.modelIsReady.withLock { $0 })
        XCTAssertFalse(feature.canPractice)

        feature.speechEngineBinding.wrappedValue = .appleSpeech
        XCTAssertEqual(feature.modelState, .ready)
        XCTAssertTrue(feature.readiness.modelIsReady.withLock { $0 })
    }

    func testSelectedAppleWithAutomaticLanguageNeverStartsAModelLoad() async throws {
        let suite = "live-speech-route-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(LiveSpeechSelection.appleSpeech.rawValue, forKey: LiveSpeechSelection.dictationKey)
        defaults.set("auto", forKey: DictationController.languageKey)
        let feature = try DictationFeature(usesTemporaryStore: true, arguments: ["-use-temp-store"], defaults: defaults)

        do {
            _ = try await feature.acquireLiveTranscriptionRuntime(for: .dictation)
            XCTFail("Automatic language must not silently launch a fixed-locale engine")
        } catch SpeechAnalyzerLiveReadiness.languageRequired {
            // Rejected before consulting the Speech daemon, so no Parakeet load was tried either.
        } catch {
            XCTFail("Expected languageRequired, got \(type(of: error))")
        }
        XCTAssertFalse(feature.warmEngine.isHoldingModel)
    }
}
