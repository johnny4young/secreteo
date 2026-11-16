import AppKit
import SwiftUI

/// Same non-activating recipe as the dictation capsule: the edited app keeps focus,
/// so the selection and the paste stay where the user left them.
@MainActor
final class SelectionRewritePanelController {
    private var panel: NSPanel?
    private var lift = SelectionRewriteLayout.Lift()

    /// The controller re-shows on every phase change; AppKit owns the one height.
    /// `behindCapsule`: the dictation's panel is showing, and the card never covers it.
    func show(controller: SelectionRewriteController, behindCapsule: Bool) {
        let size = SelectionRewriteView.size(for: controller)
        if let panel {
            resize(panel, to: size, lifted: controller.staysAboveCapsule)
            if !behindCapsule { panel.orderFrontRegardless() }
            return
        }
        let panel = SelectionRewritePanelWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.setAccessibilityIdentifier("rewrite-panel")
        panel.level = UITestWindowPlacement.floatingPanelLevel()
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let hosting = NSHostingView(rootView: SelectionRewriteView(controller: controller).secreteoLocalized())
        hosting.sizingOptions = []
        panel.contentView = hosting
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 48))
        }
        resize(panel, to: size, lifted: controller.staysAboveCapsule)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        lift = SelectionRewriteLayout.Lift()
    }

    /// Grows upward from the bottom edge and stays on screen.
    private func resize(_ panel: NSPanel, to size: NSSize, lifted: Bool) {
        guard panel.contentRect(forFrameRect: panel.frame).size != size || lifted != lift.isLifted else { return }
        let origin = panel.frame.origin
        panel.setContentSize(size)
        guard let visible = panel.screen?.visibleFrame else { return }
        let y = lift.origin(
            from: origin.y, height: panel.frame.height, lifted: lifted, within: visible.minY...visible.maxY)
        panel.setFrameOrigin(NSPoint(x: origin.x, y: y))
    }
}

private final class SelectionRewritePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}
