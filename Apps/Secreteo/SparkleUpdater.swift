import AppKit
import AppUI
@preconcurrency import Sparkle

/// Sparkle with gentle reminders: a background app gets a menu row instead of an alert
/// that could land in the middle of a dictation. Without a public key in the build,
/// as in local and fork builds, it stays off and the controls stay hidden.
@MainActor
final class SparkleUpdater: NSObject, UpdateChecking, @preconcurrency SPUStandardUserDriverDelegate {
    private weak var model: AppModel?
    private var controller: SPUStandardUpdaterController?

    init(model: AppModel) {
        self.model = model
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var canCheckForUpdates: Bool {
        controller != nil
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate { model?.updateIsAvailable = true }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        model?.updateIsAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        model?.updateIsAvailable = false
    }
}
