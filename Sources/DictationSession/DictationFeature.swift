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
    @ObservationIgnored private var readinessPoll: Task<Void, Never>?
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
        let seedsLegacyPeer = usesTemporaryStore && arguments.contains("-seed-dictation-legacy-peer")
        let readiness = ReadinessGap(isDisposable: usesTemporaryStore, microphone: MicrophonePermissionClient())
        self.readiness = readiness
        ownership = .live(
            defaults: defaults, usesTemporaryStore: usesTemporaryStore,
            missingForReadiness: { readiness.current() }, seedsLegacyPeer: seedsLegacyPeer)
        controller = DictationController()
        // A disposable launch owns its own scratch folder, because no user is there to take it.
        if usesTemporaryStore { ownership.claimScratchOwnership() }
    }

    public func start() {
        DictationTextPreferences.initialize(in: defaults, temporary: usesTemporaryMeetingStore)
        ownership.onStateChange = { [weak self] previous in self?.ownershipChanged(from: previous) }
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
        storePreference(enabled)
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
            modelState = .ready
            // Optional: without the detector the speech gate fails open and dictation still works.
            _ = try? await modelStore.ensureAvailable(ModelCatalog.sileroVAD, seeds: [], progress: nil)
            await refreshReadiness()
        }
    }

    public func requestMicrophone() {
        guard !usesTemporaryMeetingStore else { return }
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
    /// Off, or owned by another app, a start would be refused with nothing to show for it.
    public var canDictate: Bool { ownership.state == .owned || controller.isActive }
    /// What the user can do when the protocol refuses this app. Readiness has its own controls.
    public var unavailableMessage: String? {
        guard case .unavailable(let reason) = ownership.state else { return nil }
        switch reason {
        case .notReady: return nil
        case .legacyPeerActive: return L10n.text("Update Portavoz or turn off its dictation to use Secreteo.")
        case .newerProtocol: return L10n.text("Update Secreteo to keep dictating.")
        case .lockUnsupported, .corruptState, .ioError, .sandboxed:
            return L10n.text("Dictation is unavailable right now.")
        }
    }
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

    /// A disposable launch runs under the real bundle identifier, so it writes only to its volatile domain.
    private func storePreference(_ enabled: Bool) {
        guard usesTemporaryMeetingStore else {
            defaults.set(enabled, forKey: DictationController.defaultsKey)
            return
        }
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        domain[DictationController.defaultsKey] = enabled
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    private var armForHandoff: @MainActor () -> Bool {
        { [weak self] in
            guard let self else { return false }
            syncDictationTriggers()
            return controller.shortcut.availability != .unavailable
        }
    }

    /// Not ready yet, or another owner in place, is not a failure: Settings shows what to do next.
    private static func failed(_ outcome: HandoffOutcome) -> Bool {
        switch outcome {
        case .timedOut, .triggerConflict, .targetNotReady, .busy, .ioError: true
        case .completed, .alreadyOwner, .notConfirmed, .notAvailable, .superseded, .cancelled: false
        }
    }

    private func ownershipChanged(from previous: ParticipantState) {
        syncDictationTriggers()
        // Two apps must not each keep a model warm.
        if previous == .owned, ownership.state != .owned {
            idleRelease?.cancel()
            engine = nil
        }
    }

    private func syncDictationTriggers(promptIfNeeded: Bool = false) {
        controller.syncHotkey(services: self)
        syncEventTaps(promptIfNeeded: promptIfNeeded)
    }

    /// Safe on any hint: unlike the hotkey, a tap already in place is left alone, so a held key keeps its release.
    private func syncEventTaps(promptIfNeeded: Bool = false) {
        controller.syncMousePTT(services: self, promptIfNeeded: promptIfNeeded)
        controller.syncModifierPTT(services: self, promptIfNeeded: promptIfNeeded)
    }

    private func loadedEngine() async throws -> ParakeetEngine {
        if let engine { return engine }
        if let engineLoad { return try await engineLoad.value }
        let load = Task { [modelStore] in
            guard let installed = await modelStore.verifiedInstallation(ModelCatalog.parakeetTdtV3) else {
                throw DictationFeatureError.modelMissing
            }
            return try await ParakeetEngine.load(fromVerifiedDirectory: installed.directory)
        }
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
        if modelIsInstalled {
            modelState = .ready
        } else if modelState == .ready {
            modelState = .missing
        }
        readiness.modelIsInstalled.withLock { $0 = modelIsInstalled }
        ownership.reevaluate()
        syncEventTaps()
        watchReadiness()
    }

    /// A permission changed in System Settings may never activate this agent app, so look again:
    /// soon while something is missing, and now and then in case one was revoked.
    private func watchReadiness() {
        readinessPoll?.cancel()
        readinessPoll = nil
        guard isEnabled else { return }
        let delay: Duration = readiness.current() == nil ? .seconds(30) : .seconds(2)
        readinessPoll = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refreshReadiness()
        }
    }
}

/// What the protocol reads off the main actor. Permissions are read live, so every admission
/// sees the truth; only the model's state is cached, because reading it can touch the disk.
private final class ReadinessGap: Sendable {
    let modelIsInstalled = Mutex(false)
    private let isDisposable: Bool
    private let microphone: MicrophonePermissionClient

    init(isDisposable: Bool, microphone: MicrophonePermissionClient) {
        self.isDisposable = isDisposable
        self.microphone = microphone
    }

    func current() -> String? {
        // A disposable launch has its own fixtures, so nothing real can be missing there.
        if isDisposable { return nil }
        if !modelIsInstalled.withLock({ $0 }) { return "model" }
        if microphone.state() != .authorized { return "microphone" }
        return AXIsProcessTrusted() ? nil : "accessibility"
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
