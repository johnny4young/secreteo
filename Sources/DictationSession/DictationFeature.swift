import AppKit
import ApplicationServices
import DictationKit
import DictationOwnership
import Foundation
import LiveSpeech
import LocalModelStore
import MicCapture
import Observation
import SpeechCore
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

    /// On in every build since 0.1.0 (D28); a project setting can still turn it off.
    public static var mayRunInThisBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "SecreteoGlobalDictation") as? String == "YES"
    }

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let usesTemporaryMeetingStore: Bool
    @ObservationIgnored let microphonePermissions = MicrophonePermissionClient()
    @ObservationIgnored let modelStore: LocalModelStore
    @ObservationIgnored private let fixture: DictationUITestFixture?
    @ObservationIgnored let launchArguments: [String]
    @ObservationIgnored private(set) lazy var timingLog = DictationTimingLog(
        arguments: launchArguments, bundleIdentifier: Bundle.main.bundleIdentifier)
    @ObservationIgnored let environment: DictationFeatureEnvironment
    @ObservationIgnored private let ownership: DictationOwnershipCoordinator
    @ObservationIgnored let readiness: ReadinessGap
    @ObservationIgnored let warmEngine: WarmModel<ParakeetEngine>
    @ObservationIgnored let warmSpeechDetector: WarmModel<SileroVoiceActivityModel>
    /// Parts already claimed on this verified stretch, so 30 s readiness polls skip redundant adoption.
    @ObservationIgnored var adoptedParts: Set<DictationModels.Part> = []
    /// Engines whose model loaded this launch, so Core ML already holds their compiled copy.
    @ObservationIgnored var compiledEngines: Set<LiveSpeechSelection> = []
    @ObservationIgnored private var readinessPoll: Task<Void, Never>?
    @ObservationIgnored private var modelInstall: Task<Void, any Error>?
    @ObservationIgnored private var modelInstallParts: Set<DictationModels.Part> = []
    @ObservationIgnored private(set) var modelInstallGeneration = 0
    @ObservationIgnored private var memoryPressure: (any DispatchSourceMemoryPressure)?
    @ObservationIgnored let pressure = DictationMemoryPressure()
    /// Registers the fixed shortcuts, Paste Last and Rewrite; tests inject one.
    @ObservationIgnored var fixedShortcutRegistrar: DictationShortcut.Registrar?
    @ObservationIgnored private var pasteLastRegistration: (any GlobalHotkeyRegistration)?
    @ObservationIgnored private(set) var isRecordingShortcut = false
    @ObservationIgnored var rewriteSelectionRegistration: (any GlobalHotkeyRegistration)?
    @ObservationIgnored let selectionRewrite = SelectionRewriteController()
    /// Bumped on every write, because `UserDefaults` is not observable.
    var preferenceRevision = 0
    var portavozImport: PortavozPreferenceImport?
    @ObservationIgnored private var preferencesObserver: (any NSObjectProtocol)?
    let controller: DictationController
    @ObservationIgnored let practice = DictationPracticeField()
    @ObservationIgnored let dictationStore: any DictationHistoryStore & DictationStatsStore & DictationEmbeddingStore
    @ObservationIgnored let history: DictationHistoryModel
    @ObservationIgnored let stats: DictationStatsModel
    @ObservationIgnored private let pendingWrites: DictationPendingWrites
    @ObservationIgnored let settingsWindowHolder = UUID()

    /// Created on first use, because creating it writes the initial text mode.
    @ObservationIgnored var textSettingsIfCreated: DictationTextSettingsModel?

    public internal(set) var modelState = ModelState.missing
    /// Nil until the store reports bytes, so the bar starts indeterminate.
    private(set) var modelDownloadFraction: Double?
    let ultra = SpeechUltraDownload()
    let modelList = DictationModelList()
    private(set) var speechModelIsInstalled = false
    private(set) var detectorIsInstalled = false
    public private(set) var isEnabled: Bool
    public private(set) var microphoneIsAuthorized: Bool
    public private(set) var accessibilityIsGranted: Bool
    /// A disposable launch reads practice as done unless a test seeds it missing.
    var practiceIsComplete = false
    /// Whether macOS leaves the 🌐 key alone, read again with the permissions.
    var fnKeyIsFree = false
    private(set) var handoffProblem: HandoffProblem?
    public private(set) var lastResetFailed = false
    private(set) var pasteLastShortcutIsUnavailable = false
    var rewriteSelectionShortcutIsUnavailable = false

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
        let scratchModels = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let modelStore = try LocalModelStore(
            location: usesTemporaryStore ? .directory(scratchModels) : .userLibrary,
            consumer: StoreConsumer(bundleID: identifier, displayName: "Secreteo"))
        self.modelStore = modelStore
        let dictationStore = Self.openDictationStore(
            usesTemporaryStore: usesTemporaryStore, bundleIdentifier: identifier)
        self.dictationStore = dictationStore
        // A disposable launch ranks with fixture concepts, so tests never need the system model.
        let embedding: (any DictationTextEmbedding)? = usesTemporaryStore
            ? DictationFixtureEmbedding() : SystemSentenceEmbedding()
        history = DictationHistoryModel(
            store: dictationStore,
            semantic: embedding.map { DictationSemanticIndex(store: dictationStore, embedding: $0) })
        let pendingWrites = DictationPendingWrites()
        self.pendingWrites = pendingWrites
        stats = DictationStatsModel(store: dictationStore, pendingWrites: pendingWrites)
        fixture = DictationUITestFixture(arguments: arguments, usesTemporaryStore: usesTemporaryStore)
        launchArguments = arguments
        let environment = environment ?? (usesTemporaryStore
            ? .disposable(arguments: arguments) { .shelf(store: modelStore, root: scratchModels) }
            : .live(microphone: microphonePermissions, models: .live(
                store: modelStore, defaults: defaults, seedRoot: DictationModels.portavozModels)))
        self.environment = environment
        microphoneIsAuthorized = environment.microphoneState() == .authorized
        accessibilityIsGranted = environment.accessibilityIsGranted()
        fnKeyIsFree = ModifierKeySetting.systemFnKeyIsFree(usage: environment.fnKeyUsage())
        let seedsLegacyPeer = usesTemporaryStore && arguments.contains("-seed-dictation-legacy-peer")
        let readiness = ReadinessGap(isDisposable: usesTemporaryStore, defaults: defaults)
        self.readiness = readiness
        let ownership = DictationOwnershipCoordinator.live(
            defaults: defaults, usesTemporaryStore: usesTemporaryStore,
            missingForReadiness: { readiness.current() }, seedsLegacyPeer: seedsLegacyPeer,
            seedsCorruptState: usesTemporaryStore && arguments.contains("-seed-dictation-corrupt-ownership"),
            pendingWrites: pendingWrites)
        self.ownership = ownership
        // Two apps must not each keep a model warm.
        // UserDefaults is thread-safe.
        nonisolated(unsafe) let engineDefaults = defaults
        warmEngine = WarmModel(
            idleLimit: { [pressure] in DictationModelMemory.idleLimit(in: defaults, pressure: pressure) },
            mayKeep: { ownership.state == .owned },
            load: { try await Self.loadSpeechModel(store: modelStore, defaults: engineDefaults) })
        warmSpeechDetector = Self.makeWarmSpeechDetector(
            store: modelStore, defaults: defaults, pressure: pressure, ownership: ownership)
        controller = DictationController()
        practice.onForget = { [controller] in controller.practiceLastText.clear() }
        practice.onVerifiedDelivery = { [weak self] in self?.completePractice() }
        fixedShortcutRegistrar = usesTemporaryStore ? nil : DictationShortcut.liveRegistrar
        // A learned correction writes here directly, and an open Settings window must show it.
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            // AppKit can register defaults while SwiftUI lays out text, and a change mid-update aborts.
            DispatchQueue.main.async { self?.preferenceRevision += 1 }
        }
        // A disposable launch owns its own scratch folder, because no user is there to take it.
        if usesTemporaryStore, !arguments.contains("-seed-dictation-no-owner") { ownership.claimScratchOwnership() }
        wireMemoryPressure()
    }

    public func start() {
        practiceIsComplete = practiceStartsComplete
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
            Task { [weak self] in
                for await _ in models.changes() {
                    guard let self else { break }
                    self.adoptedParts.removeAll()
                }
            }
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
        if !enabled {
            practice.clear()
            warmEngine.release()
            warmSpeechDetector.release()
            adoptedParts.removeAll()
        }
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

    /// A replay is never a rewrite instruction.
    public func pasteLast(alternate: Bool = false) {
        controller.pasteLastDictation(
            using: makeDictationSessionDependencies(capturesInstruction: false), alternate: alternate)
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
        environment.askForAccessibility { [weak self] in
            Task { await self?.refreshReadiness() }
        }
    }

    public var isActive: Bool { controller.isActive }

    /// Includes Stop, clipboard restoration, saves and undelivered words that can outlive the visible session.
    public func postponeUpdateRelaunch(until resume: @escaping () -> Void) -> Bool {
        ownership.postponeUpdateRelaunch(until: resume)
    }

    public func finishUpdateCycle() {
        ownership.finishUpdateCycle()
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
    /// A rewrite reads and replaces through the same admission as a paste.
    public var canRewriteSelection: Bool { mayPaste }
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
    /// The menu bar face: the capsule's face while a dictation runs, else whether this app owns dictation.
    public var statusFace: SecreteoGlyphFace {
        guard controller.phase == .idle, !controller.historyFailureShown else { return controller.statusFace }
        return ownership.state == .owned ? .ready : .notOwner
    }
    public var canResetOwnership: Bool { ownership.state == .unavailable(.corruptState) }

    // MARK: AppServices

    var dictationAdmission: DictationAdmission { ownership.admission }
    var dictationTriggersMayArm: Bool { ownership.armsTriggers }

    var dictationShortcutRegistrar: DictationShortcut.Registrar? {
        guard !usesTemporaryMeetingStore else { return nil }
        return DictationShortcut.liveRegistrar
    }

    func makeDictationSessionDependencies() -> DictationSessionDependencies {
        makeDictationSessionDependencies(capturesInstruction: true)
    }

    func unroutedDependencies() -> DictationSessionDependencies {
        var dependencies = usesTemporaryMeetingStore
            ? fixtureDependencies() : .live(services: self, beginCapture: { {} })
        dependencies.beginHistory = { [weak self] in self?.history.admit() }
        dependencies.pendingWrites = pendingWrites
        dependencies.recordStats = { [weak self] sample in self?.stats.record(sample) }
        dependencies.timingLog = timingLog.map { log in { log.append($0) } }
        return dependencies
    }

    private func fixtureDependencies() -> DictationSessionDependencies {
        var dependencies = DictationUITestFixture.dependencies(
            fixture: fixture, admission: dictationAdmission, beginCapture: { {} })
        dependencies.waitForFeedbackDismissal = DictationUITestFixture.waitHoldingFeedback
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
        if previous.armsTriggers, !ownership.state.armsTriggers { selectionRewrite.releaseGlobalKeys() }
        if ownership.state == .unavailable(.corruptState) { selectionRewrite.revokeReplace() }
        if previous == .owned, ownership.state != .owned {
            warmEngine.release()
            warmSpeechDetector.release()
        }
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

    func modelMemoryChanged() {
        warmEngine.idleLimitChanged()
        warmSpeechDetector.idleLimitChanged()
        prewarmIfConfigured()
    }

    func memoryPressureChanged(isUnderPressure: Bool) {
        pressure.changed(isActive: isUnderPressure)
    }

    func triggersChanged(promptIfNeeded: Bool = false) {
        syncDictationTriggers(promptIfNeeded: promptIfNeeded)
    }

    private func syncDictationTriggers(promptIfNeeded: Bool = false) {
        if !isRecordingShortcut { controller.syncHotkey(services: self) }
        syncPasteLastShortcut()
        syncRewriteSelectionShortcut()
        syncEventTaps(promptIfNeeded: promptIfNeeded)
    }

    func syncPasteLastShortcut() {
        pasteLastRegistration?.unregister()
        pasteLastRegistration = nil
        let wanted = !isRecordingShortcut && dictationTriggersMayArm
            && defaults.bool(forKey: DictationController.defaultsKey)
            && defaults.bool(forKey: PasteLastShortcut.defaultsKey)
        guard wanted, let fixedShortcutRegistrar else {
            pasteLastShortcutIsUnavailable = false
            return
        }
        pasteLastRegistration = fixedShortcutRegistrar(
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
        refreshFnKey()
        guard let models = environment.models else {
            ownership.reevaluate()
            return
        }
        // Apple Speech never loads Parakeet, so its 483 MB are not hashed on every look.
        let speech = speechModelIsRequired ? await models.isVerified(.speech) : nil
        let detector = await models.isVerified(.speechDetector)
        // A cancelled check stops hashing and reports the files as bad, which says nothing about them.
        guard !Task.isCancelled else { return }
        showModels(speechIsInstalled: speech ?? speechModelIsInstalled, detectorIsInstalled: detector)
        watchReadiness()
        if let speech { await models.remember(.speech, speech) }
        await models.remember(.speechDetector, detector)
        // Another app's install, or a crash before this app's claim, leaves files nobody here keeps.
        // Only while dictation uses them, so a model the person removed stays removed.
        await adoptVerifiedPart(.speech, isVerified: speech, using: models)
        await adoptVerifiedPart(.speechDetector, isVerified: detector, using: models)
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
/// sees permission changes. Model readiness and this app's persisted practice completion are synchronized.
final class ReadinessGap: Sendable {
    static let missingModel = "model"
    static let missingPractice = "practice"
    static let practiceCompletionKey = "dictationPracticeCompleted"
    let modelIsReady = Mutex(false)
    let practiceIsComplete: Mutex<Bool>
    private let isDisposable: Bool
    private let microphone: MicrophonePermissionClient
    private let accessibilityIsGranted: @Sendable () -> Bool

    init(
        isDisposable: Bool, microphone: MicrophonePermissionClient, practiceIsComplete: Bool = false,
        accessibilityIsGranted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.isDisposable = isDisposable
        self.microphone = microphone
        self.practiceIsComplete = Mutex(practiceIsComplete)
        self.accessibilityIsGranted = accessibilityIsGranted
    }

    @MainActor
    convenience init(isDisposable: Bool, defaults: UserDefaults) {
        self.init(
            isDisposable: isDisposable, microphone: MicrophonePermissionClient(),
            practiceIsComplete: defaults.bool(forKey: Self.practiceCompletionKey))
    }

    func current() -> String? {
        // A disposable launch has its own fixtures, so nothing real can be missing there.
        if isDisposable { return nil }
        if !modelIsReady.withLock({ $0 }) { return Self.missingModel }
        if microphone.state() != .authorized { return "microphone" }
        if !accessibilityIsGranted() { return "accessibility" }
        return practiceIsComplete.withLock { $0 } ? nil : Self.missingPractice
    }
}

enum DictationFeatureError: LocalizedError {
    case modelMissing

    var errorDescription: String? {
        L10n.text("The speech model is not installed. Download it in Settings.")
    }
}

extension DictationFeature {
    private func completePractice() {
        guard practiceIsShown else { return }
        store([ReadinessGap.practiceCompletionKey: true])
        readiness.practiceIsComplete.withLock { $0 = true }
        practiceIsComplete = true
        ownership.reevaluate()
        watchReadiness()
    }

    /// A permission changed in System Settings may never activate this agent app, so look again:
    /// soon while one is missing, and now and then otherwise. A damaged model is hashed in full
    /// on each look, so a missing one never sets the fast pace.
    static func readinessPollDelay(missing: String?) -> Duration {
        switch missing {
        case nil, ReadinessGap.missingModel, ReadinessGap.missingPractice: .seconds(30)
        default: .seconds(2)
        }
    }

    /// A model hashed on an earlier launch and unchanged since need not read as missing during
    /// this launch's first hash, which still runs and takes this back if the files are bad.
    fileprivate func showRememberedModels() async {
        guard let models = environment.models else { return }
        let speech = await models.wasVerified(.speech)
        guard speech || !speechModelIsRequired else { return }
        showModels(speechIsInstalled: speech, detectorIsInstalled: await models.wasVerified(.speechDetector))
    }

    fileprivate func showModels(speechIsInstalled: Bool, detectorIsInstalled: Bool) {
        speechModelIsInstalled = speechIsInstalled
        self.detectorIsInstalled = detectorIsInstalled
        applyModelReadiness()
    }

    /// Without the detector the speech gate fails open, so only Parakeet holds dictation back.
    func applyModelReadiness() {
        let speechIsReady = speechModelIsInstalled || !speechModelIsRequired
        if speechIsReady, detectorIsInstalled {
            if modelState != .downloading { modelState = .ready }
        } else if modelState == .ready {
            modelState = .missing
        }
        readiness.modelIsReady.withLock { $0 = speechIsReady }
        ownership.reevaluate()
        syncEventTaps()
    }

    /// Settings and onboarding share one install, so neither reports the other's result as its own.
    /// An install started for another engine is joined only when it covers this one's parts.
    func installModels() async throws {
        guard let models = environment.models else { return }
        let parts = requiredModels
        while let running = modelInstall {
            if modelInstallParts.isSuperset(of: parts) { return try await running.value }
            _ = try? await running.value
            if modelInstall == running { break }
        }
        if modelState != .ready { modelState = .downloading }
        modelDownloadFraction = nil
        modelInstallGeneration += 1
        let generation = modelInstallGeneration
        let install = Task { [weak self] in
            try await models.installMissing(parts) { fraction in
                Task { @MainActor in self?.modelDownloaded(fraction, generation: generation) }
            }
        }
        modelInstall = install
        modelInstallParts = Set(parts)
        defer {
            if modelInstall == install {
                modelInstall = nil
                modelDownloadFraction = nil
            }
        }
        do {
            try await install.value
            guard modelInstall == install else { return }
            modelState = Set(parts).isSuperset(of: requiredModels) ? .ready : .missing
        } catch {
            if modelInstall == install { modelState = .failed }
            throw error
        }
    }

    /// Reports arrive on separate tasks, so a late one must not move the bar back or reach another install.
    func modelDownloaded(_ fraction: Double, generation: Int) {
        guard modelInstall != nil, generation == modelInstallGeneration else { return }
        modelDownloadFraction = max(modelDownloadFraction ?? 0, fraction)
    }
}

extension DictationFeature {
    static func makeWarmSpeechDetector(
        store: LocalModelStore, defaults: UserDefaults, pressure: DictationMemoryPressure,
        ownership: DictationOwnershipCoordinator
    ) -> WarmModel<SileroVoiceActivityModel> {
        WarmModel(
            idleLimit: { [pressure] in DictationModelMemory.idleLimit(in: defaults, pressure: pressure) },
            mayKeep: { ownership.state == .owned },
            load: { try await SileroVoiceActivityModel.load(from: store) })
    }

    func wireMemoryPressure() {
        pressure.releases(warmEngine)
        pressure.releases(warmSpeechDetector)
        if let semantic = history.semantic {
            pressure.onPressure { Task { await semantic.invalidate() } }
        }
        pressure.whenItEnds { [weak self] in self?.prewarmIfConfigured() }
    }

    fileprivate func watchMemoryPressure() {
        guard memoryPressure == nil, !usesTemporaryMeetingStore else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated { self?.memoryPressureChanged(isUnderPressure: event != .normal) }
        }
        source.activate()
        memoryPressure = source
    }

    func acquireSpeechDetector(channel: AudioChannel) async throws -> AcquiredSpeechDetector {
        let model = try await warmSpeechDetector.acquire()
        let detector = model.makeDetector(channel: channel)
        let warm = warmSpeechDetector
        return AcquiredSpeechDetector(detector: detector) {
            Task { @MainActor in warm.releaseWhenIdle() }
        }
    }

    func adoptVerifiedPart(_ part: DictationModels.Part, isVerified: Bool?, using models: DictationModels) async {
        guard isVerified == true, modelsInUse.contains(part) else {
            adoptedParts.remove(part)
            return
        }
        guard adoptedParts.insert(part).inserted else { return }
        if !(await models.adopt(part)) {
            adoptedParts.remove(part)
        }
    }

    /// Loads only an installed, verified model, because `warmEngine` never downloads.
    func prewarmIfConfigured() {
        let conditions = prewarmConditions
        let engine = conditions.engine
        if DictationPrewarmPolicy.shouldWarm(conditions) {
            guard let prewarm = warmEngine.prewarm() else { return }
            Task {
                await prewarm.value
                if warmEngine.isHoldingModel { compiledEngines.insert(engine) }
            }
        } else if !compiledEngines.contains(engine), ownership.state == .owned,
            DictationPrewarmPolicy.shouldCompile(conditions), let compile = warmEngine.compileAhead() {
            Task {
                guard await compile.value else { return }
                compiledEngines.insert(engine)
                // A prewarm asked for during the load found the model busy.
                prewarmIfConfigured()
            }
        }
    }
}
