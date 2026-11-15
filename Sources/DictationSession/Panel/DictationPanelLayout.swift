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

    /// `outcomeHeight` is what the outcome's SwiftUI content last measured; `visible` is the screen's usable size.
    @MainActor
    static func size(
        for controller: DictationController, outcomeHeight: CGFloat? = nil, visible: CGSize? = nil
    ) -> NSSize {
        if DictationCompactIndicator.applies(to: controller) { return DictationCompactIndicator.size }
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
        case .recovery, .dispatched, .noSpeech: true
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
