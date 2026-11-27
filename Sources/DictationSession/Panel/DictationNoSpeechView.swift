import SwiftUI

/// The voice detector heard no speech, so nothing was pasted. The text stays
/// reachable for an explicit Copy in case real speech was missed.
struct DictationNoSpeechView: View {
    let controller: DictationController

    var body: some View {
        DictationOutcomeCard(
            face: .noSpeech, title: L10n.text("No speech detected"), reason: L10n.text("Nothing was inserted."),
            words: controller.recoveryText,
            titleIdentifier: "dictation-panel-delivery-status", reasonIdentifier: "dictation-panel-delivery-detail",
            textIdentifier: "dictation-no-speech-text"
        ) {
            Button("Copy", action: controller.copyPendingText)
                .buttonStyle(DictationCardButtonStyle(kind: .primary))
                .modifier(DictationCardFocusRing())
                .accessibilityIdentifier("dictation-no-speech-copy")
            Button("Discard", role: .cancel, action: controller.cancel)
                .buttonStyle(DictationCardButtonStyle(kind: .bare))
                .modifier(DictationCardFocusRing())
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("dictation-no-speech-discard")
            DictationCopyStatusLabel(
                status: controller.copyStatus, privacy: controller.deliveryPrivacyLine,
                inHistory: controller.historyKeptDelivery)
                .accessibilityIdentifier("dictation-no-speech-copy-status")
        }
    }
}
