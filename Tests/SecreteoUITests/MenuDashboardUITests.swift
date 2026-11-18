import XCTest

@MainActor
final class MenuDashboardUITests: SecreteoUITestCase {
    func testTheMenuShowsTheStateTodayAndTheLastDictation() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += [
            "-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-english", "-seed-dictation-verified",
            "-seed-dictation-stats"
        ]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationTextMode":"polish","dictationPasteLastHotkey":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }

        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 30))
        XCTAssertTrue(app.control(withIdentifier: "menu-state").exists)
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: "menu-state-title")).contains("Ready"))
        XCTAssertTrue(
            renderedText(of: app.control(withIdentifier: "menu-state-detail")).contains("Secreteo owns dictation"))
        XCTAssertTrue(renderedText(of: dictate).contains("⌃⌥⌘D"), "The key cap is the real shortcut")
        XCTAssertTrue(app.buttons["menu-bar-fn-key-settings"].exists, "Fn is held by default and macOS also reacts")

        XCTAssertTrue(app.control(withIdentifier: "menu-today").waitForExistence(timeout: 5))
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: "menu-today-words")).contains("162"))
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: "menu-today-detail")).contains("2 dictations"))
        XCTAssertFalse(app.control(withIdentifier: "menu-last-dictation").exists, "Nothing dictated yet")

        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        dictate.click()
        XCTAssertTrue(waitForQuietDelivery(app), "A delivered dictation leaves no panel behind")

        XCTAssertTrue(app.control(withIdentifier: "menu-last-dictation").waitForExistence(timeout: 5))
        XCTAssertFalse(renderedText(of: app.control(withIdentifier: "menu-last-dictation-text")).isEmpty)
        XCTAssertTrue(app.buttons["menu-bar-paste-last"].exists)
        XCTAssertTrue(app.buttons["menu-bar-paste-unpolished"].exists)
        XCTAssertTrue(app.buttons["menu-settings"].isHittable, "The window grew with the card")
        attachScreenshot(named: "pr-menu-dashboard")
    }

    func testTheSetupButtonRunsTheMissingStep() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchSecreteo()
        defer { finishUITestApplication(app) }

        let setUp = app.buttons["menu-bar-set-up-dictation"]
        XCTAssertTrue(setUp.waitForStableFrame(timeout: 30))
        XCTAssertTrue(renderedText(of: setUp).contains("Turn On Dictation"))

        setUp.click()

        XCTAssertTrue(app.buttons["menu-bar-dictate"].waitForExistence(timeout: 5), "On, nothing else is missing here")
        XCTAssertFalse(setUp.exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-root").exists, "The step ran without opening Settings")
    }

    func testAFreeFnKeyLeavesTheMenuWithoutTheKeyboardLink() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-verified", "-seed-fn-key-free"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }

        XCTAssertTrue(app.buttons["menu-bar-dictate"].waitForStableFrame(timeout: 30))
        XCTAssertFalse(app.buttons["menu-bar-fn-key-settings"].exists)
    }
}
