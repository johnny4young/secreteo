import AppKit
import ApplicationServices

/// Where the dictation strip first appears: just under the text caret when the
/// focused app exposes its bounds, otherwise beside the mouse pointer.
enum DictationPanelAnchor: Equatable {
    /// Cocoa screen coordinates (bottom-left origin).
    case caret(NSRect)
    case pointer(NSPoint)
    /// A place a window keeps for the strip: centred in it, hanging from its top edge.
    case slot(NSRect)

    /// Reads only geometry, never text; secure fields fall back to the pointer.
    @MainActor
    static func current() -> Self {
        if let caret = caretRect() { return .caret(caret) }
        return .pointer(NSEvent.mouseLocation)
    }

    /// The edge that stays put when the panel's height changes.
    enum PinnedEdge: Equatable { case top, bottom }

    private var target: NSRect {
        switch self {
        case .caret(let rect), .slot(let rect): rect
        // Leave room for the cursor glyph itself.
        case .pointer(let point): NSRect(x: point.x, y: point.y - 20, width: 0, height: 20)
        }
    }

    /// A panel under its anchor grows downward, away from the line being written.
    static func pinnedEdge(for size: NSSize, near anchor: Self, in visible: NSRect, gap: CGFloat = 8) -> PinnedEdge {
        // The window's own words sit above its slot, so anything taller grows down from it.
        if case .slot = anchor { return .top }
        return anchor.target.minY - gap - size.height >= visible.minY ? .top : .bottom
    }

    /// Where a panel that changes size goes: one edge stays, and a panel that keeps its width keeps its place.
    static func origin(
        resizing frame: NSRect, to size: NSSize, pinned: PinnedEdge, in visible: NSRect, keepsLeading: Bool = false
    ) -> NSPoint {
        let y = pinned == .top ? frame.maxY - size.height : frame.minY
        guard size.width != frame.width else {
            return NSPoint(x: frame.minX, y: pinned == .top ? max(visible.minY, y) : min(y, visible.maxY - size.height))
        }
        // The indicator under a caret grows from the caret; anywhere else, around its center.
        let x = keepsLeading ? frame.minX : frame.midX - size.width / 2
        return NSPoint(
            x: max(visible.minX, min(x, visible.maxX - size.width)),
            y: max(visible.minY, min(y, visible.maxY - size.height)))
    }

    /// Below the anchor when it fits, otherwise above it, always inside `visible`.
    static func origin(for size: NSSize, near anchor: Self, in visible: NSRect, gap: CGFloat = 8) -> NSPoint {
        if case .slot(let slot) = anchor {
            return NSPoint(
                x: min(max(slot.midX - size.width / 2, visible.minX), visible.maxX - size.width),
                y: min(max(slot.maxY - size.height, visible.minY), visible.maxY - size.height))
        }
        let target = anchor.target
        var y = target.minY - gap - size.height
        if y < visible.minY { y = target.maxY + gap }
        let x = min(max(target.minX - 16, visible.minX), visible.maxX - size.width)
        return NSPoint(x: x, y: min(max(y, visible.minY), visible.maxY - size.height))
    }

    /// AX geometry has a top-left origin on the primary screen; Cocoa uses a bottom-left one.
    static func cocoaRect(fromAccessibility rect: CGRect, primaryScreenHeight: CGFloat) -> NSRect {
        NSRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    var point: NSPoint {
        switch self {
        case .caret(let rect), .slot(let rect): NSPoint(x: rect.midX, y: rect.midY)
        case .pointer(let point): point
        }
    }

    @MainActor
    private static func caretRect() -> NSRect? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let primary = NSScreen.screens.first else { return nil }
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementSetMessagingTimeout(owner, 0.1) == .success,
              let element = TextInserter.focusedElement(in: owner),
              TextInserter.fieldSecurity(of: element) == .regular else { return nil }
        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
              let selection, let range = TextInserter.checkedCFValue(selection, as: .accessibilityValue),
              AXValueGetType(range) == .cfRange else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, let value = TextInserter.checkedCFValue(bounds, as: .accessibilityValue),
              AXValueGetType(value) == .cgRect else { return nil }
        var rect = CGRect.zero
        // Apps that cannot locate the caret report an empty rect at the origin.
        guard AXValueGetValue(value, .cgRect, &rect), rect.height > 0, rect.origin != .zero else { return nil }
        return cocoaRect(fromAccessibility: rect, primaryScreenHeight: primary.frame.height)
    }
}
