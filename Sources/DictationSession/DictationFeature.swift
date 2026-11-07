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
    @ObservationIgnored private let fixture: DictationUITestFixture?
    @ObservationIgnored let launchArguments: [String]
    @ObservationIgnored let environment: DictationFeatureEnvironment
    @ObservationIgnored private let ownership: DictationOwnershipCoordinator
    @ObservationIgnored let readiness: ReadinessGap
    @ObservationIgnored let warmEngine: WarmModel<ParakeetEngine>
    @ObservationIgnored private var readinessPoll: Task<Void, Never>?
    @ObservationIgnored private var modelInstall: Task<Void, any Error>?
    @ObservationIgnored private(set) var modelInstallGeneration = 0
    @ObservationIgnored private var memoryPressure: (any DispatchSourceMemoryPressure)?
    @ObservationIgnored let pressure = DictationMemoryPressure()
    @ObservationIgnored var pasteLastRegistrar: DictationShortcut.Registrar?
    @ObservationIgnored private var pasteLastRegistration: (any GlobalHotkeyRegistration)?
    @ObservationIgnored private var isRecordingShortcut = false
    /// Bumped on every write, because `UserDefaults` is not observable.
    var preferenceRevision = 0
    var portavozImport: PortavozPreferenceImport?
    @ObservationIgnored private var preferencesObserver: (any NSObjectProtocol)?
    let controller: DictationController
    @ObservationIgnored let practice = DictationPracticeField()
    @ObservationIgnored let dictationStore: any DictationHistoryStore & DictationStatsStore
    @ObservationIgnored let history: DictationHistoryModel
    @ObservationIgnored let stats: DictationStatsModel
    @ObservationIgnored private let settingsWindowHolder = UUID()

    /// Created on first use, because creating it writes the initial text mode.
    @ObservationIgnored private(set) var textSettingsIfCreated: DictationTextSettingsModel?
    var textSettings: DictationTextSettingsModel {
        if let textSettingsIfCreated { return textSettingsIfCreated }
        let model = DictationTextSettingsModel(defaults: defaults, temporary: usesTemporaryMeetingStore)
        textSettingsIfCreated = model
        return model
    }

    /// Reads the engine chosen in Settings on every call.
    var dictationPolisher: any DictationTextPolishing { DictationPolishRouter.live(defaults: defaults) }

    public internal(set) var modelState = ModelState.missing
    /// Nil until the store reports bytes, so the bar starts indeterminate.
    private(set) var modelDownloadFraction: Double?
    private var speechModelIsInstalled = false
    public private(set) var isEnabled: Bool
    public private(set) var microphoneIsAuthorized: Bool
    public private(set) var accessibilityIsGranted: Bool
    private(set) var handoffProblem: HandoffProblem?
    public private(set) var lastResetFailed = false
    private(set) var pasteLastShortcutIsUnavailable = false

    public convenience init(usesTemporaryStore: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) throws {
        try self.init(usesTemporaryStore: usesTemporaryStore, arguments: arguments, defaults: .standard)
    }

    init(
        usesTemporaryStore: Bool, arguments: [String], defaults: UserDefaults,
        environment: DictationFeatureEnvironment? = nil
    ) throws {
        if usesTemporaryStore { UITestDefaults.installIfNeeded(arguments: arguments, defaults: defaults) }
        self.defaults = defaults
        usesTemporaryMeetingStore = usesTemporaryStore
        isEnabled = defaults.bool(forKey: DictationController.defaultsKey)
        let identifier = Bundle.main.bundleIdentifier ?? "com.johnny4young.secreteo.unbundled"
        let modelStore = try LocalModelStore(
            location: usesTemporaryStore
                ? .directory(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
                : .userLibrary,
            consumer: StoreConsumer(bundleID: identifier, displayName: "Secreteo"))
        self.modelStore = modelStore
        let dictationStore = Self.openDictationStore(
            usesTemporaryStore: usesTemporaryStore, bundleIdentifier: identifier)
        self.dictationStore = dictationStore
        history = DictationHistoryModel(store: dictationStore)
        stats = DictationStatsModel(store: dictationStore)
        fixture = DictationUITestFixture(arguments: arguments, usesTemporaryStore: usesTemporaryStore)
        launchArguments = arguments
        let environment = environment ?? (usesTemporaryStore
            ? .disposable(
                permissionsAreMissing: arguments.contains("-seed-dictation-permissions-missing"),
                seedsPortavozPreferences: arguments.contains("-seed-portavoz-preferences"),
                models: arguments.contains("-seed-model-download-held") ? .heldDownload : nil)
            : .live(microphone: microphonePermissions, models: .live(
                store: modelStore, defaults: defaults, seedRoot: DictationModels.portavozModels)))
        self.environment = environment
        microphoneIsAuthorized = environment.microphoneState() == .authorized
        accessibilityIsGranted = environment.accessibilityIsGranted()
        let seedsLegacyPeer = usesTemporaryStore && arguments.contains("-seed-dictation-legacy-peer")
        let readiness = ReadinessGap(isDisposable: usesTemporaryStore, microphone: MicrophonePermissionClient())
        self.readiness = readiness
        let ownership = DictationOwnershipCoordinator.live(
            defaults: defaults, usesTemporaryStore: usesTemporaryStore,
            missingForReadiness: { readiness.current() }, seedsLegacyPeer: seedsLegacyPeer,
            seedsCorruptState: usesTemporaryStore && arguments.contains("-seed-dictation-corrupt-ownership"))
        self.ownership = ownership
        // Two apps must not each keep a model warm.
        warmEngine = WarmModel(
            idleLimit: { [pressure] in
                DictationModelMemory.current(in: defaults).idleLimit(underPressure: pressure.isActive)
            },
            mayKeep: { ownership.state == .owned },
            load: {
                guard let installed = await modelStore.verifiedInstallation(ModelCatalog.parakeetTdtV3) else {
                    throw DictationFeatureError.modelMissing
                }
                return try await ParakeetEngine.load(fromVerifiedDirectory: installed.directory)
            })
        controller = DictationController()
        practice.onForget = { [controller] in controller.practiceLastText.clear() }
        pasteLastRegistrar = usesTemporaryStore ? nil : DictationShortcut.liveRegistrar
        // A learned correction writes here directly, and an open Settings window must show it.
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferenceRevision += 1 }
        }
        // A disposable launch owns its own scratch folder, because no user is there to take it.
        if usesTemporaryStore { ownership.claimScratchOwnership() }
    }

    public func start() {
        DictationTextPreferences.initialize(in: defaults, temporary: usesTemporaryMeetingStore)
        // Created here so a Settings body never creates it and writes defaults mid-update.
        _ = textSettings
        ownership.onStateChange = { [weak self] previous in self?.ownershipChanged(from: previous) }
        ownership.onIntentChange = { [weak self] isLive in
            if isLive { self?.controller.ownershipIntentSeen() } else { self?.controller.ownershipIntentCleared() }
        }
        ownership.start()
        syncDictationTriggers()
        installDictationIntents()
        Task {
            await showRememberedModels()
            await refreshReadiness()
        }
        Task {
            await loadDictationHistory()
            await loadDictationStats()
        }
        if let models = environment.models {
            Task.detached(priority: .utility) { await models.collectUnused() }
        }
        watchMemoryPressure()
        prewarmIfConfigured()
    }

    /// A hint from the app: permissions may have changed in System Settings.
    public func applicationDidBecomeActive() {
        Task { await refreshReadiness() }
    }

    public func setEnabled(_ enabled: Bool) {
        store([DictationController.defaultsKey: enabled])
        isEnabled = enabled
        if !enabled { practice.clear() }
        syncDictationTriggers(promptIfNeeded: enabled)
        Task {
            let outcome = await ownership.preferenceChanged(
                isOn: enabled, arm: armForHandoff, disarm: { self.syncDictationTriggers() })
            recordHandoff(outcome)
            await refreshReadiness()
            prewarmIfConfigured()
        }
    }

    /// Takes dictation from whoever owns it now. Only the user's own action calls this.
    public func takeOwnership() {
        Task {
            recordHandoff(await ownership.takeOwnership(
                arm: armForHandoff, disarm: { self.syncDictationTriggers() }))
        }
    }

    public func toggleDictation() {
        controller.toggle(using: makeDictationSessionDependencies())
    }

    public func pasteLast(alternate: Bool = false) {
        controller.pasteLastDictation(using: makeDictationSessionDependencies(), alternate: alternate)
    }

    public func downloadModel() {
        guard environment.models != nil, modelState != .downloading else { return }
        modelState = .downloading
        Task {
            try? await installModels()
            await refreshReadiness()
        }
    }

    /// The way out of a corrupt ownership file, which nothing else may overwrite.
    public func resetOwnership() {
        Task { recordReset(await ownership.resetCorruptState()) }
    }

    public func requestMicrophone() {
        switch environment.microphoneState() {
        case .denied, .restricted:
            // macOS asks only once, so after that only System Settings can change the answer.
            environment.openMicrophoneSettings()
        case .authorized, .notDetermined:
            Task {
                await environment.askForMicrophone()
                await refreshReadiness()
            }
        }
    }

    public func requestAccessibility() {
        environment.askForAccessibility()
    }

    public var isActive: Bool { controller.isActive }
    /// A disposable launch has its own fixtures, so it needs no model.
    var canPractice: Bool { environment.models == nil || speechModelIsInstalled }
    var practiceIsShown: Bool { isEnabled && canPractice }

    /// The window holds the practice field, because the form's rows come and go as it scrolls.
    public func practiceWindowChanged(_ holder: UUID, isKey: Bool) {
        practice.show(holder, isKey: isKey)
    }

    public func practiceWindowClosed(_ holder: UUID) {
        practice.hide(holder)
    }

    public func settingsWindowChanged(isKey: Bool) {
        practiceWindowChanged(settingsWindowHolder, isKey: isKey)
    }

    public func settingsWindowClosed() {
        practiceWindowClosed(settingsWindowHolder)
    }
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
    public var canPasteLast: Bool { controller.hasPastableText && mayPaste }
    public var canPasteUnpolished: Bool { canPasteAlternate && !controller.lastText.alternateIsOriginal }
    public var canPasteOriginal: Bool { canPasteAlternate && controller.lastText.alternateIsOriginal }
    private var canPasteAlternate: Bool { controller.hasAlternateText && mayPaste }
    /// A paste takes the same admission as a dictation, so it is refused without ownership.
    private var mayPaste: Bool { ownership.state == .owned && !controller.isActive }
    /// A failed handoff disarms the shortcut again, so its conflict outlives the registration.
    public var shortcutIsUnavailable: Bool {
        controller.shortcut.availability == .unavailable || handoffProblem == .shortcutTaken
    }
    public var lastHandoffFailed: Bool { handoffProblem == .failed }
    public var canTakeOwnership: Bool { ownership.state == .available }
    public var canResetOwnership: Bool { ownership.state == .unavailable(.corruptState) }

    // MARK: AppServices

    var dictationAdmission: DictationAdmission { ownership.admission }
    var dictationTriggersMayArm: Bool { ownership.armsTriggers }

    var dictationShortcutRegistrar: DictationShortcut.Registrar? {
        guard !usesTemporaryMeetingStore else { return nil }
        return DictationShortcut.liveRegistrar
    }

    func makeDictationSessionDependencies() -> DictationSessionDependencies {
        practice.route(unroutedDependencies(), appIsActive: NSApplication.shared.isActive && practiceIsShown)
    }

    private func unroutedDependencies() -> DictationSessionDependencies {
        var dependencies = usesTemporaryMeetingStore
            ? fixtureDependencies() : .live(services: self, beginCapture: { {} })
        dependencies.beginHistory = { [weak self] in self?.history.admit() }
        dependencies.recordStats = { [weak self] sample in self?.stats.record(sample) }
        return dependencies
    }

    private func fixtureDependencies() -> DictationSessionDependencies {
        var dependencies = DictationUITestFixture.dependencies(
            fixture: fixture, admission: dictationAdmission, beginCapture: { {} })
        dependencies.waitForFeedbackDismissal = DictationUITestFixture.waitHoldingUnverifiedNotices
        dependencies.storesPreferencesTemporarily = true
        dependencies.polishDictation = DictationUITestFixture.polishing(fixture)
        dependencies.translateDictation = DictationUITestFixture.translating(fixture)
        if let fixture, fixture.correctsByVoice {
            dependencies.captureDestination = { DictationUITestFixture.correctionDestination(fixture) }
        }
        return dependencies
    }

    func acquireLiveTranscriptionRuntime(for purpose: LiveSpeechPurpose) async throws -> LiveTranscriptionRuntime {
        if purpose.selectedEngine(in: defaults) == .appleSpeech {
            let engine = try await SpeechAnalyzerLiveEngine.acquireInstalled(language: purpose.language(in: defaults))
            return LiveTranscriptionRuntime(engine: engine, lane: .appleSpeech) {}
        }
        let engine = try await warmEngine.acquire()
        let lane = LiveSpeechSelection(checkpoint: engine.checkpoint)
        return LiveTranscriptionRuntime(engine: engine, lane: lane) { [warmEngine] in warmEngine.releaseWhenIdle() }
    }

    // MARK: Private

    private var armForHandoff: @MainActor () -> Bool {
        { [weak self] in
            guard let self else { return false }
            syncDictationTriggers()
            return controller.shortcut.availability != .unavailable
        }
    }

    func recordHandoff(_ outcome: HandoffOutcome?) {
        handoffProblem = outcome.flatMap { HandoffProblem($0) }
    }

    /// No change means another app's reset landed first, which fixed the file just the same.
    func recordReset(_ change: OwnershipChange) {
        lastResetFailed = change == .busy || change == .failed
    }

    private func ownershipChanged(from previous: ParticipantState) {
        syncDictationTriggers()
        if previous == .owned, ownership.state != .owned { warmEngine.release() }
        if previous != .owned, ownership.state == .owned { prewarmIfConfigured() }
    }

    var prewarmConditions: DictationPrewarmPolicy.Conditions {
        DictationPrewarmPolicy.Conditions(
            dictationEnabled: dictationAdmission.isEligible(),
            prewarmEnabled: defaults.bool(forKey: DictationPrewarmPolicy.defaultsKey),
            profile: DictationModelMemory.current(in: defaults),
            engine: LiveSpeechPurpose.dictation.selectedEngine(in: defaults),
            underPressure: pressure.isActive,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            temporaryStore: usesTemporaryMeetingStore)
    }

    /// Loads only an installed, verified model, because `warmEngine` never downloads.
    func prewarmIfConfigured() {
        guard DictationPrewarmPolicy.shouldWarm(prewarmConditions) else { return }
        Task {
            guard (try? await warmEngine.acquire()) != nil else { return }
            warmEngine.releaseWhenIdle()
        }
    }

    func modelMemoryChanged() {
        warmEngine.idleLimitChanged()
        prewarmIfConfigured()
    }

    func memoryPressureChanged(isUnderPressure: Bool) {
        pressure.isActive = isUnderPressure
        if isUnderPressure { warmEngine.release() }
    }

    private func watchMemoryPressure() {
        guard memoryPressure == nil, !usesTemporaryMeetingStore else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated { self?.memoryPressureChanged(isUnderPressure: event != .normal) }
        }
        source.activate()
        memoryPressure = source
    }

    func triggersChanged(promptIfNeeded: Bool = false) {
        syncDictationTriggers(promptIfNeeded: promptIfNeeded)
    }

    private func syncDictationTriggers(promptIfNeeded: Bool = false) {
        if !isRecordingShortcut { controller.syncHotkey(services: self) }
        syncPasteLastShortcut()
        syncEventTaps(promptIfNeeded: promptIfNeeded)
    }

    func syncPasteLastShortcut() {
        pasteLastRegistration?.unregister()
        pasteLastRegistration = nil
        let wanted = !isRecordingShortcut && dictationTriggersMayArm
            && defaults.bool(forKey: DictationController.defaultsKey)
            && defaults.bool(forKey: PasteLastShortcut.defaultsKey)
        guard wanted, let pasteLastRegistrar else {
            pasteLastShortcutIsUnavailable = false
            return
        }
        pasteLastRegistration = pasteLastRegistrar(
            PasteLastShortcut.setting, { [weak self] in self?.pasteLast() }, {})
        pasteLastShortcutIsUnavailable = pasteLastRegistration == nil
    }

    /// Freed while the recorder listens for a combination, or pressing a current one would act on it.
    func shortcutRecording(_ isRecording: Bool) {
        isRecordingShortcut = isRecording
        if isRecording { controller.shortcut.pause() }
        triggersChanged()
    }

    /// Safe on any hint: unlike the hotkey, a tap already in place is left alone, so a held key keeps its release.
    private func syncEventTaps(promptIfNeeded: Bool = false) {
        controller.syncMousePTT(services: self, promptIfNeeded: promptIfNeeded)
        controller.syncModifierPTT(services: self, promptIfNeeded: promptIfNeeded)
    }

    func refreshReadiness() async {
        microphoneIsAuthorized = environment.microphoneState() == .authorized
        accessibilityIsGranted = environment.accessibilityIsGranted()
        guard let models = environment.models else {
            ownership.reevaluate()
            return
        }
        let speech = await models.isVerified(.speech)
        let detector = await models.isVerified(.speechDetector)
        // A cancelled check stops hashing and reports the files as bad, which says nothing about them.
        guard !Task.isCancelled else { return }
        showModels(speechIsInstalled: speech, detectorIsInstalled: detector)
        watchReadiness()
        await models.remember(.speech, speech)
        await models.remember(.speechDetector, detector)
    }

    /// A model hashed on an earlier launch and unchanged since need not read as missing during
    /// this launch's first hash, which still runs and takes this back if the files are bad.
    private func showRememberedModels() async {
        guard let models = environment.models, await models.wasVerified(.speech) else { return }
        showModels(speechIsInstalled: true, detectorIsInstalled: await models.wasVerified(.speechDetector))
    }

    /// Without the detector the speech gate fails open, so only the speech model holds dictation back.
    private func showModels(speechIsInstalled: Bool, detectorIsInstalled: Bool) {
        if speechIsInstalled, detectorIsInstalled {
            modelState = .ready
        } else if modelState == .ready {
            modelState = .missing
        }
        speechModelIsInstalled = speechIsInstalled
        readiness.modelIsInstalled.withLock { $0 = speechIsInstalled }
        ownership.reevaluate()
        syncEventTaps()
    }

    /// A permission changed in System Settings may never activate this agent app, so look again:
    /// soon while one is missing, and now and then otherwise. A damaged model is hashed in full
    /// on each look, so a missing one never sets the fast pace.
    static func readinessPollDelay(missing: String?) -> Duration {
        missing == nil || missing == ReadinessGap.missingModel ? .seconds(30) : .seconds(2)
    }

    private func watchReadiness() {
        readinessPoll?.cancel()
        readinessPoll = nil
        guard isEnabled else { return }
        let delay = Self.readinessPollDelay(missing: readiness.current())
        readinessPoll = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refreshReadiness()
        }
    }
}

/// What the protocol reads off the main actor. Permissions are read live, so every admission
/// sees the truth; only the model's state is cached, because reading it can touch the disk.
final class ReadinessGap: Sendable {
    static let missingModel = "model"
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
        if !modelIsInstalled.withLock({ $0 }) { return Self.missingModel }
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

extension DictationFeature {
    /// Settings and onboarding share one install, so neither reports the other's result as its own.
    func installModels() async throws {
        guard let models = environment.models else { return }
        if let modelInstall { return try await modelInstall.value }
        if modelState != .ready { modelState = .downloading }
        modelDownloadFraction = nil
        modelInstallGeneration += 1
        let generation = modelInstallGeneration
        let install = Task { [weak self] in
            try await models.installMissing { fraction in
                Task { @MainActor in self?.modelDownloaded(fraction, generation: generation) }
            }
        }
        modelInstall = install
        defer {
            modelInstall = nil
            modelDownloadFraction = nil
        }
        do {
            try await install.value
            modelState = .ready
        } catch {
            modelState = .failed
            throw error
        }
    }

    /// Reports arrive on separate tasks, so a late one must not move the bar back or reach another install.
    func modelDownloaded(_ fraction: Double, generation: Int) {
        guard modelInstall != nil, generation == modelInstallGeneration else { return }
        modelDownloadFraction = max(modelDownloadFraction ?? 0, fraction)
    }
}
