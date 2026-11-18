import DictationKit
import Foundation

/// What the menu's header and primary action are about.
enum DictationMenuState: Equatable {
    case ready
    /// A dictation is running or just ended; the face says which.
    case live
    case standingBy
    /// On, but not able to dictate yet: preparing, taking over, or blocked by another app.
    case notReady
    case setUp
}

extension DictationFeature {
    var menuState: DictationMenuState {
        Self.menuState(
            isIdle: controller.phase == .idle, canDictate: canDictate, isEnabled: isEnabled,
            canTakeOwnership: canTakeOwnership)
    }

    nonisolated static func menuState(
        isIdle: Bool, canDictate: Bool, isEnabled: Bool, canTakeOwnership: Bool
    ) -> DictationMenuState {
        if canDictate { return isIdle ? .ready : .live }
        guard isEnabled else { return .setUp }
        return canTakeOwnership ? .standingBy : .notReady
    }

    /// The popover keeps one view, so a day that turned while it was closed needs an explicit refresh.
    public func menuWillOpen() {
        Task { await stats.refreshWeek() }
    }

    var menuTitle: String {
        switch menuState {
        case .ready: L10n.text("Ready")
        case .live: statusFace.accessibilityName
        case .standingBy: L10n.text("Standing by")
        case .notReady: L10n.text("Not ready yet")
        case .setUp: L10n.text("Dictation is off")
        }
    }

    /// Who owns dictation and what hears it; nil when there is nothing true to say.
    var menuDetail: String? {
        switch menuState {
        case .ready, .live: L10n.format("Secreteo owns dictation · %@ on this Mac", speechEngine.displayName)
        case .standingBy: L10n.text("Another app handles dictation on this Mac")
        case .setUp, .notReady: unavailableMessage
        }
    }

    /// Nil as soon as Paste Last is not possible, so the words never outlive it on screen.
    var lastDictation: DictationLastText.Entry? {
        canPasteLast ? controller.lastText.currentEntry : nil
    }

    var holdKeyLabel: String? {
        _ = preferenceRevision
        return ModifierKeySetting.load(from: defaults).keyCapLabel
    }

    /// Held Fn also runs macOS's own “Press 🌐 key to” action unless that is set to Do Nothing.
    var fnKeyConflicts: Bool {
        _ = preferenceRevision
        return ModifierKeySetting.load(from: defaults) == .function && !fnKeyIsFree
    }

    /// Nil while another app holds the shortcut, because pressing it would do nothing.
    var dictationShortcutLabel: String? {
        shortcutIsUnavailable ? nil : controller.shortcut.setting.label
    }

    var pasteLastShortcutLabel: String? {
        pasteLastShortcutBinding.wrappedValue && !pasteLastShortcutIsUnavailable
            ? PasteLastShortcut.setting.label : nil
    }

    public var rewriteSelectionShortcutLabel: String? {
        rewriteSelectionShortcutBinding.wrappedValue && !rewriteSelectionShortcutIsUnavailable
            ? RewriteSelectionShortcut.setting.label : nil
    }
}

extension ModifierKeySetting {
    var keyCapLabel: String? {
        switch self {
        case .off: nil
        case .function: "fn"
        case .rightOption: L10n.text("right ⌥")
        case .rightCommand: L10n.text("right ⌘")
        }
    }
}

extension LiveSpeechSelection {
    var displayName: String {
        switch self {
        case .parakeet: L10n.text("Parakeet")
        case .parakeetUltra: L10n.text("Parakeet Ultra")
        case .appleSpeech: L10n.text("Apple Speech")
        }
    }
}

enum DictationMenuFormat {
    static func age(of date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        return minutes < 1 ? L10n.text("Just now") : L10n.format("%d min ago", minutes)
    }

    static func eyebrow(app: String?) -> String {
        guard let app, !app.isEmpty else { return L10n.text("Last dictation") }
        return L10n.format("Last dictation · %@", app)
    }

    static func detail(_ totals: DictationStatsTotals) -> String {
        let saved = Int((totals.estimatedTimeSaved / 60).rounded())
        return totals.dictations == 1
            ? L10n.format("1 dictation · ~%d min saved", saved)
            : L10n.format("%d dictations · ~%d min saved", totals.dictations, saved)
    }

    /// Bar heights from 0 to 1 against the busiest day, oldest first.
    static func bars(_ days: [DictationStatsDay]) -> [Double] {
        let peak = max(days.map(\.totals.words).max() ?? 0, 1)
        return days.map { Double($0.totals.words) / Double(peak) }
    }
}
