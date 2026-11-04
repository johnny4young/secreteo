import AppKit
import DictationSession
import SwiftUI

/// Launch options. `-use-temp-store` keeps a test away from real state: no real launch
/// at login, no move offer, and an instance lock of its own. Debug only, so a shipped
/// binary cannot be started as a second instance beside the real one.
struct RuntimeOptions {
    let usesTemporaryStore: Bool
    let showsMenuContentWindow: Bool
    let failsLaunchAtLogin: Bool
    let reportsAvailableUpdate: Bool

    init(arguments: [String], allowsTestFlags: Bool = RuntimeOptions.isDebugBuild) {
        usesTemporaryStore = allowsTestFlags && arguments.contains("-use-temp-store")
        showsMenuContentWindow = usesTemporaryStore && arguments.contains("-show-menu-content")
        failsLaunchAtLogin = usesTemporaryStore && arguments.contains("-fail-launch-at-login")
        reportsAvailableUpdate = usesTemporaryStore && arguments.contains("-report-available-update")
    }

    #if DEBUG
        static let isDebugBuild = true
    #else
        static let isDebugBuild = false
    #endif
}

/// For test runs, which must never reach the network.
@MainActor
private final class InertUpdater: UpdateChecking {
    let canCheckForUpdates = true
    func checkForUpdates() {}
}

/// The composition root. It stays resident after its windows close, and it arms nothing
/// global until it holds the single-instance lock.
@MainActor
public final class SecreteoAppDelegate: NSObject, NSApplicationDelegate {
    private let options = RuntimeOptions(arguments: CommandLine.arguments)
    private let makeUpdater: @MainActor (AppModel) -> any UpdateChecking
    private var instanceLock: SingleInstanceLock?
    private var model: AppModel?
    private var statusItem: StatusItemController?
    private var settings: SettingsWindowController?
    private var watchdog: AffordanceWatchdog?
    private var menuContentWindow: NSWindow?

    private var activationNotification: Notification.Name {
        Notification.Name("\(Bundle.main.bundleIdentifier ?? "secreteo").activate")
    }

    /// The app target supplies the updater, which keeps Sparkle out of the libraries.
    public init(makeUpdater: @escaping @MainActor (AppModel) -> any UpdateChecking) {
        self.makeUpdater = makeUpdater
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(options.usesTemporaryStore ? .regular : .accessory)
        // Hidden in an agent app, but standard shortcuts still route through it.
        NSApp.mainMenu = StandardMenu.make()
        guard takeInstanceLock() else { return }

        #if !DEBUG
            if !options.usesTemporaryStore,
               ApplicationMover.offerIfNeeded(releaseInstanceLock: { instanceLock?.release() }) {
                NSApp.terminate(nil)
                return
            }
        #endif

        ProcessInfo.processInfo.disableAutomaticTermination("Secreteo stays resident in the menu bar")
        compose()
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        model?.dictation?.applicationDidBecomeActive()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The way back when the icon is hidden: opening the app again shows Settings.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return false
    }

    private func takeInstanceLock() -> Bool {
        let identifier = Bundle.main.bundleIdentifier ?? "secreteo"
        let directory = options.usesTemporaryStore
            ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            : URL.applicationSupportDirectory.appendingPathComponent(identifier, isDirectory: true)
        switch try? SingleInstanceLock.acquire(at: directory.appendingPathComponent("instance.lock")) {
        case .acquired(let lock):
            instanceLock = lock
            return true
        case .alreadyRunning:
            // A hint with no content: the worst a forged one can do is open Settings.
            DistributedNotificationCenter.default().postNotificationName(
                activationNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return false
        case nil:
            let alert = NSAlert()
            alert.messageText = String(localized: "Secreteo could not start.")
            alert.informativeText = String(localized: "It could not write to its folder in Application Support.")
            NSApp.activate()
            alert.runModal()
            NSApp.terminate(nil)
            return false
        }
    }

    private func compose() {
        let controller: any LaunchAtLoginControlling = options.usesTemporaryStore
            ? InMemoryLaunchAtLogin(failure: options.failsLaunchAtLogin ? CocoaError(.featureUnsupported) : nil)
            : SystemLaunchAtLogin()
        let model = AppModel(launchController: controller)
        model.updater = options.usesTemporaryStore ? InertUpdater() : makeUpdater(model)
        model.updateIsAvailable = options.reportsAvailableUpdate
        if DictationFeature.mayRunInThisBuild,
           let dictation = try? DictationFeature(usesTemporaryStore: options.usesTemporaryStore) {
            model.dictation = dictation
            dictation.start()
        }
        let settings = SettingsWindowController(model: model)
        let statusItem = StatusItemController(model: model)
        model.openSettings = { [weak settings, weak statusItem] in
            statusItem?.closeMenu()
            settings?.show()
        }
        self.model = model
        self.settings = settings
        self.statusItem = statusItem

        DistributedNotificationCenter.default().addObserver(
            forName: activationNotification, object: nil, queue: .main
        ) { [weak settings] _ in
            MainActor.assumeIsolated { settings?.show() }
        }

        if options.showsMenuContentWindow {
            showMenuContentWindow(model: model)
            return
        }
        statusItem.attach()
        let watchdog = AffordanceWatchdog(
            hasAffordance: { [weak statusItem] in statusItem?.hasVisibleAffordance == true },
            onLost: { NSApp.terminate(nil) })
        watchdog.start()
        self.watchdog = watchdog
    }

    private func showMenuContentWindow(model: AppModel) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: MenuContentView(model: model)))
        window.title = "Menu"
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        menuContentWindow = window
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
}
