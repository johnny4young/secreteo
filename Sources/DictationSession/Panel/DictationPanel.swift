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
    /// The size last asked for; a frame that is still animating has not reached it.
    private var wantedSize: NSSize?

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
            rootView: DictationStripView(controller: controller) { [weak self] in
                self?.relayout(for: controller)
            }.secreteoLocalized())
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
        wantedSize = size
        let screen = anchor.flatMap { anchor in NSScreen.screens.first { $0.frame.contains(anchor.point) } }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin: NSPoint
        if showsIndicator {
            if case .caret = anchor { indicatorIsAtCaret = true }
            origin = DictationCompactIndicator.origin(for: size, near: anchor, in: visible)
            pinnedEdge = DictationCompactIndicator.pinnedEdge(for: size, near: anchor, in: visible)
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

    private func resize(_ panel: NSPanel, to size: NSSize, for controller: DictationController) {
        let grows = showsIndicator
        showsIndicator = DictationCompactIndicator.applies(to: controller)
        guard (wantedSize ?? panel.frame.size) != size else { return }
        wantedSize = size
        guard let visible = panel.screen?.visibleFrame else {
            panel.setContentSize(size)
            return
        }
        let frame = NSRect(
            origin: DictationPanelAnchor.origin(
                resizing: panel.frame, to: size, pinned: pinnedEdge, in: visible,
                keepsLeading: grows && indicatorIsAtCaret),
            size: size)
        // The indicator grows into its card where it stands.
        if grows, !showsIndicator, !DictationPanelLayout.isCapsule(controller.phase),
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DictationCompactIndicator.growth
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}

/// While it shows the small indicator, a click opens the capsule and a drag moves it.
private final class DictationPanelWindow: NSPanel {
    var showsIndicator: () -> Bool = { false }
    var indicatorClicked: () -> Void = {}
    private var press: (pointer: NSPoint, origin: NSPoint, moved: Bool)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown where showsIndicator():
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
            if !moved { indicatorClicked() }
        default:
            super.sendEvent(event)
        }
    }
}

private struct DictationStripView: View {
    let controller: DictationController
    /// Lets the panel follow phases that change without an explicit re-show, such as a failure.
    let relayout: () -> Void

    var body: some View {
        Group {
            if DictationCompactIndicator.applies(to: controller) {
                DictationAsideView(controller: controller)
            } else {
                fullStrip
            }
        }
        .onChange(of: DictationPanelLayout.size(for: controller)) { relayout() }
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
