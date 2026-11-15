import AppKit
import SwiftUI

/// Off by default. While dictating, the panel shrinks to the two parentheses under the caret;
/// outcomes that need an action still open the full panel.
enum DictationCompactIndicator {
    static let defaultsKey = "dictationCompactIndicator"
    static let elapsedTimeKey = "dictationCompactShowsElapsedTime"
    static let backdropKey = "dictationCompactShowsBackdrop"

    struct Options: Equatable {
        var showsElapsedTime = false
        var showsBackdrop = false

        static func current(_ defaults: UserDefaults = .standard) -> Self {
            Options(
                showsElapsedTime: defaults.bool(forKey: elapsedTimeKey),
                showsBackdrop: defaults.bool(forKey: backdropKey))
        }
    }

    static let glyphSize = NSSize(width: 30, height: 24)
    static let widthWithTime: CGFloat = 68
    static let beadHeight: CGFloat = 30
    /// Under the caret's line; without a caret, this far above the bottom of the screen.
    static let caretGap: CGFloat = 6
    static let fallbackLift: CGFloat = 48
    static let fade: Duration = .milliseconds(300)
    static let growth: TimeInterval = 0.32
    static let growthStart: CGFloat = 0.06
    /// Clear room around the glyph, so the window does not cut its shadow.
    static let margin: CGFloat = 4
    /// A press that travels farther moves the indicator instead of opening the capsule.
    static let clickSlop: CGFloat = 3

    static func size(for options: Options) -> NSSize {
        NSSize(
            width: options.showsElapsedTime ? widthWithTime : glyphSize.width,
            height: options.showsBackdrop ? beadHeight : glyphSize.height)
    }

    static func windowSize(for options: Options) -> NSSize {
        let size = size(for: options)
        return NSSize(width: size.width + 2 * margin, height: size.height + 2 * margin)
    }

    /// The corner a card grows from: the one the window keeps.
    static func growthAnchor(pinned: DictationPanelAnchor.PinnedEdge, atCaret: Bool) -> UnitPoint {
        switch (pinned, atCaret) {
        case (.top, true): .topLeading
        case (.top, false): .top
        case (.bottom, true): .bottomLeading
        case (.bottom, false): .bottom
        }
    }

    /// A microphone notice needs the full capsule's words, and a click on the glyph asks for it.
    @MainActor
    static func applies(to controller: DictationController, defaults: UserDefaults = .standard) -> Bool {
        guard controller.microphoneNotice == nil, !controller.compactIndicatorExpanded else { return false }
        // No speech shows its face for a moment before the card with the words to keep.
        return applies(to: controller.phase, defaults: defaults)
            || (controller.phase == .noSpeech && defaults.bool(forKey: defaultsKey))
    }

    static func applies(to phase: DictationController.Phase, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: defaultsKey) else { return false }
        switch phase {
        case .preparing, .listening, .delivering, .verified, .dispatched: return true
        default: return false
        }
    }

    /// How long a result's face stays before it fades or gives way to its card.
    static func hold(for phase: DictationController.Phase) -> Duration? {
        switch phase {
        case .verified: .milliseconds(1_400)
        case .dispatched, .noSpeech: .milliseconds(1_200)
        default: nil
        }
    }

    /// When the controller closes a result shown as a face; nil leaves the full panel's timing.
    @MainActor
    static func dismissal(for controller: DictationController) -> Duration? {
        guard applies(to: controller), let hold = hold(for: controller.phase) else { return nil }
        return hold + fade
    }

    static func isClick(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) <= clickSlop
    }

    /// Where the window goes so the glyph inside its margin has its left edge on the caret,
    /// just under its line; above it when there is no room below.
    static func origin(for size: NSSize, near anchor: DictationPanelAnchor?, in visible: NSRect) -> NSPoint {
        guard case .caret(let caret) = anchor else {
            return NSPoint(x: visible.midX - size.width / 2 - margin, y: visible.minY + fallbackLift - margin)
        }
        var y = caret.minY - caretGap - size.height
        if y < visible.minY { y = caret.maxY + caretGap }
        return NSPoint(
            x: min(max(caret.minX, visible.minX), visible.maxX - size.width) - margin,
            y: min(max(y, visible.minY), visible.maxY - size.height) - margin)
    }

    static func pinnedEdge(
        for size: NSSize, near anchor: DictationPanelAnchor?, in visible: NSRect
    ) -> DictationPanelAnchor.PinnedEdge {
        guard case .caret(let caret) = anchor else { return .bottom }
        return caret.minY - caretGap - size.height >= visible.minY ? .top : .bottom
    }

    static func elapsed(since start: Date?, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start ?? now)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension DictationController {
    /// A click on the small indicator: the full capsule for the rest of this dictation.
    func expandCompactIndicator() {
        guard isActive || phase == .noSpeech else { return }
        expandedSessionID = activeSessionID ?? deliveryID
    }

    /// Keyed to the dictation, so the next one starts small again.
    var compactIndicatorExpanded: Bool {
        expandedSessionID != nil && expandedSessionID == activeSessionID ?? deliveryID
    }
}
