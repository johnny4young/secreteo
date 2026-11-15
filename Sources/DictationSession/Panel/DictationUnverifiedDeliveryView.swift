import SwiftUI

/// Copy is an explicit clipboard operation, never a second paste attempt.
struct DictationUnverifiedDeliveryView: View {
    let controller: DictationController

    var body: some View {
        DictationOutcomeCard(
            face: .sent, title: L10n.text("Sent, not verified"),
            reason: L10n.text("Check the destination before pasting again."),
            notice: controller.polishNotice, words: controller.recoveryText,
            titleIdentifier: "dictation-panel-delivery-status", reasonIdentifier: "dictation-panel-delivery-detail",
            textIdentifier: "dictation-unverified-text", close: controller.dismissFeedback
        ) {
            // The words most likely arrived, so no button here asks to be pressed.
            Button("Copy", action: controller.copyPendingText)
                .buttonStyle(DictationCardButtonStyle())
                .accessibilityIdentifier("dictation-unverified-copy")
            Button("Discard", role: .cancel, action: controller.cancel)
                .buttonStyle(DictationCardButtonStyle(kind: .bare))
                .accessibilityIdentifier("dictation-unverified-discard")
            DictationCopyStatusLabel(status: controller.copyStatus, kept: controller.deliveryPrivacyLine)
                .accessibilityIdentifier("dictation-unverified-copy-status")
        }
    }
}
