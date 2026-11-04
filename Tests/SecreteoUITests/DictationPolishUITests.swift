import XCTest

/// Polish runs a deterministic fixture rewrite; no engine, model or network is involved.
final class DictationPolishUITests: SecreteoUITestCase {

    @MainActor
    func testAPolishedDictationCanStillBePastedWithoutPolish() throws {
        let app = try launchPolishing()
        defer { finishUITestApplication(app) }
        deliver(app)
        XCTAssertFalse(app.staticTexts["dictation-panel-polish-notice"].exists)
        XCTAssertTrue(app.buttons["menu-bar-paste-unpolished"].waitForExistenceFast(timeout: 5))
        XCTAssertTrue(app.buttons["menu-bar-paste-last"].exists)
    }

    @MainActor
    func testPolishingCanBeSkippedToPasteTheCleanText() throws {
        let app = try launchPolishing("-seed-dictation-polish-held")
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        dictate.click()
        let skip = app.buttons["dictation-panel-skip-polish"]
        XCTAssertTrue(skip.waitForHittable(timeout: 4))
        XCTAssertTrue(app.staticTexts["dictation-panel-polish-hint"].exists)
        XCTAssertTrue(renderedText(of: app.staticTexts["dictation-panel-state"]).contains("Polishing"))
        skip.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-delivery-status"].waitForExistenceFast(timeout: 5))
        XCTAssertTrue(app.staticTexts["dictation-panel-polish-notice"].waitForExistenceFast(timeout: 5))
        XCTAssertFalse(app.buttons["menu-bar-paste-unpolished"].exists)
    }

    @MainActor
    func testARewriteThatChangesTheMeaningPastesCleanAndSaysWhy() throws {
        for verified in [true, false] {
            let app = try launchPolishing(verified: verified, "-seed-dictation-polish-unfaithful")
            defer { finishUITestApplication(app) }
            deliver(app)
            XCTAssertTrue(app.staticTexts["dictation-panel-polish-notice"].waitForExistenceFast(timeout: 5),
                          "The reason must show on the \(verified ? "verified" : "unverified") delivery too")
            XCTAssertFalse(app.buttons["menu-bar-paste-unpolished"].exists)
        }
    }

    @MainActor
    func testARecipeShapesTheDictationAndKeepsItsFacts() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-verified",
                                "-seed-dictation-english"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationTextMode":"polish","dictationPolishRecipe":"builtin.bullets"}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let mode = app.control(withIdentifier: "dictation-panel-text-mode")
        XCTAssertTrue(mode.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: mode).contains("Bullet list"))
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-delivery-status"].waitForExistenceFast(timeout: 5))
        XCTAssertFalse(app.staticTexts["dictation-panel-polish-notice"].exists)
        XCTAssertTrue(app.buttons["menu-bar-paste-unpolished"].waitForExistenceFast(timeout: 5))
    }

    @MainActor
    private func launchPolishing(verified: Bool = true, _ arguments: String...) throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-english"]
            + (verified ? ["-seed-dictation-verified"] : []) + arguments
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationTextMode":"polish"}"#
        app.launchSecreteo()
        return app
    }

    @MainActor
    private func deliver(_ app: XCUIApplication) {
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-delivery-status"].waitForExistenceFast(timeout: 5))
    }
}
