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

    func show(controller: DictationController) {
        let size = DictationPanelLayout.size(for: controller)
        if let panel {
            shade(panel, for: controller)
            resize(panel, to: size)
            // A new dictation reuses a notice's panel; it still opens at its own caret.
            if controller.phase == .preparing { place(panel, size: size, near: controller.panelAnchor) }
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
        shade(panel, for: controller)
        panel.contentView = NSHostingView(
            rootView: DictationStripView(controller: controller) { [weak self] in
                self?.relayout(for: controller)
            }.secreteoLocalized())
        place(panel, size: size, near: controller.panelAnchor)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Beside the caret (or pointer) when known; otherwise bottom-center above the Dock.
    private func place(_ panel: NSPanel, size: NSSize, near anchor: DictationPanelAnchor?) {
        if let anchor,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.point) }) ?? NSScreen.main {
            panel.setFrameOrigin(DictationPanelAnchor.origin(for: size, near: anchor, in: screen.visibleFrame))
            pinnedEdge = DictationPanelAnchor.pinnedEdge(for: size, near: anchor, in: screen.visibleFrame)
        } else if let screen = NSScreen.main {
            pinnedEdge = .bottom
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 48))
        }
    }

    /// Follows a layout change without ever reopening a closed panel.
    private func relayout(for controller: DictationController) {
        guard let panel else { return }
        shade(panel, for: controller)
        resize(panel, to: DictationPanelLayout.size(for: controller))
    }

    /// The capsule draws its own edge; the window's shadow would outline a rectangle around it.
    private func shade(_ panel: NSPanel, for controller: DictationController) {
        let wanted = DictationCompactIndicator.applies(to: controller)
            || !DictationPanelLayout.isCapsule(controller.phase)
        guard panel.hasShadow != wanted else { return }
        panel.hasShadow = wanted
        panel.invalidateShadow()
    }

    private func resize(_ panel: NSPanel, to size: NSSize) {
        guard panel.contentRect(forFrameRect: panel.frame).size != size else { return }
        let before = panel.frame
        panel.setContentSize(size)
        guard let visible = panel.screen?.visibleFrame else { return }
        panel.setFrameOrigin(DictationPanelAnchor.origin(
            resizing: before, to: panel.frame.size, pinned: pinnedEdge, in: visible))
    }
}

private final class DictationPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct DictationStripView: View {
    let controller: DictationController
    /// Lets the panel follow phases that change without an explicit re-show, such as a failure.
    let relayout: () -> Void

    var body: some View {
        Group {
            if DictationCompactIndicator.applies(to: controller) {
                DictationCompactStripView(controller: controller)
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
