import XCTest

@MainActor
final class MenuFocusUITests: SecreteoUITestCase {
    func testADictationFromTheMenuStartsWithFocusBackInThePreviousApp() throws {
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-return-menu-focus-to", "com.apple.finder"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 30))

        dictate.click()

        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5), "Words go to the app with focus")
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
    }
}
