import AppKit
import DictationKit
import Foundation

/// What delivery pastes, and the version Paste last can offer instead.
struct DictationDeliveryText: Equatable {
    var text: String
    /// The clean text before Polish or translation, when one of them changed it.
    var alternate: String?
    /// True when the alternate is the untranslated original, not just the unpolished text.
    var alternateIsOriginal = false
}

extension DictationController {
    var hasPendingOutput: Bool {
        switch phase {
        case .recovery, .noSpeech: true
        case .failed: !recoveryText.isEmpty
        default: false
        }
    }

    func copyPendingText() {
        guard hasPendingOutput, !isRetryingDelivery, let dependencies else { return }
        copyStatus = dependencies.copyText(recoveryText) ? .copied : .failed
        if copyStatus == .copied { endRecoveryHold() }
    }

    /// Closes a delivery notice now, keeping the text for Paste last.
    func dismissFeedback() {
        switch phase {
        case .verified, .dispatched: closeFeedback()
        case .failed where !recoveryText.isEmpty: closeFeedback()
        default: return
        }
    }

    var canRetryDelivery: Bool { destination?.canRetry == true }

    func retryUndeliveredText() {
        guard case .recovery = phase, !isRetryingDelivery,
              let id = deliveryID, let destination, destination.canRetry,
              case .success(let lease) = dependencies?.admission.acquire(.global) else { return }
        // The lease holds the relaunch from here; another refusal holds it again.
        endRecoveryHold()
        replay(recoveryText, into: destination, id: id, lease: lease)
    }

    /// Pastes the remembered text into whatever is focused now, through the
    /// same delivery and recovery path as a fresh dictation. Undelivered words
    /// in recovery are that text, so they paste where the user is now.
    /// False when nothing was sent.
    @discardableResult
    func pasteLastDictation(using dependencies: DictationSessionDependencies, alternate: Bool = false) -> Bool {
        guard !isActive, retryDeliveryTask == nil,
              case .success(let lease) = dependencies.admission.acquire(dependencies.admissionKind)
        else { return false }
        let store = dependencies.admissionKind == .practice ? practiceLastText : lastText
        guard let text = alternate ? store.takeCurrentAlternate() : store.takeCurrent(), dependencies.canInsert() else {
            lease.release()
            return false
        }
        cancelEditLearning()
        cancelFeedbackDismissal()
        self.dependencies = dependencies
        let id = UUID()
        deliveryID = id
        replay(text, into: dependencies.captureDestination(), id: id, lease: lease)
        return true
    }

    private func replay(
        _ text: String, into destination: CapturedDictationDestination, id: UUID, lease: DictationLease
    ) {
        self.destination = destination
        isRetryingDelivery = true
        retryDeliveryTask = Task { [weak self] in
            let result = lease.revalidate() ? await destination.insert(text) : .refused(.ownershipChanged)
            // A closed notice clears the ID, and the replay must still let go of its slot.
            if let self, !Task.isCancelled {
                self.isRetryingDelivery = false
                if self.deliveryID == id { self.presentDelivery(result, text: text, id: id) }
                self.retryDeliveryTask = nil
            }
            await lease.releaseAfterDelivery()
        }
    }

    func presentDelivery(
        _ result: DictationDeliveryOutcome, text: String, alternate: DictationDeliveryText? = nil,
        id: UUID, canLearnEdits: Bool = false
    ) {
        // Words kept from a handoff stay on screen even for a session that delivers internally.
        guard deliveryID == id, let dependencies,
              result == .refused(.ownershipChanged) || !closesInternalDelivery() else { return }
        lastInsertion = result == .verified ? destination?.lastInsertion() : nil
        cancelFeedbackDismissal()
        copyStatus = .idle
        if renewsPasteLast(id) {
            sessionLastText.remember(
                text, app: destination?.name, alternate: alternate?.alternate,
                isOriginal: alternate?.alternateIsOriginal == true)
        }
        recordHistory(result, id: id)
        if case .refused(let failure) = result {
            recoveryText = text
            holdRecoveryForUpdate()
            phase = .recovery(failure)
            showPanel()
            return
        }
        destination = nil
        endRecoveryHold()
        let words = text.split(whereSeparator: \.isWhitespace).count
        phase = result == .verified ? .verified(words) : .dispatched(words)
        recoveryText = ""
        // The words in the field are the result. Many apps never let a paste be verified,
        // so an unverified one stays quiet too; Paste Last and history still hold the words.
        let showsNotice = polishNotice != nil
        if showsNotice {
            showPanel()
        } else {
            panel.close()
            if presentsPanel { DictationCompactIndicator.announce(phase) }
        }
        scheduleFeedbackDismiss(
            after: showsNotice ? Self.noticeFeedbackDuration : Self.resultFeedbackDuration,
            wait: dependencies.waitForFeedbackDismissal)
        if result == .verified, canLearnEdits {
            scheduleEditLearning(dependencies: dependencies, sourceDeliveryID: id)
        }
    }

    /// An internal destination already holds the text; the strip just closes.
    func closesInternalDelivery() -> Bool {
        guard dependencies?.deliversInternally == true else { return false }
        closeFeedback()
        return true
    }

    func cancelFeedbackDismissal() {
        feedback.cancel()
    }

    func scheduleFeedbackDismiss(
        after delay: Duration,
        wait: @escaping @MainActor (Duration) async throws -> Void
    ) {
        feedback.schedule(after: delay, wait: wait) { [weak self] in self?.closeFeedback() }
    }

    private func closeFeedback() {
        releaseCancelKey()
        cancelFeedbackDismissal()
        polishNotice = nil
        correctionSummary = nil
        learnableCorrection = nil
        deliveryID = nil
        destination = nil
        dependencies = nil
        recoveryText = ""
        endRecoveryHold()
        copyStatus = .idle
        phase = .idle
        panel.close()
    }

    func handleMouse(_ event: MousePTTGesture.Event, start beginSession: () -> Void) {
        switch MousePTTGesture.action(
            for: event,
            isListening: isActive,
            mouseOwnsSession: mouseOwnsSession) {
        case .start:
            mouseOwnsSession = true
            beginSession()
            // A refused start (missing Accessibility trust) must not leave
            // the button claiming a session that never began.
            if !isActive { mouseOwnsSession = false }
        case .finish:
            mouseOwnsSession = false
            // A press that ends another trigger's session proved no hold.
            finishAndInsert(isHeld: event == .release)
        case .ignore:
            break
        }
    }
}

// The session's side of the ownership protocol and panel presentation.
extension DictationController {
    var sessionIsPractice: Bool { dependencies?.admissionKind == .practice }
    var sessionLastText: DictationLastText { sessionIsPractice ? practiceLastText : lastText }
    var sessionHandoffGrace: Duration? { dependencies?.handoffGrace }
    /// Stays listening until transcription ends, so the phase alone cannot say the microphone is open.
    var microphoneIsOpen: Bool {
        phase == .listening && stopTask == nil && stopIssuedSessionID != activeSessionID
    }

    func discardPreviousDelivery() {
        cancelEditLearning()
        historyFailure.clear()
        retryDeliveryTask?.cancel()
        retryDeliveryTask = nil
        isRetryingDelivery = false
        deliveryID = nil
        destination = nil
        recoveryText = ""
        endRecoveryHold()
        copyStatus = .idle
    }

    func holdRecoveryForUpdate() {
        guard releaseRecoveryHold == nil, !recoveryText.isEmpty else { return }
        releaseRecoveryHold = dependencies?.pendingWrites?.begin()
    }

    func endRecoveryHold() {
        let release = releaseRecoveryHold
        releaseRecoveryHold = nil
        release?()
    }

    func refuseDelivery(_ text: String, sessionID: UUID) {
        let refused = DictationDeliveryOutcome.refused(.ownershipChanged)
        measurement?.finishDelivery(refused)
        completeSession(id: sessionID)
        deliveryID = sessionID
        presentDelivery(refused, text: text, id: sessionID)
    }

    func showPanel() {
        if presentsPanel { panel.show(controller: self) }
    }

    /// Words that went out leave no panel, so a failed save shows on the menu bar for a moment.
    func showHistoryFailure() {
        historyFailure.show(for: Self.noticeFeedbackDuration, wait: sessionFeedbackWait)
    }
}
