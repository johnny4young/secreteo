import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Synchronization
import XCTest

@testable import DictationSession

final class ModifierKeyGestureTests: XCTestCase {
    func testHoldingAloneStartsAfterTheDelayAndReleaseDelivers() async {
        var gesture = ModifierKeyGesture()
        XCTAssertEqual(gesture.handle(.down), .scheduleStart)
        XCTAssertEqual(gesture.handle(.delayElapsed), .press)
        XCTAssertEqual(gesture.handle(.up), .release)
        XCTAssertEqual(gesture.handle(.down), .scheduleStart, "the next hold starts fresh")
    }

    func testShortcutsTypedWithTheKeyNeverDictate() async {
        var shortcut = ModifierKeyGesture()
        _ = shortcut.handle(.down)
        XCTAssertNil(shortcut.handle(.otherKey), "Fn+arrow before the delay opens nothing")
        XCTAssertNil(shortcut.handle(.delayElapsed), "a late timer cannot start it")
        XCTAssertNil(shortcut.handle(.up))

        var quickTap = ModifierKeyGesture()
        _ = quickTap.handle(.down)
        XCTAssertNil(quickTap.handle(.up))
        XCTAssertNil(quickTap.handle(.delayElapsed))

        var heldChord = ModifierKeyGesture()
        _ = heldChord.handle(.down)
        _ = heldChord.handle(.delayElapsed)
        XCTAssertEqual(heldChord.handle(.otherKey), .chord, "a shortcut after dictation began discards it")
        XCTAssertNil(heldChord.handle(.up), "its release must not deliver")
    }

    func testAnotherHeldModifierMeansAShortcutAndRightKeysStayApart() async throws {
        XCTAssertTrue(ModifierKeySetting.function.holdsOtherModifier(
            CGEventFlags([.maskSecondaryFn, .maskCommand]).rawValue))
        XCTAssertFalse(ModifierKeySetting.function.holdsOtherModifier(CGEventFlags.maskSecondaryFn.rawValue))
        XCTAssertFalse(ModifierKeySetting.rightOption.holdsOtherModifier(
            CGEventFlags.maskAlternate.rawValue | ModifierKeySetting.rightOption.flag))
        XCTAssertNotEqual(ModifierKeySetting.rightOption.flag, 0)
        XCTAssertNotEqual(ModifierKeySetting.rightOption.keyCode, ModifierKeySetting.rightCommand.keyCode)

        let suite = "modifier-key-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ModifierKeySetting.load(from: defaults), .function, "Holding Fn works out of the box")
        defaults.set("capsLock", forKey: ModifierKeySetting.defaultsKey)
        XCTAssertEqual(ModifierKeySetting.load(from: defaults), .function)
        defaults.set("off", forKey: ModifierKeySetting.defaultsKey)
        XCTAssertEqual(ModifierKeySetting.load(from: defaults), .off, "A key turned off stays off")
        defaults.set("rightOption", forKey: ModifierKeySetting.defaultsKey)
        XCTAssertEqual(ModifierKeySetting.load(from: defaults), .rightOption)
    }

    func testOnlyDoNothingLeavesTheGlobeKeyFree() {
        XCTAssertTrue(ModifierKeySetting.systemFnKeyIsFree(usage: 0))
        for usage in [nil, 1, 2, 3] {
            XCTAssertFalse(ModifierKeySetting.systemFnKeyIsFree(usage: usage), "\(String(describing: usage))")
        }
    }

    func testTappedEventsMapToTheGestureForOnlyTheChosenKey() async {
        func input(_ type: CGEventType, _ keyCode: Int, _ flags: CGEventFlags, _ setting: ModifierKeySetting = .function)
            -> ModifierKeyGesture.Input {
            ModifierKeyGesture.input(for: type, keyCode: Int64(keyCode), flags: flags.rawValue, setting: setting)
        }
        XCTAssertEqual(input(.flagsChanged, kVK_Function, .maskSecondaryFn), .down)
        XCTAssertEqual(input(.flagsChanged, kVK_Function, []), .up)
        XCTAssertEqual(input(.flagsChanged, kVK_Function, [.maskSecondaryFn, .maskShift]), .otherKey,
                       "Fn pressed while Shift is held is a shortcut")
        XCTAssertEqual(input(.keyDown, kVK_RightArrow, .maskSecondaryFn), .otherKey)
        XCTAssertEqual(input(.flagsChanged, kVK_Shift, .maskShift), .otherKey)
        let rightOption = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | ModifierKeySetting.rightOption.flag)
        XCTAssertEqual(input(.flagsChanged, kVK_RightOption, rightOption, .rightOption), .down)
        XCTAssertEqual(input(.flagsChanged, kVK_Option, .maskAlternate, .rightOption), .otherKey,
                       "the left Option key is not the trigger")
        XCTAssertEqual(input(.flagsChanged, kVK_RightOption, .maskAlternate, .rightOption), .up,
                       "left Option still held while the right one is released ends the hold")
    }

    func testTapRouterFastPathHoldChordDisableAndInvalidate() async {
        let events = Mutex<[String]>([])
        let delivery = DispatchQueue(label: "test.modifier-ptt-delivery")
        let router = ModifierKeyTapRouter(
            setting: .function,
            startDelay: .milliseconds(25),
            deliveryQueue: delivery,
            onPress: { events.withLock { $0.append("press") } },
            onRelease: { events.withLock { $0.append("release") } },
            onChord: { events.withLock { $0.append("chord") } })
        let fnFlag = CGEventFlags.maskSecondaryFn.rawValue

        // Unrelated typing while idle exits on the fast path with no callbacks.
        XCTAssertFalse(router.handleEvent(type: .keyDown, keyCode: Int64(kVK_ANSI_A), flags: 0))
        XCTAssertFalse(router.handleEvent(
            type: .flagsChanged, keyCode: Int64(kVK_Shift), flags: CGEventFlags.maskShift.rawValue))
        delivery.sync {}
        XCTAssertEqual(events.withLock { $0 }, [])

        // Quick release before delay and chord during pending both cancel the start.
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: fnFlag))
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: 0))
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: fnFlag))
        XCTAssertFalse(router.handleEvent(type: .keyDown, keyCode: Int64(kVK_RightArrow), flags: fnFlag))
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: 0))
        try? await Task.sleep(for: .milliseconds(50))
        delivery.sync {}
        XCTAssertEqual(events.withLock { $0 }, [], "quick taps and pending chords must never fire")

        // Holding Fn past the delay fires press, and releasing fires release in FIFO order.
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: fnFlag))
        let pressed = await TestPolling.until { events.withLock { $0 } == ["press"] }
        XCTAssertTrue(pressed)
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: 0))
        delivery.sync {}
        XCTAssertEqual(events.withLock { $0 }, ["press", "release"])

        // Typing another key while held fires chord and ignores the trailing release.
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: fnFlag))
        let heldForChord = await TestPolling.until { events.withLock { $0.count == 3 } }
        XCTAssertTrue(heldForChord)
        XCTAssertFalse(router.handleEvent(type: .keyDown, keyCode: Int64(kVK_RightArrow), flags: fnFlag))
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: 0))
        delivery.sync {}
        XCTAssertEqual(events.withLock { $0 }, ["press", "release", "press", "chord"])

        // Tap disable ends an active hold and requests re-enablement.
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: fnFlag))
        let pressedAgain = await TestPolling.until { events.withLock { $0.count == 5 } }
        XCTAssertTrue(pressedAgain)
        XCTAssertTrue(router.handleEvent(type: .tapDisabledByTimeout, keyCode: 0, flags: 0))
        delivery.sync {}
        XCTAssertEqual(events.withLock { $0 }, ["press", "release", "press", "chord", "press", "release"])

        // Invalidating cancels a pending start timer and suppresses future events.
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: fnFlag))
        router.invalidate()
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(router.handleEvent(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: 0))
        delivery.sync {}
        XCTAssertEqual(events.withLock { $0 }, ["press", "release", "press", "chord", "press", "release"])
    }
}
