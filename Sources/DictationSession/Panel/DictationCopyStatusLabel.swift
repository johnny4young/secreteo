import SwiftUI

/// The card's one quiet line: what Secreteo kept, until a Copy has something to say.
struct DictationCopyStatusLabel: View {
    let status: DictationController.CopyStatus
    let kept: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(SecreteoPalette.capsuleTertiaryText.color)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var message: String {
        switch status {
        case .idle: kept
        case .copied: L10n.text("Copied. You can paste the text yourself.")
        case .failed: L10n.text("Couldn't copy. Your text is still here.")
        }
    }
}
