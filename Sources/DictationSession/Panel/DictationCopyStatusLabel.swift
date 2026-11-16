import SwiftUI

/// The card's one quiet line: where the words are kept, after what the last Copy did.
struct DictationCopyStatusLabel: View {
    let status: DictationController.CopyStatus
    let privacy: String
    let inHistory: Bool

    var body: some View {
        Text(Self.message(status: status, privacy: privacy, inHistory: inHistory))
            .font(.system(size: 11))
            .foregroundStyle(SecreteoPalette.capsuleTertiaryText.color)
            .lineLimit(3)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Words the history did not keep live only in memory, which is worth saying until they are copied.
    nonisolated static func message(status: DictationController.CopyStatus, privacy: String, inHistory: Bool) -> String {
        let kept = inHistory ? privacy : L10n.text("Kept only in memory. Copy it before quitting Secreteo.")
        return switch status {
        case .idle: kept
        case .copied: L10n.text("Copied. You can paste the text yourself.") + " " + privacy
        case .failed: L10n.text("Couldn't copy. Your text is still here.") + " " + kept
        }
    }
}
