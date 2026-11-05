import Carbon.HIToolbox
import Foundation
import XCTest

@testable import DictationSession

@MainActor
final class DictationShortcutTests: XCTestCase {
    func testFailedRegistrationRecoversOnlyWhenRetriedAndCannotDispatch() async {
        let defaults = preferences()
        let shortcut = DictationShortcut()
        let host = RegistrationHost()
        host.failNext = true
        var presses = 0
        var releases = 0
        shortcut.sync(defaults: defaults, registrar: host.register,
                      onPress: { presses += 1 }, onRelease: { releases += 1 })
        XCTAssertEqual(shortcut.availability, .unavailable)
        host.callbacks[0].0()
        host.callbacks[0].1()
        XCTAssertEqual(presses, 0)
        XCTAssertEqual(releases, 0)
        XCTAssertEqual(host.settings.count, 1)

        shortcut.sync(defaults: defaults, registrar: host.register,
                      onPress: { presses += 1 }, onRelease: { releases += 1 })
        XCTAssertEqual(shortcut.availability, .registered)
        host.callbacks[0].0()
        XCTAssertEqual(presses, 0, "a delayed callback from the failed attempt cannot start capture")
        host.callbacks[1].0()
        host.callbacks[1].1()
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 1)
    }

    func testPausingFreesTheCombinationAndTheNextSyncTakesItBack() async {
        let defaults = preferences()
        let shortcut = DictationShortcut()
        let host = RegistrationHost()
        var presses = 0
        shortcut.sync(defaults: defaults, registrar: host.register, onPress: { presses += 1 }, onRelease: {})

        shortcut.pause()

        host.callbacks[0].0()
        XCTAssertEqual(presses, 0, "A press during recording must not start a dictation")
        XCTAssertEqual(shortcut.availability, .registered, "Listening is not a conflict")

        shortcut.sync(defaults: defaults, registrar: host.register, onPress: { presses += 1 }, onRelease: {})
        host.callbacks[1].0()
        XCTAssertEqual(presses, 1)
    }

    func testRebindAndDisableReleaseExactHandlesAndRejectOldCallbacks() async {
        let defaults = preferences()
        let shortcut = DictationShortcut()
        let host = RegistrationHost()
        var presses = 0
        shortcut.sync(defaults: defaults, registrar: host.register, onPress: { presses += 1 }, onRelease: {})
        defaults.setVolatileDomain([
            DictationController.defaultsKey: true,
            HotkeySetting.keyCodeKey: Int(kVK_ANSI_M),
            HotkeySetting.modifiersKey: Int(cmdKey | optionKey),
            HotkeySetting.labelKey: "⌥⌘M",
        ], forName: UserDefaults.argumentDomain)
        shortcut.sync(defaults: defaults, registrar: host.register, onPress: { presses += 1 }, onRelease: {})
        XCTAssertEqual(host.handles[0].unregistrations, 1)
        XCTAssertEqual(shortcut.setting.label, "⌥⌘M")
        host.callbacks[0].0()
        host.callbacks[1].0()
        XCTAssertEqual(presses, 1)

        defaults.setVolatileDomain([DictationController.defaultsKey: false], forName: UserDefaults.argumentDomain)
        for _ in 0..<2 {
            shortcut.sync(defaults: defaults, registrar: host.register, onPress: { presses += 1 }, onRelease: {})
        }
        XCTAssertEqual(shortcut.availability, .disabled)
        XCTAssertEqual(host.handles[1].unregistrations, 1)
        XCTAssertEqual(host.settings.count, 2)
        host.callbacks[1].0()
        XCTAssertEqual(presses, 1)
    }

    func testCorruptPreferencesReachRegistrarAsSafeDefaults() async {
        let defaults = preferences()
        defaults.setVolatileDomain([
            DictationController.defaultsKey: true, HotkeySetting.keyCodeKey: -1,
        ], forName: UserDefaults.argumentDomain)
        let shortcut = DictationShortcut()
        let host = RegistrationHost()
        shortcut.sync(defaults: defaults, registrar: host.register, onPress: {}, onRelease: {})
        XCTAssertTrue(shortcut.usedFallback)
        XCTAssertEqual(host.settings, [.default])
    }

    private func preferences() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "shortcut-tests-\(UUID().uuidString)")!
        defaults.setVolatileDomain([DictationController.defaultsKey: true], forName: UserDefaults.argumentDomain)
        return defaults
    }
}

@MainActor
private final class RegistrationHost {
    var failNext = false
    var settings: [HotkeySetting] = []
    var handles: [RegistrationHandle] = []
    var callbacks: [(() -> Void, () -> Void)] = []

    func register(_ setting: HotkeySetting, press: @escaping () -> Void, release: @escaping () -> Void)
        -> (any GlobalHotkeyRegistration)? {
        settings.append(setting)
        callbacks.append((press, release))
        if failNext {
            failNext = false
            return nil
        }
        let handle = RegistrationHandle()
        handles.append(handle)
        return handle
    }
}

@MainActor
private final class RegistrationHandle: GlobalHotkeyRegistration {
    var unregistrations = 0
    func unregister() { unregistrations += 1 }
}
