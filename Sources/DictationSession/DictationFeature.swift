import AppKit
import ApplicationServices
import DictationKit
import DictationOwnership
import Foundation
import LiveSpeech
import LocalModelStore
import MicCapture
import Observation
import Synchronization

/// The dictation half of the composition root. `AppUI` holds one of these and sees nothing else.
@MainActor
@Observable
public final class DictationFeature: AppServices {
    public enum ModelState: Equatable {
        case missing
        case downloading
        case ready
        case failed
    }

    /// Off in a Release build until the other app's cooperating version has shipped.
    public static var mayRunInThisBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "SecreteoGlobalDictation") as? String == "YES"
    }

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let usesTemporaryMeetingStore: Bool
    @ObservationIgnored let microphonePermissions = MicrophonePermissionClient()
    @ObservationIgnored let modelStore: LocalModelStore
    @ObservationIgnored let dictationPolisher: any DictationTextPolishing = UnavailablePolisher()
    @ObservationIgnored private let fixture: DictationUITestFixture?
    @ObservationIgnored private let seedsMissingPermissions: Bool
    @ObservationIgnored private let ownership: DictationOwnershipCoordinator
    @ObservationIgnored private let readiness: ReadinessGap
    @ObservationIgnored private var engine: ParakeetEngine?
    @ObservationIgnored private var engineLoad: Task<ParakeetEngine, Error>?
    @ObservationIgnored private var idleRelease: Task<Void, Never>?
    private let controller: DictationController

    public private(set) var modelState = ModelState.missing
    public private(set) var isEnabled: Bool
    public private(set) var lastHandoffFailed = false

    public init(usesTemporaryStore: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) throws {
        let defaults = UserDefaults.standard
        if usesTemporaryStore { UITestDefaults.installIfNeeded(arguments: arguments, defaults: defaults) }
        self.defaults = defaults
        usesTemporaryMeetingStore = usesTemporaryStore
        isEnabled = defaults.bool(forKey: DictationController.defaultsKey)
        let identifier = Bundle.main.bundleIdentifier ?? "com.johnny4young.secreteo.unbundled"
        modelStore = try LocalModelStore(
            location: usesTemporaryStore
                ? .directory(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
                : .userLibrary,
            consumer: StoreConsumer(bundleID: identifier, displayName: "Secreteo"))
        fixture = DictationUITestFixture(arguments: arguments, usesTemporaryStore: usesTemporaryStore)
        seedsMissingPermissions = usesTemporaryStore && arguments.contains("-seed-dictation-permissions-missing")
        // A disposable launch has its own fixtures, so nothing real can be missing there.
        let readiness = ReadinessGap(usesTemporaryStore ? nil : "model")
        self.readiness = readiness
        ownership = .live(
            defaults: defaults, usesTemporaryStore: usesTemporaryStore,
            missingForReadiness: { readiness.value.withLock { $0 } })
        controller = DictationController()
        // A disposable launch owns its own scratch folder, because no user is there to take it.
        if usesTemporaryStore { ownership.claimScratchOwnership() }
    }

    public func start() {
        DictationTextPreferences.initialize(in: defaults, temporary: usesTemporaryMeetingStore)
        ownership.onStateChange = { [weak self] _ in self?.syncDictationTriggers() }
        ownership.onIntentChange = { [weak self] isLive in
            if isLive { self?.controller.ownershipIntentSeen() } else { self?.controller.ownershipIntentCleared() }
        }
        ownership.start()
        syncDictationTriggers()
        Task { await refreshReadiness() }
    }

    /// A hint from the app: permissions may have changed in System Settings.
    public func applicationDidBecomeActive() {
        Task { await refreshReadiness() }
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: DictationController.defaultsKey)
        isEnabled = enabled
        syncDictationTriggers(promptIfNeeded: enabled)
        Task {
            let outcome = await ownership.preferenceChanged(
                isOn: enabled, arm: armForHandoff, disarm: { self.syncDictationTriggers() })
            lastHandoffFailed = outcome.map(Self.failed) ?? false
            await refreshReadiness()
        }
    }

    /// Takes dictation from whoever owns it now. Only the user's own action calls this.
    public func takeOwnership() {
        Task {
            let outcome = await ownership.takeOwnership(
                arm: armForHandoff, disarm: { self.syncDictationTriggers() })
            lastHandoffFailed = Self.failed(outcome)
        }
    }

    public func toggleDictation() {
        controller.toggle(using: makeDictationSessionDependencies())
    }

    public func pasteLast(alternate: Bool = false) {
        controller.pasteLastDictation(using: makeDictationSessionDependencies(), alternate: alternate)
    }

    public func downloadModel() {
        guard !usesTemporaryMeetingStore, modelState != .downloading else { return }
        modelState = .downloading
        Task {
            do {
                _ = try await modelStore.ensureAvailable(ModelCatalog.parakeetTdtV3, seeds: [], progress: nil)
            } catch {
                modelState = .failed
                return
            }
            await refreshReadiness()
        }
    }

    public func requestMicrophone() {
        Task {
            _ = await microphonePermissions.authorizeIfNeeded()
            await refreshReadiness()
        }
    }

    public func requestAccessibility() {
        guard !usesTemporaryMeetingStore else { return }
        _ = TextInserter.canInsert(promptIfNeeded: true)
    }

    public var isActive: Bool { controller.isActive }
    public var canPasteLast: Bool { controller.hasPastableText && !controller.isActive }
    public var canPasteUnpolished: Bool { canPasteAlternate && !controller.lastText.alternateIsOriginal }
    public var canPasteOriginal: Bool { canPasteAlternate && controller.lastText.alternateIsOriginal }
    private var canPasteAlternate: Bool { controller.hasAlternateText && !controller.isActive }
    public var shortcutLabel: String { controller.shortcut.setting.label }
    public var shortcutIsUnavailable: Bool { controller.shortcut.availability == .unavailable }
    public var isOwner: Bool { ownership.state == .owned }
    public var canTakeOwnership: Bool { ownership.state == .available }
    public var microphoneIsAuthorized: Bool {
        usesTemporaryMeetingStore ? !seedsMissingPermissions : microphonePermissions.state() == .authorized
    }
    public var accessibilityIsGranted: Bool {
        usesTemporaryMeetingStore ? !seedsMissingPermissions : AXIsProcessTrusted()
    }

    // MARK: AppServices

    var dictationAdmission: DictationAdmission { ownership.admission }
    var dictationTriggersMayArm: Bool { ownership.armsTriggers }

    var dictationShortcutRegistrar: DictationShortcut.Registrar? {
        guard !usesTemporaryMeetingStore else { return nil }
        return { setting, onPress, onRelease in
            GlobalHotkey(keyCode: setting.keyCode, modifiers: setting.modifiers, onPress: onPress, onRelease: onRelease)
        }
    }

    func makeDictationSessionDependencies() -> DictationSessionDependencies {
        guard usesTemporaryMeetingStore else {
            return .live(services: self, beginCapture: { {} })
        }
        var dependencies = DictationUITestFixture.dependencies(
            fixture: fixture, admission: dictationAdmission, beginCapture: { {} })
        dependencies.waitForFeedbackDismissal = DictationUITestFixture.waitHoldingUnverifiedNotices
        dependencies.storesPreferencesTemporarily = true
        dependencies.polishDictation = DictationUITestFixture.polishing(fixture)
        dependencies.translateDictation = DictationUITestFixture.translating(fixture)
        return dependencies
    }

    func acquireLiveTranscriptionRuntime(for purpose: LiveSpeechPurpose) async throws -> LiveTranscriptionRuntime {
        if purpose.selectedEngine(in: defaults) == .appleSpeech {
            let engine = try await SpeechAnalyzerLiveEngine.acquireInstalled(language: purpose.language(in: defaults))
            return LiveTranscriptionRuntime(engine: engine, lane: .appleSpeech) {}
        }
        idleRelease?.cancel()
        let engine = try await loadedEngine()
        let lane = LiveSpeechSelection(checkpoint: engine.checkpoint)
        return LiveTranscriptionRuntime(engine: engine, lane: lane) { [weak self] in self?.releaseEngineWhenIdle() }
    }

    // MARK: Private

    private var armForHandoff: @MainActor () -> Bool {
        { [weak self] in
            guard let self else { return false }
            syncDictationTriggers()
            return controller.shortcut.availability != .unavailable
        }
    }

    private static func failed(_ outcome: HandoffOutcome) -> Bool {
        switch outcome {
        case .completed, .alreadyOwner: false
        default: true
        }
    }

    private func syncDictationTriggers(promptIfNeeded: Bool = false) {
        controller.syncHotkey(services: self)
        controller.syncMousePTT(services: self, promptIfNeeded: promptIfNeeded)
        controller.syncModifierPTT(services: self, promptIfNeeded: promptIfNeeded)
    }

    private func loadedEngine() async throws -> ParakeetEngine {
        if let engine { return engine }
        if let engineLoad { return try await engineLoad.value }
        guard let installed = await modelStore.verifiedInstallation(ModelCatalog.parakeetTdtV3) else {
            throw DictationFeatureError.modelMissing
        }
        let load = Task { try await ParakeetEngine.load(fromVerifiedDirectory: installed.directory) }
        engineLoad = load
        defer { engineLoad = nil }
        let loaded = try await load.value
        engine = loaded
        return loaded
    }

    /// A model stays ready for the next dictation, then gives its memory back.
    private func releaseEngineWhenIdle() {
        idleRelease?.cancel()
        idleRelease = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            self?.engine = nil
        }
    }

    private func refreshReadiness() async {
        guard !usesTemporaryMeetingStore else {
            ownership.reevaluate()
            return
        }
        let modelIsInstalled = await modelStore.verifiedInstallation(ModelCatalog.parakeetTdtV3) != nil
        if modelState != .downloading { modelState = modelIsInstalled ? .ready : .missing }
        let gap: String? = if !modelIsInstalled {
            "model"
        } else if microphonePermissions.state() != .authorized {
            "microphone"
        } else if !AXIsProcessTrusted() {
            "accessibility"
        } else {
            nil
        }
        readiness.value.withLock { $0 = gap }
        ownership.reevaluate()
        syncDictationTriggers()
    }
}

/// What the protocol reads off the main actor.
private final class ReadinessGap: Sendable {
    let value: Mutex<String?>

    init(_ gap: String?) {
        value = Mutex(gap)
    }
}

enum DictationFeatureError: LocalizedError {
    case modelMissing

    var errorDescription: String? {
        L10n.text("The speech model is not installed. Download it in Settings.")
    }
}

/// Polish arrives with its providers, so until then a dictation keeps its clean text.
private struct UnavailablePolisher: DictationTextPolishing {
    func polish(_ text: String, recipe: String?) async throws -> String {
        throw DictationPolishUnavailable(reason: L10n.text("No Polish engine is available."))
    }
}
