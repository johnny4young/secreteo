import SwiftUI

/// Dictation with the real microphone and model, delivered to an in-app field
/// instead of another app, so a user can try it before granting Accessibility.
struct DictationPracticeView: View {
    let dictation: DictationFeature
    var identifierPrefix = "settings-dictation"

    private var practice: DictationPracticeField { dictation.practice }
    private var controller: DictationController { dictation.controller }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            field
            controls
        }
    }

    private var field: some View {
        Text(practice.text)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
            .accessibilityElement(children: .ignore)
            // Without a role that has a value, accessibility clients read none.
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(L10n.text("Dictated Text"))
            .accessibilityValue(practice.text)
            .accessibilityIdentifier(identifier("practice-field"))
    }

    private var controls: some View {
        HStack {
            Button {
                dictation.toggleDictation()
            } label: {
                Label(
                    controller.isActive ? L10n.text("Finish") : L10n.text("Dictate Here"),
                    systemImage: controller.isActive ? "stop.fill" : "mic.fill")
            }
            .disabled(controller.phase == .delivering)
            .accessibilityIdentifier(identifier("practice-start"))
            if !practice.text.isEmpty {
                Button("Clear") { practice.clear() }
                    .accessibilityIdentifier(identifier("practice-clear"))
            }
        }
    }

    private func identifier(_ suffix: String) -> String {
        "\(identifierPrefix)-\(suffix)"
    }
}
