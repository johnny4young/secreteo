import DictationKit
import Foundation
import XCTest

@testable import DictationSession

@MainActor
final class PortavozPreferenceImportTests: XCTestCase {
    private func scratchDefaults() throws -> UserDefaults {
        let name = "PortavozPreferenceImportTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    func testOnlyAllowedSettingsOfTheRightTypeAreOffered() throws {
        let portavoz: [String: Any] = [
            DictationController.languageKey: "es",
            DictationTextPreferences.modeKey: DictationTextMode.clean.rawValue,
            DictationSoundCue.defaultsKey: true,
            DictationController.defaultsKey: true,
            "dictationHotkeyKeyCode": 2,
            "dictationTranslationTarget": "en",
            "dictationLiveSpeechEngine": "parakeetUltra",
            "preferredInputUID": "usb-microphone",
            DictationCompactIndicator.defaultsKey: NSNumber(value: 1),
            DictationCorrections.defaultsKey: "yes",
            DictationAutoStop.pauseKey: 7.0,
        ]

        let found = PortavozPreferenceImport(portavoz: portavoz, current: try scratchDefaults())

        // Clean needs no write: the imported language makes Secreteo derive it, as Portavoz did.
        XCTAssertEqual(Set(found.values.keys), [DictationController.languageKey, DictationSoundCue.defaultsKey])
        XCTAssertEqual(Set(found.changes.map(\.key)), Set(found.values.keys))
    }

    func testAValueSecreteoAlreadyUsesIsNotAChange() throws {
        let defaults = try scratchDefaults()
        defaults.set("es", forKey: DictationController.languageKey)
        let portavoz: [String: Any] = [
            DictationController.languageKey: "es",
            DictationController.fillerFilterKey: true,
            DictationTextPreferences.modeKey: DictationTextMode.clean.rawValue,
        ]

        let found = PortavozPreferenceImport(portavoz: portavoz, current: defaults)

        XCTAssertEqual(found.changes, [], "Language matches, filler words default to on, and Secreteo already reads Clean")
    }

    func testAnUntouchedPortavozLeavesTheTextModeAlone() throws {
        let found = PortavozPreferenceImport(
            portavoz: [DictationSoundCue.defaultsKey: true], current: try scratchDefaults())

        XCTAssertNil(found.values[DictationTextPreferences.modeKey])
    }

    func testOlderPortavozSettingsImportTheCleanModeTheyShowed() throws {
        let found = PortavozPreferenceImport(
            portavoz: [DictationController.defaultsKey: true], current: try scratchDefaults())

        XCTAssertEqual(found.values[DictationTextPreferences.modeKey] as? String, DictationTextMode.clean.rawValue)
    }

    func testALiteralModeStaysLiteralWhenOlderKeysArrive() throws {
        let defaults = try scratchDefaults()
        let portavoz: [String: Any] = [
            DictationTextPreferences.modeKey: DictationTextMode.literal.rawValue,
            DictationController.languageKey: "es",
        ]
        let found = PortavozPreferenceImport(portavoz: portavoz, current: defaults)

        for (key, value) in found.values { defaults.set(value, forKey: key) }

        XCTAssertEqual(DictationTextPreferences.globalMode(in: defaults), .literal)
        XCTAssertEqual(PortavozPreferenceImport(portavoz: portavoz, current: defaults).changes, [])
    }

    func testImportingTwiceChangesNothingTheSecondTime() throws {
        let defaults = try scratchDefaults()
        // A disposable launch writes to the process-wide argument domain.
        addTeardownBlock { @MainActor in
            var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            for key in PortavozPreferenceImport.fixture.keys { domain.removeValue(forKey: key) }
            UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        }
        let feature = try DictationFeature(
            usesTemporaryStore: true, arguments: [], defaults: defaults,
            environment: .disposable(permissionsAreMissing: false, seedsPortavozPreferences: true))
        feature.refreshPortavozImport()
        let offered = try XCTUnwrap(feature.portavozImport).changes.count

        feature.importPortavozPreferences()

        XCTAssertEqual(offered, 3)
        XCTAssertNil(feature.portavozImport)
        XCTAssertEqual(defaults.string(forKey: DictationController.languageKey), "es")
        XCTAssertTrue(defaults.bool(forKey: DictationSoundCue.defaultsKey))
        XCTAssertNil(defaults.object(forKey: "dictationHotkeyKeyCode"))
        feature.refreshPortavozImport()
        XCTAssertNil(feature.portavozImport)
    }
}
