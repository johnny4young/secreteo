import DictationKit
import Foundation

/// A verified "change X to Y" or post-paste edit the dictionary does not know yet, offered once in the strip.
struct DictationLearnableCorrection {
    let rule: DictationReplacement
    let defaults: UserDefaults
    let temporary: Bool
    let wait: @MainActor (Duration) async throws -> Void

    @MainActor
    init?(
        _ command: DictationCorrectionCommand, edit: DictationCorrectionCommand.Edit, in text: String,
        dependencies: DictationSessionDependencies
    ) {
        guard case .replace = command else { return nil }
        let heard = (text as NSString).substring(with: edit.range).trimmingCharacters(in: .whitespacesAndNewlines)
        let rules = Self.rules(in: dependencies.defaults)
        guard DictationTextRules.learning(heard, as: edit.replacement, into: rules) != nil else { return nil }
        rule = DictationReplacement(trigger: heard, replacement: edit.replacement)
        defaults = dependencies.defaults
        temporary = dependencies.storesPreferencesTemporarily
        wait = dependencies.waitForFeedbackDismissal
    }

    @MainActor
    init?(rule: DictationReplacement, dependencies: DictationSessionDependencies) {
        let rules = Self.rules(in: dependencies.defaults)
        guard DictationTextRules.learning(rule.trigger, as: rule.replacement, into: rules) != nil else { return nil }
        self.rule = rule
        defaults = dependencies.defaults
        temporary = dependencies.storesPreferencesTemporarily
        wait = dependencies.waitForFeedbackDismissal
    }

    @MainActor
    static func rules(in defaults: UserDefaults) -> [DictationReplacement] {
        DictationTextRules.decode(replacements: defaults.string(forKey: DictationController.replacementsKey) ?? "")
    }
}

// Spoken corrections and opt-in post-paste edit learning.
extension DictationController {
    /// True when this dictation was a correction command, applied or refused; it is never pasted.
    func correctsLastInsertion(
        original: String, sessionID: UUID, dependencies: DictationSessionDependencies
    ) async -> Bool {
        guard !dependencies.deliversInternally, dependencies.admissionKind == .global,
              DictationCorrections.isEnabled(in: dependencies.defaults),
              let command = DictationCorrectionCommand.parse(
                  DictationTextRules.apply(original, replacements: [], removeFillers: true)),
              let pasted = lastText.current else { return false }
        // Sleep, lock or 15 minutes end Paste last, and with it the right to edit that text.
        let reference = lastInsertion?.text ?? pasted
        guard let edit = command.edit(in: reference) else { return false }
        guard let last = lastInsertion, last.text == reference, last.isFresh(at: dependencies.now()), last.isIntact()
        else {
            measurement?.finish(.deliveryRejected)
            failSession(id: sessionID, message: L10n.text(
                "Secreteo can correct only its last insertion while it is unchanged in a field it can read."))
            return true
        }
        dispatched = (sessionID, false)
        guard let updated = await last.edit(edit.range, edit.replacement) else {
            guard activeSessionID == sessionID else { return true }
            measurement?.finish(.deliveryRejected)
            failSession(id: sessionID, message: L10n.text("This field did not accept the correction. Nothing changed."))
            return true
        }
        guard activeSessionID == sessionID else { return true }
        lastInsertion = updated
        if renewsPasteLast(sessionID) { lastText.remember(updated.text, app: destination?.name) }
        correctionSummary = Self.correctionSummary(for: command, edit: edit, in: reference)
        learnableCorrection = DictationLearnableCorrection(
            command, edit: edit, in: reference, dependencies: dependencies)
        measurement?.finishDelivery(.dispatched)
        completeSession(id: sessionID)
        destination = nil
        phase = .verified(0)
        showPanel()
        // Long enough to choose "Always write"; nothing is learned unless it is pressed.
        scheduleFeedbackDismiss(
            after: learnableCorrection == nil ? Self.resultFeedbackDuration : .seconds(6),
            wait: dependencies.waitForFeedbackDismissal)
        return true
    }

    private static func correctionSummary(
        for command: DictationCorrectionCommand, edit: DictationCorrectionCommand.Edit, in text: String
    ) -> String {
        let removed = (text as NSString).substring(with: edit.range).trimmingCharacters(in: .whitespacesAndNewlines)
        switch command {
        case .replace: return L10n.format("Changed “%@” to “%@”.", removed, edit.replacement)
        case .delete: return L10n.format("Deleted “%@”.", removed)
        case .deleteLast: return L10n.text("Deleted the last dictation.")
        }
    }

    func scheduleEditLearning(dependencies: DictationSessionDependencies, sourceDeliveryID: UUID) {
        cancelEditLearning()
        guard !dependencies.deliversInternally, dependencies.admissionKind == .global,
              DictationEditLearning.isEnabled(in: dependencies.defaults),
              let insertion = lastInsertion else { return }
        let observedAt = insertion.insertedAt
        let readEdit = { @MainActor [weak self] () -> String? in
            guard let self, !Task.isCancelled, activeSessionID == nil, !hasPendingOutput,
                  !isRetryingDelivery, retryDeliveryTask == nil,
                  DictationEditLearning.isEnabled(in: dependencies.defaults),
                  dependencies.admission.isEligible(),
                  lastInsertion?.insertedAt == observedAt else { return nil }
            return insertion.readEditedSpan()
        }
        editLearningTask = Task { [weak self] in
            do { try await dependencies.waitForEditLearning(DictationEditLearning.observationDelay) } catch { return }
            guard let first = readEdit() else { return }
            do { try await dependencies.waitForEditLearning(DictationEditLearning.settleDelay) } catch { return }
            guard let self, let edited = readEdit(), edited == first else { return }
            let rules = DictationLearnableCorrection.rules(in: dependencies.defaults)
            guard let candidate = DictationEditLearner.extract(
                pasted: insertion.text, edited: edited, existing: rules),
                  let offer = DictationLearnableCorrection(rule: candidate, dependencies: dependencies)
            else { return }
            deliveryID = sourceDeliveryID
            panelAnchor = dependencies.locatePanelAnchor()
            learnableCorrection = offer
            correctionSummary = L10n.format("Changed “%@” to “%@”.", candidate.trigger, candidate.replacement)
            phase = .verified(0)
            showPanel()
            scheduleFeedbackDismiss(after: .seconds(6), wait: dependencies.waitForFeedbackDismissal)
        }
    }

    func cancelEditLearning() {
        editLearningTask?.cancel()
        editLearningTask = nil
    }

    /// Adds the offered correction to the text replacements; the next dictation applies it.
    func learnCorrection() {
        cancelEditLearning()
        guard let learnable = learnableCorrection else { return }
        learnableCorrection = nil
        let rule = learnable.rule
        guard let learned = DictationTextRules.learning(
            rule.trigger, as: rule.replacement, into: DictationLearnableCorrection.rules(in: learnable.defaults))
        else { return }
        DictationTextPreferences.store(
            DictationTextRules.encode(learned), forKey: Self.replacementsKey,
            in: learnable.defaults, temporary: learnable.temporary)
        correctionSummary = L10n.format("From now on, “%@” is written “%@”.", rule.trigger, rule.replacement)
        scheduleFeedbackDismiss(after: .milliseconds(1600), wait: learnable.wait)
    }
}
