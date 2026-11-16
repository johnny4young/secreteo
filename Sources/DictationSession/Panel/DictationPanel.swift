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
    private var outcome: DictationPanelOutcome?
    /// What the shown outcome's content measured; nil until it has.
    private var outcomeHeight: CGFloat?
    /// What the last layout showed, so a change knows whether the indicator is growing.
    private var showsIndicator = false

    func show(controller: DictationController) {
        track(controller, presented: true)
        let size = size(for: controller)
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
        let content = NSHostingView(
            rootView: DictationStripView(controller: controller, placement: placement) { [weak self] measured in
                self?.relayout(for: controller, measured: measured)
            }.secreteoLocalized())
        // The layout decides the size; the hosting view must not constrain the window too.
        content.sizingOptions = []
        panel.contentView = content
        place(panel, size: size, for: controller)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        outcome = nil
        outcomeHeight = nil
    }

    private func track(_ controller: DictationController, presented: Bool) {
        let shown = DictationPanelOutcome(phase: controller.phase, delivery: controller.deliveryID)
        if DictationPanelLayout.startsNewOutcome(shown, after: outcome, presented: presented) {
            placement.outcomeSerial += 1
            outcomeHeight = nil
        }
        outcome = shown
    }

    private func size(for controller: DictationController) -> NSSize {
        DictationPanelLayout.size(
            for: controller, outcomeHeight: outcomeHeight,
            visible: (panel?.screen ?? NSScreen.main)?.visibleFrame.size)
    }

    /// Beside the caret (or pointer) when known; otherwise bottom-center above the Dock.
    private func place(_ panel: NSPanel, size: NSSize, for controller: DictationController) {
        let anchor = controller.panelAnchor
        showsIndicator = DictationCompactIndicator.applies(to: controller)
        placement.indicatorIsAtCaret = false
        let screen = anchor.flatMap { anchor in NSScreen.screens.first { $0.frame.contains(anchor.point) } }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin: NSPoint
        if showsIndicator {
            if case .caret = anchor { placement.indicatorIsAtCaret = true }
            let glyph = DictationCompactIndicator.size(for: .current())
            origin = DictationCompactIndicator.origin(for: glyph, near: anchor, in: visible)
            placement.pinnedEdge = DictationCompactIndicator.pinnedEdge(for: glyph, near: anchor, in: visible)
        } else if let anchor {
            origin = DictationPanelAnchor.origin(for: size, near: anchor, in: visible)
            placement.pinnedEdge = DictationPanelAnchor.pinnedEdge(for: size, near: anchor, in: visible)
        } else {
            placement.pinnedEdge = .bottom
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + DictationCompactIndicator.fallbackLift)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Follows a layout change without ever reopening a closed panel.
    private func relayout(for controller: DictationController, measured: DictationStripView.Measurement?) {
        guard let panel else { return }
        track(controller, presented: false)
        // A height that arrives late from the outcome before this one is not this one's.
        if let measured, measured.serial == placement.outcomeSerial { outcomeHeight = measured.height }
        shade(panel, for: controller)
        resize(panel, to: size(for: controller), for: controller)
    }

    /// The capsule, the pill and the bare glyph draw their own edge and change shape; only the cards and
    /// the indicator's bead keep the window's shadow.
    private func shade(_ panel: NSPanel, for controller: DictationController) {
        let wanted = DictationCompactIndicator.applies(to: controller)
            ? DictationCompactIndicator.Options.current().showsBackdrop
            : DictationPanelLayout.isCard(controller.phase)
        guard panel.hasShadow != wanted else { return }
        panel.hasShadow = wanted
        panel.invalidateShadow()
    }

    /// The window takes its new frame at once; the content's own transition does the growing, so nothing is cut.
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
                growingFrom: panel.frame.insetBy(dx: margin, dy: margin), to: size, pinned: placement.pinnedEdge,
                in: visible, atCaret: placement.indicatorIsAtCaret)
            // An option switched mid-dictation resizes the indicator from its corner.
            : DictationPanelAnchor.origin(
                resizing: panel.frame, to: size, pinned: placement.pinnedEdge, in: visible,
                keepsLeading: grows && showsIndicator)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.hasShadow { panel.invalidateShadow() }
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

/// The edge the panel keeps when its height changes, shared with the content it hosts.
@MainActor
@Observable
final class DictationPanelPlacement {
    var pinnedEdge = DictationPanelAnchor.PinnedEdge.bottom
    /// The small indicator stands on a caret, so what replaces it grows from its leading corner.
    var indicatorIsAtCaret = false
    /// Changes with every new outcome, so its view starts from fresh state.
    var outcomeSerial = 0
}

private struct DictationStripView: View {
    struct Measurement {
        let serial: Int
        let height: CGFloat
    }

    let controller: DictationController
    let placement: DictationPanelPlacement
    /// Lets the panel follow phases that change without an explicit re-show, such as a failure,
    /// and the height an outcome's content measures.
    let relayout: (Measurement?) -> Void
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
            } else if DictationPanelLayout.isCapsule(controller.phase) {
                DictationCapsuleView(controller: controller)
                    .transition(.asymmetric(insertion: growth, removal: .identity))
            } else {
                let serial = placement.outcomeSerial
                outcome
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        relayout(Measurement(serial: serial, height: $0))
                    }
                    .id(serial)
                    // Dark over any app and in either appearance, like the capsule.
                    .environment(\.colorScheme, .dark)
                    .transition(.asymmetric(insertion: growth, removal: .identity))
            }
        }
        .animation(
            DictationCapsuleMotion.indicatorChange(
                microphoneIsOpen: DictationWaveform.animates(for: controller),
                duration: DictationCompactIndicator.growth)
                ?? DictationCapsuleMotion.settledChange(
                    to: controller.phase, duration: DictationCompactIndicator.growth),
            value: showsIndicator)
        // The content sits on the edge the panel keeps, so it never jumps while the window follows.
        .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: placement.pinnedEdge == .top ? .topLeading : .bottomLeading)
        .onChange(of: DictationPanelLayout.size(for: controller, options: options)) { relayout(nil) }
        .onChange(of: DictationPanelLayout.isCapsule(controller.phase)) { relayout(nil) }
    }

    /// The indicator grows into its capsule or its settled card; Reduce Motion cross-fades instead.
    private var growth: AnyTransition {
        let anchor = DictationCompactIndicator.growthAnchor(
            pinned: placement.pinnedEdge, atCaret: placement.indicatorIsAtCaret)
        return reduceMotion
            ? .opacity
            : .scale(scale: DictationCompactIndicator.growthStart, anchor: anchor).combined(with: .opacity)
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
