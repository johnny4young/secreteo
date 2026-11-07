import AppKit
import DictationSession
import Observation

/// The update mechanism, behind a seam so tests never reach the network.
@MainActor
public protocol UpdateChecking: AnyObject {
    /// False when this build has no update key, so the controls stay hidden.
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

/// What the menu and Settings show, and the actions behind them.
@MainActor
@Observable
public final class AppModel {
    public private(set) var launchAtLogin: Bool
    /// Shown next to the toggle, because a silent revert would look like a broken control.
    public private(set) var launchAtLoginFailed = false

    /// Set instead of interrupting: an update must never cut into a dictation.
    public var updateIsAvailable = false
    public var updater: (any UpdateChecking)?
    /// Nil in a build that may not run global dictation yet.
    public var dictation: DictationFeature?
    public var dictationFailedToStart = false

    public let versionDescription: String
    public var openSettings: () -> Void = {}
    public var openHistory: () -> Void = {}

    private let launchController: any LaunchAtLoginControlling

    public init(launchController: any LaunchAtLoginControlling, bundle: Bundle = .main) {
        self.launchController = launchController
        self.launchAtLogin = launchController.isEnabled
        self.versionDescription = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchController.setEnabled(enabled)
            launchAtLoginFailed = false
        } catch {
            launchAtLoginFailed = true
        }
        launchAtLogin = launchController.isEnabled
    }

    public func openNotices(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md") else { return }
        NSWorkspace.shared.open(url)
    }

    public var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates == true
    }

    public func checkForUpdates() {
        updater?.checkForUpdates()
    }

    public func quit() {
        NSApp.terminate(nil)
    }
}
