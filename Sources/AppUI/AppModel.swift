import AppKit
import Observation

/// What the menu and Settings show, and the actions behind them.
@MainActor
@Observable
public final class AppModel {
    public private(set) var launchAtLogin: Bool
    /// Shown next to the toggle, because a silent revert would look like a broken control.
    public private(set) var launchAtLoginFailed = false

    public let versionDescription: String
    public var openSettings: () -> Void = {}

    private let launchController: any LaunchAtLoginControlling

    public init(launchController: any LaunchAtLoginControlling, bundle: Bundle = .main) {
        self.launchController = launchController
        self.launchAtLogin = launchController.isEnabled
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        self.versionDescription = "\(version) (\(build))"
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

    public func quit() {
        NSApp.terminate(nil)
    }
}
