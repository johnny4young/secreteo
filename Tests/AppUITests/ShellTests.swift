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
        var first: SingleInstanceLock?
        guard case .acquired(let lock) = try SingleInstanceLock.acquire(at: url) else {
            Issue.record("The first instance must acquire")
            return
        }
        first = lock
        guard case .alreadyRunning = try SingleInstanceLock.acquire(at: url) else {
            Issue.record("A second instance must be refused")
            return
        }
        withExtendedLifetime(first) {}
        first = nil
        _ = first
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
        watchdog.tick()
        watchdog.tick()
        #expect(flag.lost == 1)
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

struct RuntimeOptionsTests {
    @Test func testFlagsRequireTheTemporaryStore() {
        let bare = RuntimeOptions(arguments: ["-show-menu-content", "-fail-launch-at-login"])
        #expect(!bare.usesTemporaryStore && !bare.showsMenuContentWindow && !bare.failsLaunchAtLogin)
        let test = RuntimeOptions(arguments: ["-use-temp-store", "-show-menu-content"])
        #expect(test.usesTemporaryStore && test.showsMenuContentWindow)
    }
}
