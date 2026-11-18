import AppKit

/// One size authority for AppKit and SwiftUI: a conflicting intrinsic size
/// otherwise moves the panel again after every explicit re-show.
enum DictationPanelLayout {
    static let width: CGFloat = 520
    static let capsuleHeight: CGFloat = 56
    static let noticeHeight: CGFloat = 22
    static let noticeSpacing: CGFloat = 4
    static let cardRadius: CGFloat = 25
    static let wordsFontSize: CGFloat = 24
    /// About four lines of the serif; longer text scrolls.
    static let wordsMaxHeight: CGFloat = 118
    /// The pill holds, then fades just before the controller closes the panel.
    static let resultContraction: TimeInterval = 0.32
    static let resultFade: Duration = .milliseconds(200)
    @MainActor static var resultHold: Duration { DictationController.verifiedFeedbackDuration - resultFade }

    /// A notice to read or a correction to answer keeps the panel open longer, and the pill with it.
    static func resultFades(showsNotice: Bool, offersCorrection: Bool) -> Bool {
        !showsNotice && !offersCorrection
    }

    /// Every presented result is a new pill; a card is new when its kind or its delivery changes,
    /// so showing a retained card again leaves it as it is.
    static func startsNewOutcome(
        _ shown: DictationPanelOutcome?, after previous: DictationPanelOutcome?, presented: Bool
    ) -> Bool {
        guard let shown else { return false }
        return shown != previous || (presented && shown.kind == .result)
    }

    /// Words fade at the bottom only while more of them wait below.
    static func wordsContinueBelow(offset: CGFloat, visible: CGFloat, content: CGFloat) -> Bool {
        content - (offset + visible) > 1
    }

    /// `outcomeHeight` is what the outcome's SwiftUI content last measured; `visible` is the screen's usable size.
    @MainActor
    static func size(
        for controller: DictationController, options: DictationCompactIndicator.Options = .current(),
        outcomeHeight: CGFloat? = nil, visible: CGSize? = nil
    ) -> NSSize {
        if DictationCompactIndicator.applies(to: controller) {
            return DictationCompactIndicator.windowSize(for: options)
        }
        if isCapsule(controller.phase) {
            return NSSize(width: width, height: capsuleHeight(showsNotice: controller.microphoneNotice != nil))
        }
        // Idle keeps the capsule's height, so a cancelled dictation does not resize a panel still on screen.
        if controller.phase == .idle { return NSSize(width: width, height: capsuleHeight) }
        return outcomeSize(measuredHeight: outcomeHeight, visible: visible)
    }

    static func isCapsule(_ phase: DictationController.Phase) -> Bool {
        switch phase {
        case .preparing, .listening, .delivering, .failed: true
        case .idle, .verified, .dispatched, .noSpeech, .recovery: false
        }
    }

    static func isCard(_ phase: DictationController.Phase) -> Bool {
        switch phase {
        case .recovery, .noSpeech: true
        default: false
        }
    }

    /// A microphone notice hangs under the capsule, so the capsule itself never grows.
    static func capsuleHeight(showsNotice: Bool = false) -> CGFloat {
        capsuleHeight + (showsNotice ? noticeSpacing + noticeHeight : 0)
    }

    /// An outcome is as tall as its content, on whole points, never shorter than
    /// the capsule and never larger than the screen. Unmeasured, it is the capsule.
    static func outcomeSize(measuredHeight: CGFloat?, visible: CGSize?) -> NSSize {
        let measured = measuredHeight.map { $0.isFinite ? $0.rounded(.up) : capsuleHeight } ?? capsuleHeight
        let height = max(capsuleHeight, measured)
        guard let visible, visible.width > 0, visible.height > 0 else { return NSSize(width: width, height: height) }
        return NSSize(
            width: min(width, visible.width.rounded(.down)), height: min(height, visible.height.rounded(.down)))
    }

    /// The words take the height they need up to a few lines.
    static func wordsHeight(forContent height: CGFloat) -> CGFloat {
        guard height.isFinite, height > 0 else { return 0 }
        return min(height.rounded(.up), wordsMaxHeight)
    }
}

/// Which outcome the panel shows, so a new one never inherits the last one's state or measured height.
struct DictationPanelOutcome: Equatable {
    enum Kind: Equatable { case result, notSent, noSpeech }

    let kind: Kind
    let delivery: UUID?

    init?(phase: DictationController.Phase, delivery: UUID?) {
        switch phase {
        case .verified, .dispatched: kind = .result
        case .recovery: kind = .notSent
        case .noSpeech: kind = .noSpeech
        case .idle, .preparing, .listening, .delivering, .failed: return nil
        }
        self.delivery = delivery
    }
}
