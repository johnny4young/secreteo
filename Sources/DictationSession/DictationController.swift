import AppKit
import MicCapture
import Carbon.HIToolbox
import Foundation
import Observation
import DictationKit
import LiveSpeech
import SpeechCore

/// System-wide dictation (the MacParakeet-validated surface): press the
/// global hotkey anywhere, speak, press it again — the transcript lands in
/// the captured original field, or stays available for explicit recovery.
/// Reuses the meeting pipeline as-is: Parakeet
/// streaming on the ANE, the caption coalescer's echo/noise hygiene, and
/// the user's custom vocabulary. Mic-only, nothing is stored: no meeting,
/// no database row, no audio file.
@MainActor
@Observable
final class DictationController {
    static let defaultsKey = "globalDictationEnabled"
    /// "auto" (or absent) lets the multilingual engine detect; "es"/"en"
    /// request the backend's script-aware filter without touching meeting settings.
    static let languageKey = "dictationLanguage"
    /// Bilingual hesitation-filler removal; on by default — polished text
    /// is the point of dictation, and the filter only ever drops tokens
    /// that are meaningless in both languages.
    static let fillerFilterKey = "dictationFillerFilter"
    /// The deterministic replacement rules as one JSON string
    /// (`DictationTextRules` codec).
    static let replacementsKey = "dictationReplacements"
    static let vocabularyKey = "customVocabulary"

    static func fillerFilterEnabled(in defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: fillerFilterKey) as? Bool) ?? true
    }

    enum Phase: Equatable {
        case idle
        case preparing
        case listening
        /// The paste is in flight: a second trigger can neither cancel nor restart it.
        case delivering
        case verified(Int)
        case dispatched(Int)
        /// The voice detector heard no speech; the text is offered, never pasted.
        case noSpeech
        case failed(String)
        case recovery(DictationDeliveryOutcome.Refusal)
    }

    var phase: Phase = .idle
    /// Rows confirmed by the engine so far (coalesced, echo-trimmed).
    private(set) var confirmedText = ""
    /// The still-changing tail of what's being said.
    private(set) var partialText = ""
    /// Mic peak with fast attack / slow decay (same VU feel as the HUD).
    private(set) var micLevel: Float = 0
    private(set) var microphoneNotice: String?
    var loadingModelSessionID: UUID?
    /// Why the last delivery kept its clean text; nil when it was polished or not asked to be.
    var polishNotice: String?
    /// What a spoken correction changed, shown instead of the inserted-words line.
    var correctionSummary: String?
    var learnableCorrection: DictationLearnableCorrection?
    @ObservationIgnored var lastInsertion: DictationInsertion?
    /// Observed: the strip shows "Polishing…" while a rewrite is pending.
    var polishRun = DictationPolishRun()
    @ObservationIgnored var dispatched: (id: UUID, slept: Bool)?

    /// The app that was frontmost when dictation started — where the text
    /// will land. The strip shows it so you never dictate "blind" (4b).
    private(set) var targetApp: String?
    /// The caret or pointer the strip opens beside, read with the destination.
    var panelAnchor: DictationPanelAnchor?
    var expandedSessionID: UUID?

    enum CopyStatus: Equatable { case idle, copied, failed }
    var recoveryText = ""
    /// Unresolved recovery words hold an accepted update's relaunch, since memory is their only copy.
    @ObservationIgnored var releaseRecoveryHold: (@MainActor () -> Void)?
    var copyStatus: CopyStatus = .idle
    var isRetryingDelivery = false
    var destination: CapturedDictationDestination?
    var dependencies: DictationSessionDependencies?
    var deliveryID: UUID?
    private(set) var history: DictationHistorySession?
    let historyFailure = DictationHistoryFailure()
    var statsDraft: DictationStatsDraft?
    @ObservationIgnored var retryDeliveryTask: Task<Void, Never>?

    let shortcut = DictationShortcut()
    private var mousePTT: MouseButtonPTT?
    private var mousePTTButton: Int?
    /// True while the active session was started by the mouse button, so
    /// only that button's release may deliver (`MousePTTGesture`).
    var mouseOwnsSession = false
    var modifierTrigger = ModifierTriggerState()
    var microphone: (any AudioCaptureSource)?
    private var feed: AsyncStream<AudioChunk>.Continuation?
    private var session: Task<Void, Never>?
    var stopTask: Task<Void, Never>?
    var stopIssuedSessionID: UUID?
    private var relayEndedSessionID: UUID?
    @ObservationIgnored let feedback = DictationFeedbackTimer()
    @ObservationIgnored var editLearningTask: Task<Void, Never>?
    var pressedSessionID: UUID?
    var sessionFeedbackWait: (@MainActor (Duration) async throws -> Void)?
    private(set) var activeSessionID: UUID?
    var measurement: DictationSessionMeasurementRecorder?
    /// The lane that transcribed this session, which can differ from the preference.
    @ObservationIgnored private(set) var sessionEngine: LiveSpeechSelection?
    var textPolicy = DictationTextPreferenceSnapshot.inert
    /// Set once delivery has prepared its text; a later panel choice could not apply.
    /// Only `start` clears it: between sessions `canChangeTextMode` is already false.
    var textPolicySealed = false
    let panel = DictationPanelController()
    let presentsPanel: Bool
    var sessionClock: (() -> Date)?
    @ObservationIgnored var cancelKey: (any GlobalHotkeyRegistration)?
    @ObservationIgnored var analysis = DictationSessionAnalysis()

    let lastText: DictationLastText
    /// Practice words are not the user's last dictation, so they must not replace it.
    let practiceLastText: DictationLastText

    init(presentsPanel: Bool = true, lastText: DictationLastText? = nil) {
        self.presentsPanel = presentsPanel
        // A headless controller never watches system sleep or lock.
        self.lastText = lastText ?? DictationLastText(observesSystem: presentsPanel)
        practiceLastText = DictationLastText(observesSystem: presentsPanel)
        self.lastText.onClear = { [weak self] in self?.forgetDictatedText() }
        self.lastText.onSystemSleep = { [weak self] in self?.systemWillSleep() }
    }

    /// Arms/disarms the push-to-talk mouse button to match the Settings
    /// toggle AND the recorded button. Separate from `syncHotkey` because
    /// the event tap needs Accessibility trust the Carbon hotkey does not;
    /// setup can prompt explicitly and returning from System Settings retries
    /// a tap that could not be created while permission was absent.
    func syncMousePTT(
        services: AppServices,
        promptIfNeeded: Bool = false
    ) {
        let enabled = services.dictationTriggersMayArm && UserDefaults.standard.bool(forKey: Self.defaultsKey)
        let storedButton = MouseButtonSetting.load()
        let desiredButton = enabled
            && MouseButtonSetting.isEligible(storedButton) ? storedButton : nil
        if mousePTT != nil, mousePTTButton == desiredButton { return }

        // Rebinding or disabling while the mouse owns capture would otherwise
        // discard the matching release event and strand a listening session.
        if mouseOwnsSession {
            retireTriggerOwnedSession()
        }
        mousePTT?.invalidate()
        mousePTT = nil
        mousePTTButton = nil
        guard !services.usesTemporaryMeetingStore, let desiredButton else { return }

        // Configuring a system-wide mouse trigger is the earliest useful time
        // to explain its Accessibility requirement. A denied/pending prompt
        // leaves the keyboard hotkey intact; applicationDidBecomeActive retries
        // after the user returns from System Settings.
        if promptIfNeeded {
            _ = TextInserter.canInsert(promptIfNeeded: true)
        }
        guard let ptt = MouseButtonPTT(
            button: desiredButton,
            // Admission does file I/O, so it leaves the event tap callback.
            onPress: { [weak self, weak services] in
                DispatchQueue.main.async {
                    guard let self, let services else { return }
                    self.handleMouse(.press) { self.start(services: services) }
                }
            },
            onRelease: { [weak self, weak services] in
                DispatchQueue.main.async {
                    guard let self, let services else { return }
                    self.handleMouse(.release) { self.start(services: services) }
                }
            })
        else { return }
        mousePTT = ptt
        mousePTTButton = desiredButton
    }

    /// Press-to-release lapse that separates a toggle TAP from a
    /// hold-to-talk gesture.
    static let holdThreshold: TimeInterval = 0.5
    var pressedAt: Date?

    /// The mic keeps capturing this long after the finish gesture so the
    /// tail of the last word survives — stopping on the release clips it
    /// mid-phoneme.
    var microphoneReadiness: DictationMicrophoneReadiness?
    var sessionLease: DictationLease?
    var yieldsToHandoff = false
    var handoffGrace: Task<Void, Never>?

    /// Hotkey press: start listening, or finish-and-insert if already on.
    func toggle(services: AppServices) {
        toggle(using: services.makeDictationSessionDependencies())
    }

    func toggle(using dependencies: DictationSessionDependencies) {
        if holdsProtectedRecovery { showPanel(); return }
        switch phase {
        case .idle, .failed, .verified, .dispatched, .noSpeech:
            start(using: dependencies)
        case .preparing:
            cancel()
        case .listening:
            finishAndInsert()
        case .delivering, .recovery:
            break
        }
    }

    func start(services: AppServices) {
        start(using: services.makeDictationSessionDependencies())
    }

    private func start(using dependencies: DictationSessionDependencies) {
        // A global trigger cannot silently replace refused or interrupted words
        // waiting in recovery. A dispatched result was already sent: a new
        // dictation replaces it and never re-sends the old output.
        if holdsProtectedRecovery { showPanel(); return }
        guard phase != .delivering,
              case .success(let lease) = dependencies.admission.acquire(dependencies.admissionKind)
        else { return }
        discardPreviousDelivery()
        adopt(lease)
        self.dependencies = dependencies
        sessionFeedbackWait = dependencies.waitForFeedbackDismissal
        measurement = DictationSessionMeasurementRecorder.make(for: dependencies)
        pressedAt = nil
        pressedSessionID = nil
        cancelFeedbackDismissal()
        // The paste needs Accessibility; ask BEFORE recording so the user
        // never dictates into a void.
        guard dependencies.canInsert() else {
            lease.release()
            self.dependencies = nil
            measurement?.finish(.permissionDenied)
            phase = .failed(L10n.text(
                // One-line UI copy.
                // swiftlint:disable:next line_length
                "Dictation needs the Accessibility permission to type into other apps — grant it in System Settings and try again."))
            showPanel()
            scheduleFeedbackDismiss(after: .seconds(6), wait: dependencies.waitForFeedbackDismissal)
            return
        }
        dependencies.sessionAdmitted()
        // Capture the destination BEFORE the non-activating panel appears —
        // the frontmost app is still the one the user will dictate into.
        let destination = dependencies.captureDestination()
        self.destination = destination
        targetApp = destination.name
        panelAnchor = dependencies.locatePanelAnchor()
        textPolicy = Self.textPolicy(for: dependencies, bundleIdentifier: destination.bundleIdentifier)
        textPolicySealed = false
        sessionEngine = nil
        phase = .preparing
        confirmedText = ""
        partialText = ""
        micLevel = 0
        microphoneNotice = nil
        polishNotice = nil
        correctionSummary = nil
        learnableCorrection = nil
        retireMicrophoneReadiness()
        stopTask?.cancel()
        stopTask = nil
        let sessionID = UUID()
        history = dependencies.beginHistory().map {
            DictationHistorySession(sessionID: sessionID, write: $0, pendingWrites: dependencies.pendingWrites)
        }
        activeSessionID = sessionID
        sessionClock = dependencies.now
        armCancelKey(dependencies, sessionID: sessionID)
        // Before the microphone opens, so the cue itself is never captured.
        dependencies.playCue(.start)
        showPanel()

        let capture = DictationCaptureOwnership(finish: dependencies.beginCapture())
        let measurement = self.measurement
        session = Task { [weak self] in
            await self?.runSession(
                id: sessionID, dependencies: dependencies, measurement: measurement, capture: capture)
            capture.end()
            await lease.releaseAfterDelivery()
        }
    }

    private func runSession(
        id: UUID, dependencies: DictationSessionDependencies,
        measurement: DictationSessionMeasurementRecorder?, capture: DictationCaptureOwnership
    ) async {
        var microphone: (any AudioCaptureSource)?
        let acquisition = DictationRuntimeAcquisition(acquire: dependencies.acquireRuntime)
        await runCapture(
            id: id, dependencies: dependencies, measurement: measurement,
            acquisition: acquisition, capture: capture, microphone: &microphone)
        // The lease outlives catch-path native cleanup, never the session.
        await acquisition.settle()
        // EOF can precede native teardown, and a cancelled session can overlap
        // its replacement. Retire only this source before releasing its owner.
        await microphone?.stop()
    }

    private func runCapture(
        id: UUID, dependencies: DictationSessionDependencies,
        measurement: DictationSessionMeasurementRecorder?,
        acquisition: DictationRuntimeAcquisition,
        capture: DictationCaptureOwnership,
        microphone: inout (any AudioCaptureSource)?
    ) async {
        var localFeed: AsyncStream<AudioChunk>.Continuation?
        var pump: Task<Void, Never>?
        do {
            let input = try await dependencies.authorizedMicrophone()
            guard activeSessionID == id else { return }
            microphone = input.source
            self.microphone = input.source
            measurement?.observeCapture(input.source)
            measurement?.noteInput(input.transport, replacedBluetooth: input.replacesBluetooth)
            microphoneNotice = input.notice
            // Audio-first: speech during a cold load waits in the bounded relay.
            acquisition.start()
            let readiness = makeMicrophoneReadiness(id: id, dependencies: dependencies, measurement: measurement)
            defer { readiness.finish() }
            monitorCaptureFailure(input.source, id: id)
            readiness.beginDeadline(wait: dependencies.waitForFirstBufferDeadline)
            await input.warmUp()
            try Task.checkCancellation()
            let micStream = try await input.source.start()
            try Task.checkCancellation()
            guard activeSessionID == id else { throw CancellationError() }
            // Stream construction can precede its first hardware callback.
            // Only an admitted nonempty buffer starts the capture clock.
            measurement?.record(.microphoneReady)

            // Dictation has no durable original to replay. A bounded relay
            // remains safe only when every dropped chunk revokes delivery.
            let (audio, feed) = AsyncStream.makeStream(
                of: AudioChunk.self,
                bufferingPolicy: .bufferingNewest(DictationRelayPolicy.capacity))
            localFeed = feed
            self.feed = feed
            let analysis = DictationSessionAnalysis(gate: dependencies.makeSpeechGate(), pause: dependencies
                .makePauseDetector { [weak self] in Task { @MainActor in self?.stopAfterPause(sessionID: id) } })
            self.analysis = analysis
            pump = startPump(
                readiness: readiness, stream: micStream, feed: feed, sessionID: id, measurement: measurement,
                mirror: analysis.offer)

            let runtime = try await awaitRuntime(acquisition, id: id, measurement: measurement)
            analysis.pause?.arm()
            try await consumeCaptions(
                from: runtime.engine.transcribe(audio, hints: dependencies.transcriptionHints()),
                sessionID: id, measurement: measurement)
            // Captions that end while audio still flows leave the rest untranscribed.
            if activeSessionID == id, relayEndedSessionID != id { throw rejectDelivery(id: id) }
            try await awaitCaptureCompletion(id: id, pump: pump, source: input.source)
            await deliver(sessionID: id, dependencies: dependencies, capture: capture)
        } catch {
            let cancelled = Task.isCancelled || activeSessionID != id
            let permissionDenied = (error as? DictationMicrophoneReadiness.Failure) == .permissionRequired
            measurement?.finish(cancelled ? .cancelled : (permissionDenied ? .permissionDenied : .pipelineFailed))
            await stopCapture(feed: localFeed, pump: pump, microphone: microphone)
            guard !Task.isCancelled, activeSessionID == id else { return }
            if let message = DictationMicrophoneReadiness.preparationMessage(for: error) {
                failSession(id: id, message: message, autoDismiss: false)
            } else if error is CancellationError {
                // Nothing was typed: keep it visible like a capture interruption.
                failSession(
                    id: id, message: LiveSpeechFailureMessage.dictation(DictationSessionError.unexpectedCompletion),
                    autoDismiss: false, keepsWords: true)
            } else {
                failSession(id: id, message: LiveSpeechFailureMessage.dictation(error), keepsWords: true)
            }
        }
    }

    /// Esc or the panel's cancel control: throw everything away.
    func cancel() {
        cancelEditLearning()
        releaseCancelKey()
        releaseSpeechGate()
        abandonPolish()
        retryDeliveryTask?.cancel()
        retryDeliveryTask = nil
        deliveryID = nil
        destination = nil
        dependencies = nil
        recoveryText = ""
        endRecoveryHold()
        targetApp = nil
        copyStatus = .idle
        isRetryingDelivery = false
        measurement?.finish(.cancelled)
        measurement = nil
        sessionFeedbackWait = nil
        activeSessionID = nil
        textPolicy = .inert
        sessionClock = nil
        confirmedText = ""
        partialText = ""
        micLevel = 0
        retireMicrophoneReadiness()
        mouseOwnsSession = false
        modifierTrigger.ownsSession = false
        stopTask?.cancel()
        stopTask = nil
        pressedAt = nil
        pressedSessionID = nil
        cancelFeedbackDismissal()
        session?.cancel()
        session = nil
        let microphone = self.microphone
        Task { await microphone?.stop() }
        self.microphone = nil
        feed?.finish()
        feed = nil
        phase = .idle
        panel.close()
    }

    private func deliver(
        sessionID: UUID, dependencies: DictationSessionDependencies, capture: DictationCaptureOwnership
    ) async {
        guard activeSessionID == sessionID, let destination else { return }
        // The two-tier dictionary's deterministic tier plus the filler
        // filter run on the final text only — meeting transcripts stay
        // verbatim records and never pass through here.
        let measurement = self.measurement
        let original = DictationAssembler.text(confirmed: confirmedText, partial: partialText)
        let text = textPolicy.applying(to: original)
        prepareHistory(original: original, text: text, dependencies: dependencies)
        // Stop bookkeeping retires below while the phase stays active until the
        // insertion settles; the panel must not offer a choice that cannot apply.
        textPolicySealed = true
        measurement?.record(.textPrepared)
        microphone = nil
        feed = nil
        stopTask = nil
        retireMicrophoneReadiness()
        guard DictationAssembler.hasLexicalContent(text) else {
            measurement?.finish(.empty)
            completeSession(id: sessionID)
            self.destination = nil
            self.dependencies = nil
            phase = .idle
            panel.close()
            return
        }
        releaseCancelKey()
        phase = .delivering
        showPanel()
        // Nothing optional runs for words that cannot be delivered: the other app is waiting for the lease.
        guard !yieldsToHandoff, sessionLease?.revalidate() != false else {
            refuseDelivery(text, sessionID: sessionID)
            return
        }
        if let gate = analysis.gate, await gate.verdict() == .noSpeech {
            guard activeSessionID == sessionID else { return }
            presentNoSpeech(text, id: sessionID)
            return
        }
        // A cancel during the verdict ends it as undetermined, so it lands here.
        guard activeSessionID == sessionID else { return }
        if await correctsLastInsertion(original: original, sessionID: sessionID, dependencies: dependencies) { return }
        guard activeSessionID == sessionID, let delivery = await textToDeliver(
            text, original: original, sessionID: sessionID, dependencies: dependencies, capture: capture)
        else { return }
        let delivered = delivery.text
        // Rules run before Polish and translation, so only text they produced can teach one.
        let learnsEdits = textPolicy.mode.appliesCleanRules && delivered == text
            && dependencies.admissionKind == .global && !dependencies.deliversInternally
        destination.armEditAnchors(learnsEdits)
        measurement?.record(.deliveryStarted)
        // Read again here: polish may have taken a while since the check above.
        let stillOwner = dispatchesInsert(sessionID: sessionID)
        let result = stillOwner ? await destination.insert(delivered) : .refused(.ownershipChanged)
        measurement?.finishDelivery(result)
        guard activeSessionID == sessionID else { return }
        completeSession(id: sessionID)
        deliveryID = sessionID
        presentDelivery(
            result, text: delivered, alternate: delivery, id: sessionID, canLearnEdits: learnsEdits)
    }

    func completeSession(id: UUID) {
        guard activeSessionID == id else { return }
        releaseCancelKey()
        releaseSpeechGate()
        activeSessionID = nil
        textPolicy = .inert
        sessionClock = nil
        pressedAt = nil
        pressedSessionID = nil
        sessionFeedbackWait = nil
        session = nil
        microphone = nil
        feed = nil
        stopTask = nil
        retireMicrophoneReadiness()
        mouseOwnsSession = false
        modifierTrigger.ownsSession = false
    }
}

extension DictationController {
    private var holdsProtectedRecovery: Bool {
        switch phase {
        case .recovery: true
        case .failed: !recoveryText.isEmpty
        default: false
        }
    }

    /// - Parameter keepsWords: a capture failure leaves what was heard reachable for Copy
    ///   and Paste last, since nothing else can bring those words back.
    func failSession(id: UUID, message: String, autoDismiss: Bool = true, keepsWords: Bool = false) {
        guard activeSessionID == id else { return }
        let wait: @MainActor (Duration) async throws -> Void = sessionFeedbackWait
            ?? { try await Task.sleep(for: $0) }
        let heard = keepsWords ? heardWords() : nil
        completeSession(id: id)
        destination = nil
        if heard != nil { deliveryID = id }
        keepAfterFailure(heard)
        phase = .failed(message)
        if heard != nil { showPanel() }
        if autoDismiss, heard == nil { scheduleFeedbackDismiss(after: .seconds(6), wait: wait) }
    }

    private func systemWillSleep() {
        cancelEditLearning()
        // A dispatched edit must finish its clipboard restore. Anything before it, polish
        // included, can still be cancelled without pasting, with Stop and the lease draining normally.
        if phase == .delivering, dispatched?.id == activeSessionID {
            dispatched?.slept = true
            return
        }
        guard phase == .preparing || phase == .listening || phase == .delivering else { return }
        let heard = heardWords()
        let recoveryDependencies = heard == nil ? nil : dependencies
        cancel()
        // Copy uses the session's sink; its destination and retry token stay cancelled.
        dependencies = recoveryDependencies
        recoveryText = heard ?? ""
        if heard != nil { deliveryID = UUID() }
        holdRecoveryForUpdate()
        phase = .failed(DictationMicrophoneReadiness.Failure.interrupted.message)
        showPanel()
    }

    /// From here sleep lets the delivery finish instead of cancelling it.
    private func dispatchesInsert(sessionID: UUID) -> Bool {
        dispatched = (sessionID, false)
        return !yieldsToHandoff && sessionLease?.revalidate() != false
    }

    /// Sleep already ended Paste last; a delivery it let finish must not bring it back.
    func renewsPasteLast(_ id: UUID) -> Bool {
        dispatched?.id != id || dispatched?.slept != true
    }

    /// When Paste last ends, the same words leave the session's state too, unless a session is using them.
    private func forgetDictatedText() {
        guard !isActive else { return }
        cancelEditLearning()
        confirmedText = ""
        partialText = ""
        lastInsertion = nil
        history?.forgetDraft()
    }

    /// Read before the session completes, while its text policy still applies.
    /// An internal destination's words are not dictation, so Paste last never keeps them.
    private func heardWords() -> String? {
        guard dependencies?.deliversInternally != true else { return nil }
        let heard = textPolicy.applying(to: DictationAssembler.text(confirmed: confirmedText, partial: partialText))
        return DictationAssembler.hasLexicalContent(heard) ? heard : nil
    }

    private func keepAfterFailure(_ heard: String?) {
        guard let heard else {
            dependencies = nil
            return
        }
        sessionLastText.remember(heard)
        recoveryText = heard
        holdRecoveryForUpdate()
        copyStatus = .idle
    }
}

private extension DictationController {
    func awaitRuntime(
        _ acquisition: DictationRuntimeAcquisition, id: UUID,
        measurement: DictationSessionMeasurementRecorder?
    ) async throws -> LiveTranscriptionRuntime {
        loadingModelSessionID = id
        defer { if loadingModelSessionID == id { loadingModelSessionID = nil } }
        let runtime = try await acquisition.runtime()
        measurement?.record(.runtimeReady)
        try Task.checkCancellation()
        guard activeSessionID == id else { throw CancellationError() }
        sessionEngine = runtime.lane
        if let lane = runtime.lane { measurement?.noteEngine(lane.rawValue) }
        return runtime
    }

    func awaitCaptureCompletion(
        id: UUID, pump: Task<Void, Never>?, source: any AudioCaptureSource
    ) async throws {
        // Reject recognizer EOF before joining a producer that may still be live.
        guard stopIssuedSessionID == id else { throw rejectDelivery(id: id) }
        let nativeStop = stopTask
        await pump?.value
        await nativeStop?.value
        try Task.checkCancellation()
        guard activeSessionID == id else { throw CancellationError() }
        try verifyCaptureIntegrity(source: source, id: id)
    }

    func monitorCaptureFailure(_ source: any AudioCaptureSource, id: UUID) {
        (source as? any CaptureReportingSource)?.setCaptureFailureHandler { [weak self] in
            Task { @MainActor [weak self] in self?.failCapture(id: id) }
        }
    }

    func makeMicrophoneReadiness(
        id: UUID, dependencies: DictationSessionDependencies,
        measurement: DictationSessionMeasurementRecorder?
    ) -> DictationMicrophoneReadiness {
        let readiness = DictationMicrophoneReadiness(now: dependencies.now, onReady: { [weak self] in
            guard let self, activeSessionID == id, phase == .preparing else { return }
            phase = .listening
        }, onFailure: { [weak self] failure in
            guard let self, activeSessionID == id else { return }
            // The session task then unwinds as cancelled; keep the real outcome.
            measurement?.finish(.pipelineFailed)
            session?.cancel()
            stopTask?.cancel()
            feed?.finish()
            let source = microphone
            Task { await source?.stop() }
            // The relay only overflows while nothing drains it: the model is still loading.
            let message = failure == .interrupted && isLoadingModel
                ? L10n.text("The speech model took too long to load. Nothing was inserted. Try again in a moment.")
                : failure.message
            failSession(id: id, message: message, autoDismiss: false, keepsWords: true)
        })
        microphoneReadiness = readiness
        return readiness
    }

    func retireMicrophoneReadiness() {
        stopIssuedSessionID = nil
        relayEndedSessionID = nil
        microphoneReadiness?.finish()
        microphoneReadiness = nil
    }

    /// Native stop runs before the pump drains, on every failed or cancelled start.
    func stopCapture(
        feed: AsyncStream<AudioChunk>.Continuation?, pump: Task<Void, Never>?,
        microphone: (any AudioCaptureSource)?
    ) async {
        feed?.finish()
        pump?.cancel()
        await microphone?.stop()
        await pump?.value
    }

    func startPump(
        readiness: DictationMicrophoneReadiness, stream: AsyncThrowingStream<AudioChunk, Error>,
        feed: AsyncStream<AudioChunk>.Continuation, sessionID: UUID,
        measurement: DictationSessionMeasurementRecorder?,
        mirror: @escaping @Sendable (AudioChunk) -> Void
    ) -> Task<Void, Never> {
        readiness.pump(
            stream: stream, feed: feed, mirror: mirror,
            onInputEnded: { [weak self] in
                if let measurement { await measurement.record(.inputEnded) }
                await self?.markRelayEnded(sessionID)
            },
            onRelayDrop: { frames in
                if let measurement { await measurement.noteRelayDrop(frames: frames) }
            },
            updateMeter: { [weak self] peak in
                guard let self, activeSessionID == sessionID else { return }
                measurement?.record(.firstBufferHandled)
                measurement?.noteBuffer(peak: peak)
                micLevel = max(peak, micLevel * 0.8)
            })
    }

    func consumeCaptions(
        from stream: AsyncThrowingStream<TranscriptSegment, Error>,
        sessionID: UUID, measurement: DictationSessionMeasurementRecorder?
    ) async throws {
        var transcript = DictationTranscriptProjection()
        for try await segment in stream {
            try Task.checkCancellation()
            guard activeSessionID == sessionID else { throw CancellationError() }
            measurement?.record(.firstCaptionHandled)
            if transcript.apply(segment) {
                confirmedText = transcript.confirmedText
            }
            if partialText != transcript.partialText {
                partialText = transcript.partialText
            }
        }
        // A cancelled AsyncStream can finish normally, without throwing.
        try Task.checkCancellation()
        guard activeSessionID == sessionID else { throw CancellationError() }
        measurement?.record(.transcriptionEnded)
        confirmedText = transcript.finalText
        partialText = ""
    }

    func failCapture(id: UUID) {
        // Once delivery relinquishes capture, a late report cannot promise
        // to undo an already-dispatched edit.
        guard activeSessionID == id, microphone != nil else { return }
        microphoneReadiness?.failCapture()
    }

    func verifyCaptureIntegrity(source: any AudioCaptureSource, id: UUID) throws {
        if (source as? any CaptureReportingSource)?.captureReport.failure != nil {
            throw rejectDelivery(id: id)
        }
        // EOF without our actual Stop call can be device teardown, even
        // when the source omits a failure report.
        guard stopIssuedSessionID == id else { throw rejectDelivery(id: id) }
    }

    func markRelayEnded(_ id: UUID) {
        guard activeSessionID == id else { return }
        relayEndedSessionID = id
    }

    /// Fails the session even when readiness no longer accepts a rejection.
    func rejectDelivery(id: UUID) -> CancellationError {
        failCapture(id: id)
        if activeSessionID == id {
            measurement?.finish(.pipelineFailed)
            failSession(
                id: id, message: DictationMicrophoneReadiness.Failure.interrupted.message, autoDismiss: false,
                keepsWords: true)
        }
        return CancellationError()
    }
}
