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
    /// A disposable launch hides first-run setup unless a test asks for it.
    let forcesOnboarding: Bool
    /// The status item cannot be automated, so a test names the app a menu row gives focus to.
    let menuFocusTarget: String?

    init(arguments: [String], allowsTestFlags: Bool = RuntimeOptions.isDebugBuild) {
        usesTemporaryStore = allowsTestFlags && arguments.contains("-use-temp-store")
        showsMenuContentWindow = usesTemporaryStore && arguments.contains("-show-menu-content")
        failsLaunchAtLogin = usesTemporaryStore && arguments.contains("-fail-launch-at-login")
        reportsAvailableUpdate = usesTemporaryStore && arguments.contains("-report-available-update")
        forcesOnboarding = usesTemporaryStore && arguments.contains("-show-onboarding")
        let focusFlag = showsMenuContentWindow ? arguments.firstIndex(of: "-return-menu-focus-to") : nil
        menuFocusTarget = focusFlag.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
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
    private var history: HistoryWindowController?
    private var onboarding: OnboardingWindowController?
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
        if DictationFeature.mayRunInThisBuild {
            do {
                let dictation = try DictationFeature(usesTemporaryStore: options.usesTemporaryStore)
                model.dictation = dictation
                dictation.start()
            } catch {
                model.dictationFailedToStart = true
            }
        }
        if model.dictation == nil { DictationFeature.answerIntentsWithoutDictation() }
        let settings = SettingsWindowController(model: model)
        let statusItem = StatusItemController(model: model)
        model.openSettings = { [weak settings, weak statusItem] in
            statusItem?.closeMenu()
            settings?.show()
        }
        if let dictation = model.dictation {
            let history = HistoryWindowController(dictation: dictation)
            model.openHistory = { [weak history, weak statusItem] in
                statusItem?.closeMenu()
                history?.show()
            }
            dictation.installDictationNavigation { [weak history] in history?.show() }
            self.history = history
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
        } else {
            statusItem.attach()
            let watchdog = AffordanceWatchdog(
                hasAffordance: { [weak statusItem] in statusItem?.hasVisibleAffordance == true },
                onLost: { NSApp.terminate(nil) })
            statusItem.onAffordanceChange = { [weak watchdog] in watchdog?.checkSoon() }
            watchdog.start()
            self.watchdog = watchdog
        }
        showOnboardingIfNeeded(model: model)
    }

    /// A build without dictation has nothing to set up yet.
    private func showOnboardingIfNeeded(model: AppModel) {
        guard let dictation = model.dictation else { return }
        let record = FirstRunOnboardingRecord(defaults: .standard, isDisposable: options.usesTemporaryStore)
        let context = FirstRunOnboardingContext(
            forceRequested: options.forcesOnboarding,
            automationSuppressed: options.usesTemporaryStore,
            hasCompleted: record.hasCompleted)
        guard FirstRunOnboardingPolicy.decide(context) == .show else { return }
        let onboarding = OnboardingWindowController(dictation: dictation) { record.markCompleted() }
        onboarding.show()
        self.onboarding = onboarding
    }

    private func showMenuContentWindow(model: AppModel) {
        let content = options.menuFocusTarget.map { target in
            let focusReturn = MenuFocusReturn()
            return MenuContentView(model: model) { action in
                let running = NSRunningApplication.runningApplications(withBundleIdentifier: target).first
                focusReturn.aim(at: running?.processIdentifier)
                focusReturn.run(action)
            }
        } ?? MenuContentView(model: model)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
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
