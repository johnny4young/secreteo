import AppKit
import AppUI
import OSLog
@preconcurrency import Sparkle

/// Sparkle with gentle reminders: a background app gets a menu row instead of an alert
/// that could land in the middle of a dictation. Without a public key in the build,
/// as in local and fork builds, it stays off and the controls stay hidden.
@MainActor
final class SparkleUpdater: NSObject, UpdateChecking,
    @preconcurrency SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    nonisolated private static let logger = Logger(subsystem: "com.johnny4young.secreteo", category: "updates")
    private weak var model: AppModel?
    private var controller: SPUStandardUpdaterController?

    init(model: AppModel) {
        self.model = model
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        #if SECRETEO_UPDATE_DRYRUN
            model.dictation?.holdLeaseForUpdateDryRun()
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    var canCheckForUpdates: Bool {
        controller != nil
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        let postponed = model?.dictation?.postponeUpdateRelaunch {
            Self.logger.notice("Resuming the postponed update relaunch")
            installHandler()
        } ?? false
        if postponed { Self.logger.notice("Postponed the update relaunch until dictation finishes") }
        return postponed
    }

    #if SECRETEO_UPDATE_DRYRUN
        // A shipped build installs an automatic update on quit, a path that never asks the hook above.
        func updater(
            _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
            immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
        ) -> Bool {
            immediateInstallHandler()
            return true
        }
    #endif

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        model?.dictation?.finishUpdateCycle()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        model?.dictation?.finishUpdateCycle()
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
