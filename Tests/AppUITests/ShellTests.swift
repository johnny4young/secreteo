import AppKit
@testable import AppUI
import Foundation
import Testing

struct SingleInstanceLockTests {
    private func lockFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("secreteo-lock-\(UUID().uuidString)/instance.lock")
    }

    @Test func aSecondInstanceIsRefusedUntilTheFirstEnds() throws {
        let url = lockFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        guard case .acquired(let first) = try SingleInstanceLock.acquire(at: url) else {
            Issue.record("The first instance must acquire")
            return
        }
        guard case .alreadyRunning = try SingleInstanceLock.acquire(at: url) else {
            Issue.record("A second instance must be refused")
            return
        }
        first.release()
        guard case .acquired = try SingleInstanceLock.acquire(at: url) else {
            Issue.record("A released lock must be free again")
            return
        }
    }
}

@MainActor
struct VersionRowTests {
    @Test func theRowShowsOnlyTheVersionBecauseTheBuildNumberRepeatsIt() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("secreteo-version-\(UUID().uuidString).bundle")
        let contents = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        let info = ["CFBundleIdentifier": "test.version", "CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "1.2.3"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: bundleURL))
        #expect(AppModel(launchController: InMemoryLaunchAtLogin(), bundle: bundle).versionDescription == "1.2.3")
    }
}

struct ApplicationLocationTests {
    private let home = URL(fileURLWithPath: "/Volumes/Home/someone")

    @Test(arguments: ["/Applications/Secreteo.app", "/Volumes/Home/someone/Applications/Secreteo.app"])
    func installedLocationsAreLeftAlone(path: String) {
        #expect(!ApplicationLocation.shouldOfferMove(bundleURL: URL(fileURLWithPath: path), homeDirectory: home))
    }

    @Test(arguments: [
        "/Volumes/Home/someone/Downloads/Secreteo.app",
        "/Volumes/Secreteo/Secreteo.app",
        "/private/var/folders/x/AppTranslocation/y/d/Secreteo.app",
        "/ApplicationsOther/Secreteo.app"
    ])
    func otherLocationsGetTheOffer(path: String) {
        #expect(ApplicationLocation.shouldOfferMove(bundleURL: URL(fileURLWithPath: path), homeDirectory: home))
    }
}

@MainActor
struct AffordanceWatchdogTests {
    private final class Flag {
        var value = true
        var lost = 0
    }

    @Test func losingTheIconIsReportedOnce() {
        let flag = Flag()
        let watchdog = AffordanceWatchdog(hasAffordance: { flag.value }, onLost: { flag.lost += 1 })
        watchdog.tick()
        #expect(flag.lost == 0)
        flag.value = false
        for _ in 0..<6 { watchdog.tick() }
        #expect(flag.lost == 1)
    }

    @Test func aMomentaryLossIsNotReported() {
        let flag = Flag()
        let watchdog = AffordanceWatchdog(hasAffordance: { flag.value }, onLost: { flag.lost += 1 })
        for _ in 0..<4 {
            flag.value = false
            watchdog.tick()
            watchdog.tick()
            flag.value = true
            watchdog.tick()
        }
        #expect(flag.lost == 0)
    }

    @Test func anEventPutsItOnTheFastScheduleForAFewChecks() {
        let flag = Flag()
        let watchdog = AffordanceWatchdog(hasAffordance: { flag.value }, onLost: {}, idleInterval: 10, checkInterval: 1)
        #expect(watchdog.nextInterval == 10)
        watchdog.checkSoon()
        for _ in 0..<3 {
            #expect(watchdog.nextInterval == 1)
            watchdog.tick()
        }
        #expect(watchdog.nextInterval == 10)
    }

    @Test func aMissStaysOnTheFastScheduleUntilTheIconReturns() {
        let flag = Flag()
        let watchdog = AffordanceWatchdog(hasAffordance: { flag.value }, onLost: {}, idleInterval: 10, checkInterval: 1)
        flag.value = false
        watchdog.tick()
        watchdog.tick()
        #expect(watchdog.nextInterval == 1)
        flag.value = true
        watchdog.tick()
        #expect(watchdog.nextInterval == 10)
    }

    @Test func aSilentLossIsReportedWithinOneIdleWaitAndTwoChecks() {
        let flag = Flag()
        let watchdog = AffordanceWatchdog(
            hasAffordance: { flag.value }, onLost: { flag.lost += 1 }, idleInterval: 10, checkInterval: 1)
        flag.value = false
        #expect(waitUntilReported(watchdog, flag) == 12)
        #expect(watchdog.nextInterval == nil)
    }

    @Test func anAnnouncedLossIsReportedOnTheSameScheduleAsAlwaysPolling() {
        let flag = Flag()
        let watchdog = AffordanceWatchdog(hasAffordance: { flag.value }, onLost: { flag.lost += 1 })
        flag.value = false
        watchdog.checkSoon()
        #expect(waitUntilReported(watchdog, flag) == 2.25)
    }

    @Test func aBurstOfEventsNeverBringsTheNextCheckCloser() throws {
        let flag = Flag()
        let watchdog = AffordanceWatchdog(hasAffordance: { flag.value }, onLost: {}, idleInterval: 1000, checkInterval: 500)
        watchdog.start()
        defer { watchdog.stop() }
        for _ in 0..<3 { watchdog.tick() }
        let idle = try #require(watchdog.nextCheck)
        #expect(idle.timeIntervalSinceNow > 900)
        watchdog.checkSoon()
        let fast = try #require(watchdog.nextCheck)
        #expect(fast.timeIntervalSinceNow < 600)
        for _ in 0..<5 { watchdog.checkSoon() }
        #expect(watchdog.nextCheck == fast)
    }

    @Test func theSentinelHearsTheButtonLeaveItsWindow() {
        let flag = Flag()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 20), styleMask: .borderless,
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let button = NSButton(frame: .zero)
        let sentinel = WindowSentinel { flag.lost += 1 }
        button.addSubview(sentinel)
        window.contentView?.addSubview(button)
        #expect(flag.lost == 1)
        button.removeFromSuperview()
        #expect(flag.lost == 2)
        #expect(sentinel.isHidden && !sentinel.isAccessibilityElement())
    }

    /// The scheduled waits from a loss to its report, which a real timer would sleep through.
    private func waitUntilReported(_ watchdog: AffordanceWatchdog, _ flag: Flag) -> TimeInterval {
        var waited: TimeInterval = 0
        while flag.lost == 0, let wait = watchdog.nextInterval {
            waited += wait
            watchdog.tick()
        }
        return waited
    }
}

@MainActor
struct AppModelTests {
    @Test func aFailedLaunchAtLoginChangeShowsTheFailureAndKeepsTheRealState() {
        let model = AppModel(launchController: InMemoryLaunchAtLogin(failure: CocoaError(.featureUnsupported)))
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == false)
        #expect(model.launchAtLoginFailed)
    }

    @Test func aSuccessfulChangeClearsAnEarlierFailure() {
        let model = AppModel(launchController: InMemoryLaunchAtLogin())
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin)
        #expect(model.launchAtLoginFailed == false)
    }
}

@MainActor
struct UpdateTests {
    private final class Recording: UpdateChecking {
        var canCheckForUpdates = true
        var checks = 0
        func checkForUpdates() { checks += 1 }
    }

    @Test func noUpdaterMeansNoControls() {
        let model = AppModel(launchController: InMemoryLaunchAtLogin())
        #expect(model.canCheckForUpdates == false)
        model.checkForUpdates()
    }

    @Test func aBuildWithoutAKeyHidesTheControls() {
        let model = AppModel(launchController: InMemoryLaunchAtLogin())
        let updater = Recording()
        updater.canCheckForUpdates = false
        model.updater = updater
        #expect(model.canCheckForUpdates == false)
    }

    @Test func checkingGoesToTheUpdater() {
        let model = AppModel(launchController: InMemoryLaunchAtLogin())
        let updater = Recording()
        model.updater = updater
        model.checkForUpdates()
        #expect(updater.checks == 1)
    }
}

struct RuntimeOptionsTests {
    @Test func aMenuFocusTargetNeedsTheMenuWindowAndATestBuild() {
        let flags = ["-use-temp-store", "-show-menu-content", "-return-menu-focus-to", "com.example.app"]
        #expect(RuntimeOptions(arguments: flags, allowsTestFlags: true).menuFocusTarget == "com.example.app")
        #expect(RuntimeOptions(arguments: flags, allowsTestFlags: false).menuFocusTarget == nil)
        #expect(RuntimeOptions(arguments: Array(flags.dropLast()), allowsTestFlags: true).menuFocusTarget == nil)
        let noWindow = ["-use-temp-store", "-return-menu-focus-to", "com.example.app"]
        #expect(RuntimeOptions(arguments: noWindow, allowsTestFlags: true).menuFocusTarget == nil)
    }

    @Test func testFlagsRequireTheTemporaryStore() {
        let bare = RuntimeOptions(arguments: ["-show-menu-content", "-fail-launch-at-login"], allowsTestFlags: true)
        #expect(!bare.usesTemporaryStore && !bare.showsMenuContentWindow && !bare.failsLaunchAtLogin)
        let test = RuntimeOptions(arguments: ["-use-temp-store", "-show-menu-content"], allowsTestFlags: true)
        #expect(test.usesTemporaryStore && test.showsMenuContentWindow)
    }

    @Test func aReleaseBuildIgnoresTestFlags() {
        let flags = ["-use-temp-store", "-show-menu-content", "-report-available-update"]
        let release = RuntimeOptions(arguments: flags, allowsTestFlags: false)
        #expect(!release.usesTemporaryStore && !release.showsMenuContentWindow && !release.reportsAvailableUpdate)
    }
}
