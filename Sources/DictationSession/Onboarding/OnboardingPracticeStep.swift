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
            .shadow(color: SecreteoDesign.amber.opacity(sessionIsHere ? 0.75 : 0), radius: 13)
            .accessibilityElement(children: .ignore)
            // A text's own label is read as its value, so the key is given as the value of a named element.
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(L10n.text("Dictation Key"))
            .accessibilityValue(label)
            .accessibilityIdentifier("onboarding-practice-key")
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        return VStack(spacing: 0) {
            words
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: Self.wordsHeight, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.top, Self.wordsTop)
            // The capsule opens under the words and grows downward, so it never covers them.
            OnboardingPanelSlot(
                practice: practice,
                moved: { controller.panelSlotMoved(to: $0) }, closed: { controller.panelSlotClosed() })
                .frame(height: DictationPanelLayout.capsuleHeight)
                .padding(.top, Self.slotGap)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .frame(height: Self.fieldHeight)
        .background(SecreteoDesign.card, in: shape)
        .overlay { shape.strokeBorder(SecreteoDesign.accent, lineWidth: 1.5) }
        .padding(5)
        .background(SecreteoDesign.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 23))
        .padding(-5)
        .accessibilityElement(children: .ignore)
        // Without a role that has a value, accessibility clients read none.
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(L10n.text("Dictated Text"))
        .accessibilityValue(practice.text)
        .accessibilityIdentifier(identifiers.field)
    }

    /// Only a dictation into this field: one started in another app never shows here.
    private var sessionIsHere: Bool { controller.isActive && controller.sessionIsPractice }

    private var words: Text {
        let live = Self.words(
            delivered: practice.text, confirmed: controller.confirmedText, partial: controller.partialText,
            isLive: sessionIsHere)
        let settled = Text(live.settled)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(SecreteoDesign.text)
        let provisional = Text(live.provisional)
            .font(.secreteoSerif(24, italic: true))
            .foregroundStyle(SecreteoDesign.accent)
        let caret = Text(verbatim: sessionIsHere ? " |" : "")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(SecreteoDesign.amber)
        return Text("\(settled)\(provisional)\(caret)")
    }

    nonisolated static let fieldHeight: CGFloat = 190
    nonisolated static let wordsTop: CGFloat = 18
    /// Three lines of the field's text.
    nonisolated static let wordsHeight: CGFloat = 78
    nonisolated static let slotGap: CGFloat = 8
    /// What the field keeps under the words, for the capsule and a notice hanging from it.
    nonisolated static var roomUnderWords: CGFloat { fieldHeight - wordsTop - wordsHeight - slotGap }

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

/// Tells the practice field where on screen the capsule belongs while this window is key,
/// and the controller when that place moves or goes away.
private struct OnboardingPanelSlot: NSViewRepresentable {
    let practice: DictationPracticeField
    let moved: (NSRect) -> Void
    let closed: () -> Void

    func makeNSView(context: Context) -> PanelSlotView {
        let view = PanelSlotView()
        view.moved = moved
        view.closed = closed
        practice.panelSlot = { [weak view] in
            guard let view, view.window?.isKeyWindow == true else { return nil }
            return view.screenRect
        }
        return view
    }

    func updateNSView(_ view: PanelSlotView, context: Context) {}

    func makeCoordinator() -> DictationPracticeField { practice }

    static func dismantleNSView(_ view: PanelSlotView, coordinator: DictationPracticeField) {
        coordinator.panelSlot = nil
        view.closed?()
    }
}

/// Closing the window does not take the view down, so the view watches its window itself.
private final class PanelSlotView: NSView {
    var moved: ((NSRect) -> Void)?
    var closed: (() -> Void)?

    var screenRect: NSRect? {
        window.map { $0.convertToScreen(convert(bounds, to: nil)) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        center.removeObserver(self)
        guard let newWindow else { return }
        center.addObserver(
            self, selector: #selector(windowMoved), name: NSWindow.didMoveNotification, object: newWindow)
        center.addObserver(
            self, selector: #selector(windowClosed), name: NSWindow.willCloseNotification, object: newWindow)
    }

    @objc private func windowMoved() {
        if let screenRect { moved?(screenRect) }
    }

    @objc private func windowClosed() {
        closed?()
    }
}
