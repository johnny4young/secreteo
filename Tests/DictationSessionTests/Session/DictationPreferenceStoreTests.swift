import DictationKit
import Foundation
import Observation
import XCTest

@testable import DictationSession

@MainActor
final class DictationPreferenceStoreTests: XCTestCase {
    private func makeDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = "DictationPreferenceStoreTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    private func makeFeature(_ defaults: UserDefaults) throws -> DictationFeature {
        try DictationFeature(usesTemporaryStore: true, arguments: [], defaults: defaults)
    }

    func testADisposableLaunchNeverWritesAPreferenceFile() throws {
        let (defaults, name) = try makeDefaults()

        DictationFeature.store(["key": "value"], in: defaults, temporary: true)

        XCTAssertEqual(defaults.string(forKey: "key"), "value")
        XCTAssertNil(defaults.persistentDomain(forName: name)?["key"])
    }

    func testARealEditPersistsAndSupersedesAStartupOverride() throws {
        let (defaults, name) = try makeDefaults()
        defaults.setVolatileDomain(["key": "startup", "other": "kept"], forName: UserDefaults.argumentDomain)

        DictationFeature.store(["key": "edited"], in: defaults, temporary: false)

        XCTAssertEqual(defaults.string(forKey: "key"), "edited")
        XCTAssertEqual(defaults.persistentDomain(forName: name)?["key"] as? String, "edited")
        XCTAssertEqual(defaults.string(forKey: "other"), "kept", "Only the edited key loses its override")
    }

    func testABindingReadsItsDefaultThenWhatWasStored() throws {
        let (defaults, _) = try makeDefaults()
        let feature = try makeFeature(defaults)
        let binding = feature.preference("key", default: "fallback")
        XCTAssertEqual(binding.wrappedValue, "fallback")

        binding.wrappedValue = "chosen"

        XCTAssertEqual(binding.wrappedValue, "chosen")
    }

    func testAMalformedStoredValueReadsAsTheDefault() throws {
        let (defaults, _) = try makeDefaults()
        let feature = try makeFeature(defaults)
        DictationFeature.store(["key": "text"], in: defaults, temporary: true)

        XCTAssertEqual(feature.preference("key", default: 2.0).wrappedValue, 2.0)
    }

    func testRecordingAShortcutIsWhatTheNextLoadReads() throws {
        let (defaults, _) = try makeDefaults()
        let feature = try makeFeature(defaults)
        let setting = HotkeySetting(keyCode: 38, modifiers: HotkeySetting.default.modifiers, label: "⌃⌥⌘J")

        feature.recordShortcut(setting)

        XCTAssertEqual(HotkeySetting.load(from: defaults), setting)
    }

    func testAnIneligibleMouseButtonIsStoredAsOff() throws {
        let (defaults, _) = try makeDefaults()
        let feature = try makeFeature(defaults)
        feature.recordMouseButton(3)
        XCTAssertEqual(feature.mouseButton, 3)

        feature.recordMouseButton(1)

        XCTAssertEqual(feature.mouseButton, MouseButtonSetting.off)
    }

    func testAWriteFromElsewhereRedrawsSettings() async throws {
        let (defaults, _) = try makeDefaults()
        let feature = try makeFeature(defaults)
        let redrawn = expectation(description: "The value's readers are told")
        withObservationTracking {
            _ = feature.preference("key", default: "").wrappedValue
        } onChange: {
            redrawn.fulfill()
        }

        defaults.set("learned", forKey: "key")

        await fulfillment(of: [redrawn], timeout: 5)
    }

    func testChoosingCleanIsWhatADictationReads() throws {
        let (defaults, _) = try makeDefaults()
        let feature = try makeFeature(defaults)
        XCTAssertEqual(feature.textSettings.globalMode, .literal)

        feature.textSettings.setGlobalChoice(DictationTextChoice(mode: .clean))

        XCTAssertEqual(DictationTextPreferences.snapshot(in: defaults, bundleIdentifier: nil).mode, .clean)
    }
}
