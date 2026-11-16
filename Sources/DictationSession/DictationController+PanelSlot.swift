import AppKit

extension DictationController {
    /// A panel in a window's slot follows that window.
    func panelSlotMoved(to slot: NSRect) {
        guard case .slot = panelAnchor, phase != .idle else { return }
        panelAnchor = .slot(slot)
        panel.move(to: .slot(slot))
    }

    /// Without its window the panel would float over nothing, so the dictation in it ends.
    func panelSlotClosed() {
        guard case .slot = panelAnchor, phase != .idle else { return }
        cancel()
    }
}
