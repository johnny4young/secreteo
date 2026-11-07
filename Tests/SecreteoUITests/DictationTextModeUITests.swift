import AppKit
import XCTest

final class DictationTextModeUITests: SecreteoUITestCase {
    @MainActor
    func testApplicationProfileUsesNativePickerAndKeepsTheOriginal() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments.append("-seed-dictation-profile-picker")
        app.launchEnvironment["TMPDIR"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("secreteo-profiles-\(UUID().uuidString)", isDirectory: true).path
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationTextMode":"literal","dictationApplicationTextProfiles":"[]"}"#
        let original = try makeApplication(in: app)
        let originalBytes = try Data(contentsOf: original)
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        try openSettings(app)
        let global = app.control(withIdentifier: "settings-dictation-text-mode")
        XCTAssertTrue(app.revealInSettings(global))
        try select(.clean, prefix: "settings-dictation-text-mode", in: app)
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: global).contains(cleanTitle) })
        try openProfiles(in: app)
        let add = app.buttons["settings-dictation-profile-add"]
        XCTAssertTrue(app.revealInSettings(add))
        XCTAssertFalse(app.staticTexts["settings-dictation-profile-error"].exists)
        add.click()
        let picker = app.sheets.firstMatch
        guard picker.waitForExistenceFast(timeout: 5) else {
            XCTFail("The real application chooser must appear")
            return
        }
        app.typeKey("2", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { picker.buttons["OKButton"].isEnabled })
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(picker.waitForDisappearance(timeout: 5))
        let prefix = "settings-dictation-profile-mode-com.johnny4young.secreteo.profile.fixture"
        let profile = app.control(withIdentifier: prefix)
        XCTAssertTrue(profile.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: profile).contains(cleanTitle), "A new profile starts with the chosen global mode")
        for rowPrefix in ["settings-dictation-profile-mode-", "settings-dictation-profile-translate-"] {
            let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", rowPrefix))
            XCTAssertEqual(rows.count, 1, "One profile, one row of each control")
        }
        attachScreenshot(named: "pr-settings-application-profile")
        try select(.literal, prefix: prefix, in: app)
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: profile).contains("Literal") })
        let translation = app.control(
            withIdentifier: "settings-dictation-profile-translate-com.johnny4young.secreteo.profile.fixture")
        XCTAssertTrue(renderedText(of: translation).contains("Default"), "A new profile follows the default translation")
        XCTAssertTrue(renderedText(of: global).contains(cleanTitle), "An application override must not rewrite the default")
        let remove = app.buttons["settings-dictation-profile-remove-com.johnny4young.secreteo.profile.fixture"]
        XCTAssertTrue(app.revealInSettings(remove))
        remove.click()
        XCTAssertTrue(profile.waitForDisappearance(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }

    @MainActor
    func testCorruptProfilesShowAnExplicitResetWithoutChangingTheDefault() throws {
        let app = try XCUIApplication.launchSettings(
            #""dictationTextMode":"literal","dictationApplicationTextProfiles":"not json""#)
        defer { finishUITestApplication(app) }
        try openProfiles(in: app)
        let warning = app.staticTexts["settings-dictation-profiles-invalid"]
        XCTAssertTrue(warning.waitForExistenceFast(timeout: 5))
        XCTAssertFalse(app.buttons["settings-dictation-profile-add"].exists)
        let reset = app.buttons["settings-dictation-profile-reset"]
        XCTAssertTrue(app.revealInSettings(reset))
        reset.click()
        XCTAssertTrue(warning.waitForDisappearance(timeout: 5))
        XCTAssertTrue(app.buttons["settings-dictation-profile-add"].waitForExistence(timeout: 5))
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: "settings-dictation-text-mode")).contains("Literal"))
        let disclosure = app.buttons["settings-dictation-profiles"]
        XCTAssertTrue(app.revealInSettings(disclosure))
        disclosure.click()
        XCTAssertTrue(app.buttons["settings-dictation-profile-add"].waitForDisappearance(timeout: 5))
        XCTAssertTrue(renderedText(of: disclosure).contains(
            UITestLocale.environmentLocale == "es" ? "Contraído" : "Collapsed"))
    }

    @MainActor
    func testSessionModeOverrideCancelsAndRestartsWithoutChangingDefaults() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments.append("-seed-dictation")
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationTextMode":"literal"}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForHittable(timeout: 5))
        dictate.click()
        let mode = app.control(withIdentifier: "dictation-panel-text-mode")
        XCTAssertTrue(mode.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: mode).contains("Literal"))
        try select(.clean, prefix: "dictation-panel-text-mode", in: app)
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: mode).contains(cleanTitle) })
        app.buttons["dictation-panel-cancel"].click()
        XCTAssertTrue(mode.waitForDisappearance(timeout: 5))
        XCTAssertTrue(app.prepareForInteraction())
        dictate.click()
        XCTAssertTrue(mode.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: mode).contains("Literal"), "A cancelled session must not retain its override")
        app.buttons["dictation-panel-cancel"].click()
        XCTAssertTrue(mode.waitForDisappearance(timeout: 5))
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) throws {
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        app.buttons["menu-settings"].click()
        XCTAssertTrue(app.control(withIdentifier: "settings-root").waitForExistence(timeout: 5))
    }

    @MainActor
    private func openProfiles(in app: XCUIApplication) throws {
        let disclosure = app.control(withIdentifier: "settings-dictation-profiles")
        XCTAssertTrue(app.revealInSettings(disclosure))
        disclosure.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: disclosure).contains(UITestLocale.environmentLocale == "es" ? "Expandido" : "Expanded")
        })
    }

    private enum Mode: String { case literal, clean }

    @MainActor
    private func select(_ mode: Mode, prefix: String, in app: XCUIApplication) throws {
        let picker = app.control(withIdentifier: prefix)
        if prefix.hasPrefix("settings-") { XCTAssertTrue(app.revealInSettings(picker)) }
        XCTAssertTrue(picker.waitForHittable(timeout: 5))
        picker.click()
        let option = app.menuItems[prefix + "-" + mode.rawValue]
        XCTAssertTrue(option.waitForExistenceFast(timeout: 5))
        option.click()
    }

    private var cleanTitle: String { UITestLocale.environmentLocale == "es" ? "Limpio" : "Clean" }

    @MainActor
    private func makeApplication(in app: XCUIApplication) throws -> URL {
        let root = URL(fileURLWithPath: try XCTUnwrap(app.launchEnvironment["TMPDIR"]), isDirectory: true)
        let directory = root.appendingPathComponent("dictation-profile-applications/Fixture.app/Contents")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plist = directory.appendingPathComponent("Info.plist")
        let values = ["CFBundleIdentifier": "com.johnny4young.secreteo.profile.fixture", "CFBundlePackageType": "APPL",
                      "CFBundleName": "Fixture", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: plist)
        return plist
    }
}
