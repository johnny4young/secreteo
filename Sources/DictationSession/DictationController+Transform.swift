import DictationKit
import Foundation
import LiveSpeech

/// The post-recognition steps that run between the speech gate and the paste.
enum DictationTransformKind: Equatable { case polish, translate }

enum DictationTransformResult: Equatable {
    case polish(DictationPolishOutcome)
    case translation(DictationTranslationOutcome)
}

/// One pending transform: the delivery waiting for it, the task, its token and kind.
struct DictationPolishRun {
    var wait: CheckedContinuation<DictationTransformResult?, Never>?
    var task: Task<Void, Never>?
    var token: UUID?
    var kind: DictationTransformKind?
}

// A session override changes text policy, never preferences or destination authority.
extension DictationController {
    var isActive: Bool { phase == .preparing || phase == .listening || phase == .delivering }
    /// When the first audio arrived, for the compact indicator's elapsed time.
    var captureStartedAt: Date? { microphoneReadiness?.firstFrameAt }
    static let noticeFeedbackDuration: Duration = .seconds(4)
    /// How long a result stays: the pill with a correction, or only the menu bar face.
    static let resultFeedbackDuration: Duration = .milliseconds(1600)
    /// Listening while the model still loads; the relay holds the speech.
    var isLoadingModel: Bool { loadingModelSessionID != nil && loadingModelSessionID == activeSessionID }
    var textMode: DictationTextMode { textPolicy.mode }
    var canChangeTextMode: Bool {
        isActive && activeSessionID != nil && !textPolicySealed && stopTask == nil
            && stopIssuedSessionID != activeSessionID
    }

    func selectTextMode(_ mode: DictationTextMode) {
        guard canChangeTextMode else { return }
        textPolicy.mode = mode
    }

    var textChoice: DictationTextChoice { textPolicy.choice }
    var translationTarget: DictationTranslationTarget { textPolicy.translationTarget }

    func selectTranslationTarget(_ target: DictationTranslationTarget) {
        guard canChangeTextMode else { return }
        textPolicy.translationTarget = target
    }

    /// The recipes read when this session started, for the strip's choice.
    var availableRecipes: [DictationRecipe] { textPolicy.recipes }

    func selectTextChoice(_ choice: DictationTextChoice) {
        guard canChangeTextMode else { return }
        textPolicy.mode = choice.mode
        textPolicy.recipeID = choice.recipeID
    }

    static func textPolicy(
        for dependencies: DictationSessionDependencies, bundleIdentifier: String?
    ) -> DictationTextPreferenceSnapshot {
        var policy = DictationTextPreferences.snapshot(in: dependencies.defaults, bundleIdentifier: bundleIdentifier)
        if let mode = dependencies.textModeOverride {
            policy.mode = mode
            policy.recipeID = nil
        }
        // An internal receiver takes the words as spoken; nothing is pasted to translate.
        if dependencies.deliversInternally { policy.translationTarget = .off }
        return policy
    }

    /// Polish rewrites inside `.delivering`, so every delivering guard still applies.
    var isPolishing: Bool { polishRun.token != nil && polishRun.kind == .polish }
    var isTranslating: Bool { polishRun.token != nil && polishRun.kind == .translate }

    /// Escape or the strip: paste the clean text now.
    /// Skips polish or translation, whichever is running.
    func skipPolish() {
        guard isPolishing || isTranslating else { return }
        endPolish(nil)
    }

    private static let stopTail: Duration = .milliseconds(250)

    /// False when the stop itself was cancelled. Silence after the gesture ends the wait early.
    static func stopTailEnded(
        wait: @escaping @MainActor (Duration) async throws -> Void, silence: DictationTrailingSilence
    ) async -> Bool {
        let tail = Task { @MainActor in try await wait(stopTail) }
        silence.onSilence { tail.cancel() }
        let outcome = await withTaskCancellationHandler { await tail.result } onCancel: { tail.cancel() }
        if Task.isCancelled { return false }
        if case .success = outcome { return true }
        return silence.isSilent
    }

    /// Second hotkey press or release of a held trigger: stop the mic; the drained stream delivers.
    func finishAndInsert(isHeld: Bool = false) {
        guard phase == .preparing || phase == .listening else { return }
        guard stopTask == nil else { return }
        measurement?.record(.stopRequested)
        guard DictationCapturePolicy.finishDecision(
            captureStartedAt: microphoneReadiness?.firstFrameAt,
            now: sessionClock?() ?? Date(), isHeld: isHeld) == .stopAfterTail
        else {
            cancel()
            return
        }
        guard let sessionID = activeSessionID else {
            cancel()
            return
        }
        let microphone = self.microphone
        guard let dependencies else {
            cancel()
            return
        }
        let playCue = dependencies.playCue
        let waitForTail = dependencies.waitForStopTail
        let silence = analysis.tail
        silence.finishRequested()
        // A stopping session is past preparing, so a later press or handoff cannot discard its words.
        if phase == .preparing { phase = .listening }
        stopTask = Task { [weak self] in
            guard await Self.stopTailEnded(wait: waitForTail, silence: silence) else { return }
            guard let self, self.activeSessionID == sessionID else { return }
            self.measurement?.noteTail(silence.report)
            self.stopIssuedSessionID = sessionID
            await microphone?.stop()
            playCue(.stop)
        }
    }
}

// Polish, translation, and session-owned auxiliaries (Escape key, speech gate, pause auto-stop).
extension DictationController {
    /// The clean text after Polish and translation when they apply; nil when the session ended.
    func textToDeliver(
        _ clean: String, original: String, sessionID: UUID, dependencies: DictationSessionDependencies,
        capture: DictationCaptureOwnership
    ) async -> DictationDeliveryText? {
        guard textPolicy.mode == .polish || textPolicy.translationTarget != .off else {
            return DictationDeliveryText(text: clean)
        }
        // The microphone is done; a large local model must not see live capture.
        capture.end()
        var delivery = DictationDeliveryText(text: clean)
        if textPolicy.mode == .polish {
            guard let polished = await polish(clean, original: original, sessionID: sessionID,
                                              dependencies: dependencies) else { return nil }
            delivery = polished
        }
        guard textPolicy.translationTarget != .off else { return delivery }
        guard let translated = await translate(delivery.text, sessionID: sessionID, dependencies: dependencies)
        else { return nil }
        guard translated != delivery.text else { return delivery }
        // History keeps the mode that produced the text before translation.
        let unpolishedMode: DictationTextMode = textPolicy.mode == .literal ? .literal : .clean
        let mode = delivery.alternate != nil ? DictationTextMode.polish : unpolishedMode
        reviseHistory(text: translated, original: original, mode: mode)
        return DictationDeliveryText(text: translated, alternate: delivery.text, alternateIsOriginal: true)
    }

    /// Nil when the session ended meanwhile. A skip, Escape or the strip's button,
    /// pastes the clean text at once; the rewrite is abandoned, never awaited.
    private func polish(
        _ clean: String, original: String, sessionID: UUID, dependencies: DictationSessionDependencies
    ) async -> DictationDeliveryText? {
        let terms = textPolicy.replacements.map(\.replacement)
        let vocabulary = textPolicy.vocabulary
        let recipe = textPolicy.polishRecipe?.instruction
        let end = await runTransform(.polish, sessionID: sessionID, dependencies: dependencies) {
            .polish(await dependencies.polishDictation(clean, terms, vocabulary, recipe))
        }
        switch end {
        case .ended:
            return nil
        case .finished(.polish(.polished(let polished))):
            reviseHistory(text: polished, original: original, mode: .polish)
            return DictationDeliveryText(text: polished, alternate: clean)
        case .finished(.polish(.kept(let skip))):
            polishNotice = Self.polishNotice(for: skip)
        case .skipped, .finished(.translation):
            polishNotice = L10n.text("Pasted without polish.")
        }
        reviseHistory(text: clean, original: original, mode: .clean)
        return DictationDeliveryText(text: clean)
    }

    /// The text untouched unless the system translator produced the target language.
    private func translate(
        _ text: String, sessionID: UUID, dependencies: DictationSessionDependencies
    ) async -> String? {
        guard let target = textPolicy.translationTarget.languageCode else { return text }
        let configured = dependencies.defaults.string(forKey: Self.languageKey)
        let source = ["es", "en"].contains(configured) ? configured : SpokenLanguageDetector.dictationLanguage(in: text)
        let end = await runTransform(.translate, sessionID: sessionID, dependencies: dependencies) {
            .translation(await dependencies.translateDictation(text, source, target))
        }
        switch end {
        case .ended:
            return nil
        case .finished(.translation(.translated(let translated))):
            return translated
        case .finished(.translation(.kept(let skip))):
            appendNotice(Self.translationNotice(for: skip))
        case .skipped, .finished(.polish):
            appendNotice(L10n.text("Pasted without translation."))
        }
        return text
    }

    private func appendNotice(_ notice: String?) {
        guard let notice else { return }
        polishNotice = [polishNotice, notice].compactMap { $0 }.joined(separator: " ")
    }

    private enum TransformEnd { case ended, skipped, finished(DictationTransformResult) }

    /// One bounded step with "Polishing…" or "Translating…" in the strip and Escape to skip it.
    private func runTransform(
        _ kind: DictationTransformKind, sessionID: UUID, dependencies: DictationSessionDependencies,
        work: @escaping @MainActor () async -> DictationTransformResult
    ) async -> TransformEnd {
        let token = UUID()
        polishRun.token = token
        polishRun.kind = kind
        showPanel()
        armPolishSkipKey(dependencies, sessionID: sessionID)
        let result: DictationTransformResult? = await withCheckedContinuation { continuation in
            polishRun.wait = continuation
            polishRun.task = Task { [weak self] in
                let result = await work()
                guard let self, self.polishRun.token == token else { return }
                self.endPolish(result)
            }
        }
        // Only a live session owns the key: a cancel already released this one's.
        guard activeSessionID == sessionID else { return .ended }
        releaseCancelKey()
        return result.map(TransformEnd.finished) ?? .skipped
    }

    /// Resumes the waiting delivery once; a late result after a skip is dropped.
    private func endPolish(_ result: DictationTransformResult?) {
        if result == nil { polishRun.task?.cancel() }
        let wait = polishRun.wait
        polishRun = DictationPolishRun()
        wait?.resume(returning: result)
    }

    func abandonPolish() {
        endPolish(nil)
        polishNotice = nil
    }

    private static func translationNotice(for skip: DictationTranslationSkip) -> String? {
        switch skip {
        case .sameLanguage:
            nil
        case .unknownLanguage:
            L10n.text("Pasted without translation: the dictation's language was not clear.")
        case .notInstalled:
            L10n.text("Pasted without translation: download the languages in Settings first.")
        case .unsupported:
            L10n.text("Pasted without translation: this language pair is not available on this Mac.")
        case .timedOut, .failed:
            L10n.text("Pasted without translation: the translator could not finish.")
        }
    }

    private func armPolishSkipKey(_ dependencies: DictationSessionDependencies, sessionID: UUID) {
        releaseCancelKey()
        cancelKey = dependencies.registerCancelKey { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == sessionID else { return }
                self.skipPolish()
            }
        }
    }

    private static func polishNotice(for skip: DictationPolishSkip) -> String? {
        switch skip {
        case .tooShort:
            nil
        case .tooLong:
            L10n.text("Pasted without polish: the dictation is too long to polish.")
        case .unavailable(let reason):
            L10n.format("Pasted without polish: %@", reason)
        case .timedOut:
            L10n.text("Pasted without polish: the rewrite took too long.")
        case .failed:
            L10n.text("Pasted without polish: the model could not rewrite it.")
        case .changedMeaning:
            L10n.text("Pasted without polish: the rewrite changed a fact, name or number.")
        }
    }

    func armCancelKey(_ dependencies: DictationSessionDependencies, sessionID: UUID) {
        releaseCancelKey()
        cancelKey = dependencies.registerCancelKey { [weak self] in
            // Leave the Carbon callback before its own registration is removed.
            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == sessionID,
                      self.phase == .preparing || self.phase == .listening else { return }
                self.cancel()
            }
        }
    }

    func releaseCancelKey() {
        cancelKey?.unregister()
        cancelKey = nil
    }

    func releaseSpeechGate() {
        analysis.cancel()
        analysis = DictationSessionAnalysis()
    }

    /// A tap-started dictation ends itself after a pause; a held trigger never does.
    func stopAfterPause(sessionID: UUID) {
        guard activeSessionID == sessionID, phase == .listening, !isLoadingModel, stopTask == nil, !mouseOwnsSession,
              !modifierTrigger.ownsSession, pressedSessionID != sessionID else { return }
        finishAndInsert()
    }

    /// No paste: the text stays reachable for Copy in case speech was missed.
    func presentNoSpeech(_ text: String, id: UUID) {
        measurement?.finish(.noSpeech)
        completeSession(id: id)
        if closesInternalDelivery() { return }
        deliveryID = id
        destination = nil
        cancelFeedbackDismissal()
        copyStatus = .idle
        recoveryText = text
        holdRecoveryForUpdate()
        sessionLastText.remember(text)
        phase = .noSpeech
        showPanel()
    }
}
