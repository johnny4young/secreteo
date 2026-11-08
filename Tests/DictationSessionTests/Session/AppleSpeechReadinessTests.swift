import Foundation
import Synchronization
import Testing

@testable import DictationSession

/// Switching the engine writes the process-wide argument domain, so this runs with the suites that guard it.
@Suite(.serialized, .exclusiveArgumentDomain)
@MainActor
struct AppleSpeechReadinessTests {
    @Test
    func appleSpeechNeedsOnlyTheDetectorAndChoosingParakeetAsksForIt() async throws {
        let parts = AppleSpeechParts()
        let (feature, cleanup) = try parts.feature()
        defer { cleanup() }

        await feature.refreshReadiness()
        #expect(feature.modelState == .missing, "The speech gate and auto-stop still use the detector")
        #expect(feature.readiness.modelIsReady.withLock { $0 }, "Without it the gate fails open")
        #expect(feature.canPractice)

        try await feature.installModels()
        #expect(parts.installed.withLock { $0 } == [.speechDetector], "Apple Speech never loads Parakeet")
        await feature.refreshReadiness()
        #expect(feature.modelState == .ready)

        feature.speechEngineBinding.wrappedValue = .parakeet
        #expect(feature.modelState == .missing)
        #expect(!feature.readiness.modelIsReady.withLock { $0 })
        #expect(!feature.canPractice)

        feature.speechEngineBinding.wrappedValue = .appleSpeech
        #expect(feature.modelState == .ready)
        #expect(feature.readiness.modelIsReady.withLock { $0 })
    }

    @Test
    func onboardingWithAppleSpeechInstallsOnlyTheDetectorAndLoadsNoParakeet() async throws {
        let parts = AppleSpeechParts()
        let (feature, cleanup) = try parts.feature()
        defer { cleanup() }

        try await feature.prepareSpeechModel(attempt: 1)

        #expect(parts.installed.withLock { $0 } == [.speechDetector])
        #expect(!feature.warmEngine.isHoldingModel)
    }

    @Test
    func appleSpeechNeverHashesParakeetUntilParakeetIsChosen() async throws {
        let parts = AppleSpeechParts()
        let (feature, cleanup) = try parts.feature()
        defer { cleanup() }

        await feature.refreshReadiness()
        #expect(parts.speechHashes.withLock { $0 } == 0)

        feature.speechEngineBinding.wrappedValue = .parakeet
        #expect(await TestPolling.until { parts.speechHashes.withLock { $0 } > 0 })
    }

    @Test
    func aParakeetInstallDoesNotJoinADetectorOnlyInstall() async throws {
        let parts = AppleSpeechParts(holdsDetector: true)
        let (feature, cleanup) = try parts.feature()
        defer { cleanup() }
        let first = Task { try await feature.installModels() }
        #expect(await TestPolling.until { parts.installed.withLock { $0 } == [.speechDetector] })

        feature.speechEngineBinding.wrappedValue = .parakeet
        let second = Task { try await feature.installModels() }
        parts.release()
        try await first.value
        try await second.value

        #expect(parts.installed.withLock { $0 } == [.speechDetector, .speech])
        #expect(feature.modelState == .ready)
    }

    @Test
    func aFailureForOneEngineIsNotShownForTheOther() async throws {
        let parts = AppleSpeechParts(failsInstall: true)
        let (feature, cleanup) = try parts.feature()
        defer { cleanup() }
        await #expect(throws: (any Error).self) { try await feature.installModels() }
        #expect(feature.modelState == .failed)

        feature.speechEngineBinding.wrappedValue = .parakeet

        #expect(feature.modelState == .missing)
    }

    @Test
    func aRememberedDetectorIsEnoughForAppleSpeechAtLaunch() async throws {
        let parts = AppleSpeechParts(holdsHashes: true, remembersDetector: true)
        let (feature, cleanup) = try parts.feature()
        defer {
            parts.release()
            cleanup()
        }

        feature.start()
        let isReady = await TestPolling.until { feature.modelState == .ready }
        #expect(isReady, "Apple Speech needs no remembered Parakeet")
    }

    @Test
    func importingAppleSpeechFromPortavozStopsAskingForParakeet() async throws {
        let parts = AppleSpeechParts(choosesApple: false)
        let (feature, cleanup) = try parts.feature(
            portavoz: [LiveSpeechSelection.dictationKey: LiveSpeechSelection.appleSpeech.rawValue])
        defer { cleanup() }
        await feature.refreshReadiness()
        #expect(!feature.readiness.modelIsReady.withLock { $0 })
        feature.refreshPortavozImport()

        feature.importPortavozPreferences()

        #expect(feature.readiness.modelIsReady.withLock { $0 })
    }
}

/// Synthetic parts: nothing is verified until it is installed.
private final class AppleSpeechParts: Sendable {
    let installed = Mutex<[DictationModels.Part]>([])
    let speechHashes = Mutex(0)
    private let verified = Mutex<Set<DictationModels.Part>>([])
    private let held: Mutex<Bool>
    private let holdsHashes: Bool
    private let failsInstall: Bool
    private let remembersDetector: Bool
    private let choosesApple: Bool

    init(
        holdsDetector: Bool = false, holdsHashes: Bool = false, failsInstall: Bool = false,
        remembersDetector: Bool = false, choosesApple: Bool = true
    ) {
        held = Mutex(holdsDetector || holdsHashes)
        self.holdsHashes = holdsHashes
        self.failsInstall = failsInstall
        self.remembersDetector = remembersDetector
        self.choosesApple = choosesApple
    }

    func release() { held.withLock { $0 = false } }

    private func waitWhileHeld() async throws {
        while held.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
    }

    @MainActor
    func feature(portavoz: [String: Any] = [:]) throws -> (DictationFeature, () -> Void) {
        let suite = "apple-speech-readiness-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        if choosesApple {
            defaults.set(LiveSpeechSelection.appleSpeech.rawValue, forKey: LiveSpeechSelection.dictationKey)
        }
        let models = DictationModels(
            isVerified: { [self] part in
                if part == .speech { speechHashes.withLock { $0 += 1 } }
                if holdsHashes { try? await waitWhileHeld() }
                return verified.withLock { $0.contains(part) }
            },
            wasVerified: { [self] part in remembersDetector && part == .speechDetector },
            remember: { _, _ in },
            install: { [self] part, _ in
                installed.withLock { $0.append(part) }
                if !holdsHashes { try await waitWhileHeld() }
                if failsInstall { throw CancellationError() }
                verified.withLock { _ = $0.insert(part) }
            },
            size: { _ in 100 }, collectUnused: {})
        var environment = DictationFeatureEnvironment.disposable(permissionsAreMissing: false, models: models)
        environment.portavozPreferences = { portavoz }
        let feature = try DictationFeature(
            usesTemporaryStore: true, arguments: ["-use-temp-store"], defaults: defaults, environment: environment)
        return (feature, { defaults.removePersistentDomain(forName: suite) })
    }
}
