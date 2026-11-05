import AppKit
import XCTest

/// The practice field delivers a real dictation session into Secreteo itself,
/// so these journeys prove delivery without another app or the clipboard.
final class DictationPracticeUITests: SecreteoUITestCase {
    @MainActor
    func testSettingsPracticeFieldReceivesDictationWithoutTheClipboard() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        // The verified fixture's clock makes the session long enough to deliver at once.
        app.launchArguments += ["-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-verified"]
        if UITestLocale.environmentLocale == "en" { app.launchArguments.append("-seed-dictation-english") }
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        app.buttons["menu-settings"].click()

        let expected = UITestLocale.environmentLocale == "en" ? "Don't delete these notes." : "No borres estas notas."
        let start = app.buttons["settings-dictation-practice-start"]
        XCTAssertTrue(start.waitForStableFrame(timeout: 5))
        XCTAssertFalse(app.buttons["settings-dictation-practice-clear"].exists)
        let clipboard = NSPasteboard.general.changeCount
        start.click()
        let transcript = app.staticTexts["dictation-panel-transcript"]
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: transcript).contains(expected) })
        start.click()

        let field = app.control(withIdentifier: "settings-dictation-practice-field")
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: field) == expected })
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboard, "Practice never borrows the clipboard")
        attachScreenshot(named: "settings-dictation-practice")
        // The verified notice closes itself; nothing else is clicked while it is up.
        XCTAssertTrue(app.dialogs["dictation-panel"].waitForDisappearance(timeout: 5))
        app.buttons["settings-dictation-practice-clear"].click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: field) != expected })
        XCTAssertFalse(app.buttons["settings-dictation-practice-clear"].exists)

        start.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: transcript).contains(expected) })
        start.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: field) == expected })
        XCTAssertTrue(app.dialogs["dictation-panel"].waitForDisappearance(timeout: 5))
        app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !field.exists })
        app.buttons["menu-settings"].click()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertNotEqual(renderedText(of: field), expected, "Words are not kept once the field is gone")
    }
}
