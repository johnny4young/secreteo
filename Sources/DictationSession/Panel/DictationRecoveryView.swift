import SwiftUI
import DictationKit

/// Presentation only: the controller retains the complete output and owns
/// every effect. The visible excerpt is never the source of a copied paste.
struct DictationRecoveryView: View {
    let controller: DictationController
    let failure: DictationDeliveryOutcome.Refusal

    var body: some View {
        DictationOutcomeCard(
            face: .notSent, title: L10n.text("Text wasn't sent"), reason: message, words: controller.recoveryText,
            titleIdentifier: "dictation-recovery-title", reasonIdentifier: "dictation-recovery-reason",
            textIdentifier: "dictation-recovery-text"
        ) {
            if controller.canRetryDelivery {
                Button("Reinsert", action: controller.retryUndeliveredText)
                    .buttonStyle(DictationCardButtonStyle(kind: .primary))
                    .modifier(DictationCardFocusRing())
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("dictation-recovery-reinsert")
                    .disabled(controller.isRetryingDelivery)
            }
            Button("Copy", action: controller.copyPendingText)
                .buttonStyle(DictationCardButtonStyle(kind: controller.canRetryDelivery ? .quiet : .primary))
                .modifier(DictationCardFocusRing())
                .accessibilityIdentifier("dictation-recovery-copy")
                .disabled(controller.isRetryingDelivery)
            // This abandons the pending operation; it does not delete an already saved history entry.
            Button("Discard", role: .cancel, action: controller.cancel)
                .buttonStyle(DictationCardButtonStyle(kind: .bare))
                .modifier(DictationCardFocusRing())
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("dictation-recovery-discard")
            DictationCopyStatusLabel(
                status: controller.copyStatus, privacy: controller.deliveryPrivacyLine,
                inHistory: controller.historyKeptDelivery)
                .accessibilityIdentifier("dictation-recovery-copy-status")
        }
    }

    private var message: String {
        if !controller.canRetryDelivery, let copyOnlyMessage { return copyOnlyMessage }
        switch failure {
        case .targetChanged:
            if let name = controller.targetApp {
                return L10n.format("Return to %@ and the original field to reinsert, or copy your text.", name)
            }
            return L10n.text("The destination changed. Copy your text to keep it.")
        case .secureField:
            return L10n.text("Dictation never types into password fields.")
        case .modifiersStillPressed:
            return L10n.text("Release Command, Option, Control, and Shift, then try again.")
        case .focusUnavailable:
            return L10n.text("The original field can't be verified. Your text is still available to copy.")
        case .ownershipChanged:
            return L10n.text("Another app took over dictation, so nothing was inserted. Copy your text to keep it.")
        case .clipboardUnavailable:
            return L10n.text(
                // One-line UI copy.
                // swiftlint:disable:next line_length
                "Your clipboard couldn't be backed up, so nothing was inserted. Reinsert after clearing it, or copy your text.")
        case .eventUnavailable, .cancelled, .emptyText:
            return L10n.text("Delivery didn't complete. Reinsert into the original field, or copy your text.")
        }
    }

    /// Without Reinsert, the messages that would ask the user to retry point to Copy instead.
    private var copyOnlyMessage: String? {
        switch failure {
        case .targetChanged:
            L10n.text("The destination changed. Copy your text to keep it.")
        case .clipboardUnavailable:
            L10n.text("Your clipboard couldn't be backed up, so nothing was inserted. Copy your text to keep it.")
        case .modifiersStillPressed, .eventUnavailable, .cancelled, .emptyText:
            L10n.text("Delivery didn't complete. Copy your text to keep it.")
        case .secureField, .focusUnavailable, .ownershipChanged:
            nil
        }
    }
}

/// A capture failure or sleep that already heard words opens a copyable card instead of hiding them.
struct DictationFailureRecoveryView: View {
    let controller: DictationController
    let message: String

    var body: some View {
        DictationOutcomeCard(
            face: .notSent, title: L10n.text("Text wasn't sent"), reason: message, words: controller.recoveryText,
            titleIdentifier: "dictation-recovery-title", reasonIdentifier: "dictation-recovery-reason",
            textIdentifier: "dictation-recovery-text"
        ) {
            Button("Copy", action: controller.copyPendingText)
                .buttonStyle(DictationCardButtonStyle(kind: .primary))
                .modifier(DictationCardFocusRing())
                .accessibilityIdentifier("dictation-recovery-copy")
                .disabled(controller.isRetryingDelivery)
            Button("Discard", role: .cancel, action: controller.cancel)
                .buttonStyle(DictationCardButtonStyle(kind: .bare))
                .modifier(DictationCardFocusRing())
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("dictation-recovery-discard")
            DictationCopyStatusLabel(
                status: controller.copyStatus, privacy: controller.deliveryPrivacyLine,
                inHistory: controller.historyKeptDelivery)
                .accessibilityIdentifier("dictation-recovery-copy-status")
        }
    }
}
