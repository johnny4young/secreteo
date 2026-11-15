import AppKit
import SwiftUI

/// The first dictation: the key that starts it, the field the words land in, and room in the
/// field for the real capsule.
struct OnboardingPracticeStep: View {
    let dictation: DictationFeature

    private let identifiers = DictationPracticeView.Identifiers.onboarding
    private var practice: DictationPracticeField { dictation.practice }
    private var controller: DictationController { dictation.controller }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTitle(title: L10n.text("Try It Here"), identifier: "onboarding-practice")
            controls.padding(.top, 12)
            field.padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            keyCap
            Button(controller.isActive ? L10n.text("Finish") : L10n.text("Dictate Here")) {
                dictation.toggleDictation()
            }
            .buttonStyle(OnboardingButtonStyle())
            .disabled(controller.phase == .delivering)
            .accessibilityIdentifier(identifiers.start)
            if !practice.text.isEmpty {
                Button("Clear") { practice.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SecreteoDesign.tertiaryText)
                    .accessibilityIdentifier(identifiers.clear)
            }
        }
    }

    /// The key that dictates everywhere else, lit while the microphone is open.
    private var keyCap: some View {
        let modifier = ModifierKeySetting(
            rawValue: dictation.preference(ModifierKeySetting.defaultsKey, default: "").wrappedValue) ?? .off
        let label = Self.keyLabel(modifier: modifier, shortcut: controller.shortcut.setting.label)
        let shape = RoundedRectangle(cornerRadius: 10)
        return Text(verbatim: label)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SecreteoPalette.capsuleInk.color)
            .padding(.horizontal, 12)
            .frame(minWidth: 46, minHeight: 42)
            .background(SecreteoDesign.amber, in: shape)
            .overlay { shape.strokeBorder(SecreteoPalette.capsuleInk.color.opacity(0.25)) }
            .shadow(color: SecreteoDesign.amber.opacity(controller.isActive ? 0.75 : 0), radius: 13)
            .accessibilityLabel(L10n.format("Dictation key: %@", label))
            .accessibilityIdentifier("onboarding-practice-key")
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        return words
            .textSelection(.enabled)
            .lineLimit(3)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            // The capsule opens over the bottom of the field, never over the words.
            .padding(.bottom, Self.slotInset * 2 + DictationPanelLayout.capsuleHeight)
            .frame(height: 190)
            .background(SecreteoDesign.card, in: shape)
            .overlay { shape.strokeBorder(SecreteoDesign.accent, lineWidth: 1.5) }
            .padding(5)
            .background(SecreteoDesign.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 23))
            .padding(-5)
            .overlay(alignment: .bottom) {
                OnboardingPanelSlot(practice: practice)
                    .frame(height: DictationPanelLayout.capsuleHeight)
                    .padding(.bottom, Self.slotInset)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            // Without a role that has a value, accessibility clients read none.
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(L10n.text("Dictated Text"))
            .accessibilityValue(practice.text)
            .accessibilityIdentifier(identifiers.field)
    }

    private var words: Text {
        let live = Self.words(
            delivered: practice.text, confirmed: controller.confirmedText, partial: controller.partialText,
            isLive: controller.isActive && practice.isArmed)
        let settled = Text(live.settled)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(SecreteoDesign.text)
        let provisional = Text(live.provisional)
            .font(.secreteoSerif(24, italic: true))
            .foregroundStyle(SecreteoDesign.accent)
        let caret = Text(verbatim: controller.isActive ? " |" : "")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(SecreteoDesign.amber)
        return Text("\(settled)\(provisional)\(caret)")
    }

    static let slotInset: CGFloat = 14

    nonisolated static func keyLabel(modifier: ModifierKeySetting, shortcut: String) -> String {
        switch modifier {
        case .function: "fn"
        case .rightOption: "⌥"
        case .rightCommand: "⌘"
        case .off: shortcut
        }
    }

    /// What is delivered and what the engine has confirmed stand upright; its tail is still provisional.
    nonisolated static func words(
        delivered: String, confirmed: String, partial: String, isLive: Bool
    ) -> (settled: String, provisional: String) {
        guard isLive else { return (delivered, "") }
        let settled = [delivered, confirmed].filter { !$0.isEmpty }.joined(separator: " ")
        guard !partial.isEmpty else { return (settled, "") }
        return (settled, settled.isEmpty ? partial : " " + partial)
    }
}

/// Tells the practice field where on screen the capsule belongs while this window is key.
private struct OnboardingPanelSlot: NSViewRepresentable {
    let practice: DictationPracticeField

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        practice.panelSlot = { [weak view] in
            guard let view, let window = view.window, window.isKeyWindow else { return nil }
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    func makeCoordinator() -> DictationPracticeField { practice }

    static func dismantleNSView(_ view: NSView, coordinator: DictationPracticeField) {
        coordinator.panelSlot = nil
    }
}
