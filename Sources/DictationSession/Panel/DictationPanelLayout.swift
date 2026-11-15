import AppKit

/// One height authority for AppKit and SwiftUI: a conflicting intrinsic size
/// otherwise moves the panel again after every explicit re-show.
enum DictationPanelLayout {
    static let width: CGFloat = 520
    static let capsuleHeight: CGFloat = 56
    static let noticeHeight: CGFloat = 22
    static let noticeSpacing: CGFloat = 4

    @MainActor
    static func size(for controller: DictationController) -> NSSize {
        DictationCompactIndicator.applies(to: controller)
            ? DictationCompactIndicator.windowSize(for: .current())
            : NSSize(
                width: width,
                height: height(for: controller.phase, showsNotice: controller.microphoneNotice != nil))
    }

    static func isCapsule(_ phase: DictationController.Phase) -> Bool {
        switch phase {
        case .preparing, .listening, .delivering, .failed: true
        case .idle, .verified, .dispatched, .noSpeech, .recovery: false
        }
    }

    /// A microphone notice hangs under the capsule, so the capsule itself never grows.
    static func height(for phase: DictationController.Phase, showsNotice: Bool = false) -> CGFloat {
        switch phase {
        case .recovery, .dispatched, .noSpeech: 288
        case .verified: 96
        // Idle keeps the capsule's height, so a cancelled dictation does not resize a panel still on screen.
        case .idle: capsuleHeight
        case .preparing, .listening, .delivering, .failed:
            capsuleHeight + (showsNotice ? noticeSpacing + noticeHeight : 0)
        }
    }
}
