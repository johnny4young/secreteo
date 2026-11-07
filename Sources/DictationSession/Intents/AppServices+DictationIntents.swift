import Foundation

extension DictationController {
    /// Answers an intent through the same dependencies and admission as the shortcut,
    /// so it never starts while another app owns dictation.
    func performIntent(
        _ request: SecreteoAppIntentBridge.DictationRequest, using dependencies: DictationSessionDependencies
    ) -> SecreteoAppIntentBridge.DictationRequestOutcome {
        let store = dependencies.admissionKind == .practice ? practiceLastText : lastText
        let outcome = Self.dictationIntentOutcome(
            for: request,
            refusal: isActive ? nil : dependencies.admission.refusalNow(for: dependencies.admissionKind),
            phase: phase,
            hasPastableText: store.current != nil)
        guard outcome == .accepted else { return outcome }
        switch request {
        case .toggle:
            toggle(using: dependencies)
            return outcome
        case .pasteLast:
            if pasteLastDictation(using: dependencies) { return outcome }
            return dependencies.canInsert() ? .busy : .needsAccessibility
        }
    }

    static func dictationIntentOutcome(
        for request: SecreteoAppIntentBridge.DictationRequest,
        refusal: DictationAdmissionRefusal?,
        phase: DictationController.Phase,
        hasPastableText: Bool
    ) -> SecreteoAppIntentBridge.DictationRequestOutcome {
        switch refusal {
        case .dictationOff: return .dictationOff
        case .notOwner: return .notOwner
        case .unavailable: return .unavailable
        case .busy, .transferring: return .busy
        case nil: break
        }
        switch (request, phase) {
        case (_, .delivering), (.toggle, .recovery):
            return .busy
        case (.toggle, _):
            return .accepted
        case (.pasteLast, .preparing), (.pasteLast, .listening):
            return .busy
        case (.pasteLast, _):
            return hasPastableText ? .accepted : .nothingToPaste
        }
    }
}

extension DictationFeature {
    func installDictationIntents() {
        SecreteoAppIntentBridge.dictationHandler = { [weak self] request in
            self?.performDictationIntent(request) ?? .unavailable
        }
    }

    func performDictationIntent(
        _ request: SecreteoAppIntentBridge.DictationRequest
    ) -> SecreteoAppIntentBridge.DictationRequestOutcome {
        controller.performIntent(request, using: makeDictationSessionDependencies())
    }

    /// A build or launch with no dictation still lists the actions, so they say why they do nothing.
    public static func answerIntentsWithoutDictation() {
        SecreteoAppIntentBridge.dictationHandler = { _ in .unavailable }
    }
}
