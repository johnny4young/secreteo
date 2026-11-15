import AppKit
import SwiftUI
import DictationKit

/// The floating dictation strip: same non-activating panel recipe as the
/// recording HUD — always on top, never steals focus, so the keystrokes
/// keep landing in the app the user is dictating INTO.
@MainActor
final class DictationPanelController {
    private var panel: NSPanel?
    private let placement = DictationPanelPlacement()
    /// The last height an outcome's content measured.
    private var outcomeHeight: CGFloat?

    func show(controller: DictationController) {
        let size = size(for: controller)
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
        let content = NSHostingView(
            rootView: DictationStripView(controller: controller, placement: placement) { [weak self] measured in
                self?.relayout(for: controller, outcomeHeight: measured)
            }.secreteoLocalized())
        // The layout decides the size; the hosting view must not constrain the window too.
        content.sizingOptions = []
        panel.contentView = content
        place(panel, size: size, near: controller.panelAnchor)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        outcomeHeight = nil
    }

    private func size(for controller: DictationController) -> NSSize {
        DictationPanelLayout.size(
            for: controller, outcomeHeight: outcomeHeight,
            visible: (panel?.screen ?? NSScreen.main)?.visibleFrame.size)
    }

    /// Beside the caret (or pointer) when known; otherwise bottom-center above the Dock.
    private func place(_ panel: NSPanel, size: NSSize, near anchor: DictationPanelAnchor?) {
        if let anchor,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.point) }) ?? NSScreen.main {
            panel.setFrameOrigin(DictationPanelAnchor.origin(for: size, near: anchor, in: screen.visibleFrame))
            placement.pinnedEdge = DictationPanelAnchor.pinnedEdge(for: size, near: anchor, in: screen.visibleFrame)
        } else if let screen = NSScreen.main {
            placement.pinnedEdge = .bottom
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 48))
        }
    }

    /// Follows a layout change without ever reopening a closed panel.
    private func relayout(for controller: DictationController, outcomeHeight measured: CGFloat?) {
        guard let panel else { return }
        if let measured { outcomeHeight = measured }
        shade(panel, for: controller)
        resize(panel, to: size(for: controller))
    }

    /// The capsule and the pill draw their own edge and change shape; only the cards keep the window's shadow.
    private func shade(_ panel: NSPanel, for controller: DictationController) {
        let wanted = DictationCompactIndicator.applies(to: controller)
            || DictationPanelLayout.isCard(controller.phase)
        guard panel.hasShadow != wanted else { return }
        panel.hasShadow = wanted
        panel.invalidateShadow()
    }

    private func resize(_ panel: NSPanel, to size: NSSize) {
        guard panel.contentRect(forFrameRect: panel.frame).size != size else { return }
        let before = panel.frame
        panel.setContentSize(size)
        if panel.hasShadow { panel.invalidateShadow() }
        guard let visible = panel.screen?.visibleFrame else { return }
        panel.setFrameOrigin(DictationPanelAnchor.origin(
            resizing: before, to: panel.frame.size, pinned: placement.pinnedEdge, in: visible))
    }
}

private final class DictationPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The edge the panel keeps when its height changes, shared with the content it hosts.
@MainActor
@Observable
final class DictationPanelPlacement {
    var pinnedEdge = DictationPanelAnchor.PinnedEdge.bottom
}

private struct DictationStripView: View {
    let controller: DictationController
    let placement: DictationPanelPlacement
    /// Lets the panel follow phases that change without an explicit re-show, such as a failure,
    /// and the height an outcome's content measures.
    let relayout: (CGFloat?) -> Void

    var body: some View {
        Group {
            if DictationCompactIndicator.applies(to: controller) {
                DictationCompactStripView(controller: controller)
            } else if DictationPanelLayout.isCapsule(controller.phase) {
                DictationCapsuleView(controller: controller)
            } else {
                outcome
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { relayout($0) }
                    // Dark over any app and in either appearance, like the capsule.
                    .environment(\.colorScheme, .dark)
            }
        }
        // The content sits on the edge the panel keeps, so it never jumps while the window follows.
        .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: placement.pinnedEdge == .top ? .topLeading : .bottomLeading)
        .onChange(of: DictationPanelLayout.size(for: controller)) { relayout(nil) }
        .onChange(of: DictationPanelLayout.isCapsule(controller.phase)) { relayout(nil) }
    }

    @ViewBuilder private var outcome: some View {
        switch controller.phase {
        case .recovery(let failure): DictationRecoveryView(controller: controller, failure: failure)
        case .verified(let words): DictationResultPill(controller: controller, words: words)
        case .noSpeech: DictationNoSpeechView(controller: controller)
        case .dispatched: DictationUnverifiedDeliveryView(controller: controller)
        default: EmptyView()
        }
    }
}
