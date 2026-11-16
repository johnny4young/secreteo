import AppKit
import SwiftUI
import DictationKit

/// The floating dictation strip: same non-activating panel recipe as the
/// recording HUD — always on top, never steals focus, so the keystrokes
/// keep landing in the app the user is dictating INTO.
@MainActor
final class DictationPanelController {
    private var panel: NSPanel?
    private var pinnedEdge = DictationPanelAnchor.PinnedEdge.bottom
    /// What the last layout showed, so a change knows whether the indicator is growing.
    private var showsIndicator = false
    private var indicatorIsAtCaret = false

    func show(controller: DictationController) {
        let size = DictationPanelLayout.size(for: controller)
        if let panel {
            shade(panel, for: controller)
            // A new dictation reuses a notice's panel; it still opens at its own caret.
            if controller.phase == .preparing {
                place(panel, size: size, for: controller)
            } else {
                resize(panel, to: size, for: controller)
            }
            panel.orderFrontRegardless()
            return
        }
        let panel = DictationPanelWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.setAccessibilityIdentifier("dictation-panel")
        panel.level = UITestWindowPlacement.floatingPanelLevel()
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.showsIndicator = { [weak controller] in
            controller.map { DictationCompactIndicator.applies(to: $0) } ?? false
        }
        panel.indicatorClicked = { [weak controller] in controller?.expandCompactIndicator() }
        shade(panel, for: controller)
        panel.contentView = NSHostingView(
            rootView: DictationStripView(
                controller: controller,
                growthAnchor: { [weak self] in
                    DictationCompactIndicator.growthAnchor(
                        pinned: self?.pinnedEdge ?? .bottom, atCaret: self?.indicatorIsAtCaret ?? false)
                },
                relayout: { [weak self] in self?.relayout(for: controller) }
            ).secreteoLocalized())
        place(panel, size: size, for: controller)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Beside the caret (or pointer) when known; otherwise bottom-center above the Dock.
    private func place(_ panel: NSPanel, size: NSSize, for controller: DictationController) {
        let anchor = controller.panelAnchor
        showsIndicator = DictationCompactIndicator.applies(to: controller)
        indicatorIsAtCaret = false
        let screen = anchor.flatMap { anchor in NSScreen.screens.first { $0.frame.contains(anchor.point) } }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin: NSPoint
        if showsIndicator {
            if case .caret = anchor { indicatorIsAtCaret = true }
            let glyph = DictationCompactIndicator.size(for: .current())
            origin = DictationCompactIndicator.origin(for: glyph, near: anchor, in: visible)
            pinnedEdge = DictationCompactIndicator.pinnedEdge(for: glyph, near: anchor, in: visible)
        } else if let anchor {
            origin = DictationPanelAnchor.origin(for: size, near: anchor, in: visible)
            pinnedEdge = DictationPanelAnchor.pinnedEdge(for: size, near: anchor, in: visible)
        } else {
            pinnedEdge = .bottom
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + DictationCompactIndicator.fallbackLift)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Follows a layout change without ever reopening a closed panel.
    private func relayout(for controller: DictationController) {
        guard let panel else { return }
        shade(panel, for: controller)
        resize(panel, to: DictationPanelLayout.size(for: controller), for: controller)
    }

    /// The capsule and the bare glyph draw their own edge; the window's shadow would outline a rectangle.
    private func shade(_ panel: NSPanel, for controller: DictationController) {
        let wanted = DictationCompactIndicator.applies(to: controller)
            ? DictationCompactIndicator.Options.current().showsBackdrop
            : !DictationPanelLayout.isCapsule(controller.phase)
        guard panel.hasShadow != wanted else { return }
        panel.hasShadow = wanted
        panel.invalidateShadow()
    }

    /// The window takes its new frame at once; the card's own transition does the growing, so nothing is cut.
    private func resize(_ panel: NSPanel, to size: NSSize, for controller: DictationController) {
        let grows = showsIndicator
        showsIndicator = DictationCompactIndicator.applies(to: controller)
        guard panel.frame.size != size else { return }
        guard let visible = panel.screen?.visibleFrame else {
            panel.setContentSize(size)
            return
        }
        let margin = DictationCompactIndicator.margin
        // The glyph, not its clear margin, is what the card grows from.
        let origin = grows && !showsIndicator
            ? DictationCompactIndicator.origin(
                growingFrom: panel.frame.insetBy(dx: margin, dy: margin), to: size, pinned: pinnedEdge,
                in: visible, atCaret: indicatorIsAtCaret)
            // An option switched mid-dictation resizes the indicator from its corner.
            : DictationPanelAnchor.origin(
                resizing: panel.frame, to: size, pinned: pinnedEdge, in: visible,
                keepsLeading: grows && showsIndicator)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// While it shows the small indicator, a click opens the capsule and a drag moves it.
private final class DictationPanelWindow: NSPanel {
    var showsIndicator: () -> Bool = { false }
    var indicatorClicked: () -> Void = {}
    private var press: (pointer: NSPoint, origin: NSPoint, moved: Bool)?
    private var expandedAt: Date?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        let indicator = showsIndicator()
        let isPress = event.type == .leftMouseDown || event.type == .leftMouseUp
        if isPress, press == nil, DictationCompactIndicator.swallowsPress(
            clickCount: indicator ? event.clickCount : 1,
            sinceExpansion: expandedAt.map { Date.now.timeIntervalSince($0) },
            doubleClick: NSEvent.doubleClickInterval) { return }
        switch event.type {
        case .leftMouseDown where indicator:
            press = (NSEvent.mouseLocation, frame.origin, false)
        case .leftMouseDragged where press != nil:
            guard var held = press else { return }
            let pointer = NSEvent.mouseLocation
            let travel = CGSize(width: pointer.x - held.pointer.x, height: pointer.y - held.pointer.y)
            guard held.moved || !DictationCompactIndicator.isClick(translation: travel) else { return }
            held.moved = true
            press = held
            setFrameOrigin(NSPoint(x: held.origin.x + travel.width, y: held.origin.y + travel.height))
        case .leftMouseUp where press != nil:
            let moved = press?.moved == true
            press = nil
            guard !moved else { return }
            expandedAt = .now
            indicatorClicked()
        default:
            super.sendEvent(event)
        }
    }
}

private struct DictationStripView: View {
    let controller: DictationController
    let growthAnchor: () -> UnitPoint
    /// Lets the panel follow phases that change without an explicit re-show, such as a failure.
    let relayout: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reads the signal, so a switch flipped in Settings mid-dictation resizes the indicator.
    private var options: DictationCompactIndicator.Options {
        _ = DictationPreferenceSignal.shared.revision
        return .current()
    }

    var body: some View {
        let showsIndicator = DictationCompactIndicator.applies(to: controller)
        let options = options
        Group {
            if showsIndicator {
                DictationAsideView(controller: controller, options: options)
                    .transition(.identity)
            } else {
                fullStrip
                    .transition(.asymmetric(insertion: growth, removal: .identity))
            }
        }
        .animation(
            DictationCapsuleMotion.indicatorChange(
                microphoneIsOpen: DictationWaveform.animates(for: controller),
                duration: DictationCompactIndicator.growth),
            value: showsIndicator)
        .onChange(of: DictationPanelLayout.size(for: controller, options: options)) { relayout() }
    }

    /// While the microphone is open the indicator grows into its capsule; Reduce Motion cross-fades instead.
    private var growth: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: DictationCompactIndicator.growthStart, anchor: growthAnchor()).combined(with: .opacity)
    }

    @ViewBuilder private var fullStrip: some View {
        if DictationPanelLayout.isCapsule(controller.phase) {
            DictationCapsuleView(controller: controller)
        } else {
            Group {
                if case .recovery(let failure) = controller.phase {
                    DictationRecoveryView(controller: controller, failure: failure)
                } else if case .verified(let words) = controller.phase {
                    verifiedDeliveryView(words)
                } else if controller.phase == .noSpeech {
                    DictationNoSpeechView(controller: controller)
                } else if case .dispatched = controller.phase {
                    DictationUnverifiedDeliveryView(controller: controller)
                }
            }
            .padding(12)
            .frame(width: DictationPanelLayout.width, height: DictationPanelLayout.size(for: controller).height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// The brief confirmation after insertion: N words → the target app,
    /// and whether the dictation history kept it.
    private func verifiedDeliveryView(_ words: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: SecreteoSymbol.success)
                .foregroundStyle(SecreteoDesign.verified)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.correctionSummary ?? insertedTitle(words))
                    .accessibilityIdentifier("dictation-panel-delivery-status")
                    .font(.callout.weight(.medium))
                Text(controller.deliveryPrivacyLine)
                    .accessibilityIdentifier("dictation-panel-delivery-detail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notice = controller.polishNotice {
                    Text(notice)
                        .accessibilityIdentifier("dictation-panel-polish-notice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let learnable = controller.learnableCorrection {
                Button(L10n.format("Always write “%@”", learnable.rule.replacement)) {
                    controller.learnCorrection()
                }
                .controlSize(.small)
                .help(L10n.format(
                    "Adds “%@” → “%@” to your text replacements.", learnable.rule.trigger, learnable.rule.replacement))
                .accessibilityIdentifier("dictation-panel-learn-correction")
            }
        }
    }

    private func insertedTitle(_ words: Int) -> String {
        if let target = controller.targetApp {
            return L10n.format("%d words inserted into %@.", words, target)
        }
        return L10n.format("%d words inserted.", words)
    }
}
