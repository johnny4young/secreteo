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
        case .toggle: toggle(using: dependencies)
        case .pasteLast: pasteLastDictation(using: dependencies)
        }
        return outcome
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
        case (_, .delivering), (_, .recovery):
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
    /// The app is the only listener, so a request posted before this runs is answered as not ready.
    func installDictationIntents() -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: SecreteoAppIntentBridge.dictationRequested, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let request = SecreteoAppIntentBridge.consumeDictationRequest() else { return }
                SecreteoAppIntentBridge.answerDictationRequest(self.performDictationIntent(request))
            }
        }
    }

    func performDictationIntent(
        _ request: SecreteoAppIntentBridge.DictationRequest
    ) -> SecreteoAppIntentBridge.DictationRequestOutcome {
        controller.performIntent(request, using: makeDictationSessionDependencies())
    }
}
