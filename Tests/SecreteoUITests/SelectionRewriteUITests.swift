import XCTest

/// The fixture supplies a fixed selection and receiver; no Accessibility, clipboard or engine.
final class SelectionRewriteUITests: SecreteoUITestCase {
    @MainActor
    func testRewriteSelectionPreviewsBeforeReplacing() throws {
        let app = try launchRewrite()
        defer { finishUITestApplication(app) }
        openRewrite(app)
        XCTAssertTrue(app.staticTexts["rewrite-original"].waitForExistenceFast(timeout: 5))
        XCTAssertFalse(app.staticTexts["rewrite-notice"].exists)
        XCTAssertFalse(app.staticTexts["rewrite-instruction"].exists)
        app.buttons["rewrite-choice-polish"].click()
        let preview = app.staticTexts["rewrite-preview"]
        XCTAssertTrue(preview.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: preview).contains("Don't delete these notes!"))
        attachScreenshot(named: "pr-rewrite-preview")
        app.buttons["rewrite-choose-again"].click()
        XCTAssertTrue(app.buttons["rewrite-choice-polish"].waitForHittable(timeout: 5))
        XCTAssertFalse(preview.exists, "Nothing is replaced while choosing again")
        app.buttons["rewrite-choice-polish"].click()
        XCTAssertTrue(preview.waitForExistenceFast(timeout: 5))
        app.buttons["rewrite-replace"].click()
        let state = app.staticTexts["rewrite-state"]
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: state).contains("Rewrite test receiver") })
        XCTAssertFalse(app.buttons["rewrite-replace"].exists)
    }

    @MainActor
    func testARecipeRewriteIsNeverPastedOverAChangedSelection() throws {
        let app = try launchRewrite("-seed-rewrite-selection-changes")
        defer { finishUITestApplication(app) }
        openRewrite(app)
        let recipes = app.control(withIdentifier: "rewrite-recipes")
        XCTAssertTrue(recipes.waitForHittable(timeout: 5))
        recipes.click()
        let bullets = app.menuItems["rewrite-choice-builtin.bullets"]
        XCTAssertTrue(bullets.waitForExistenceFast(timeout: 5))
        bullets.click()
        let preview = app.staticTexts["rewrite-preview"]
        XCTAssertTrue(preview.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: preview).hasPrefix("- "))
        app.buttons["rewrite-replace"].click()
        XCTAssertTrue(app.buttons["rewrite-copy"].waitForExistenceFast(timeout: 5))
        XCTAssertFalse(app.buttons["rewrite-replace"].exists)
    }

    @MainActor
    func testRewritingWithoutASelectionExplainsWhatToDo() throws {
        let app = try launchRewrite("-seed-rewrite-nothing-selected")
        defer { finishUITestApplication(app) }
        openRewrite(app)
        let state = app.staticTexts["rewrite-state"]
        XCTAssertTrue(state.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: state).contains("Select some text") })
        XCTAssertFalse(app.buttons["rewrite-choice-polish"].exists)
        app.buttons["rewrite-cancel"].click()
        XCTAssertTrue(state.waitForDisappearance(timeout: 5))
    }

    @MainActor
    private func launchRewrite(_ arguments: String...) throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += arguments
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        return app
    }

    @MainActor
    private func openRewrite(_ app: XCUIApplication) {
        XCTAssertTrue(app.prepareForInteraction())
        let rewrite = app.buttons["menu-bar-rewrite-selection"]
        XCTAssertTrue(rewrite.waitForStableFrame(timeout: 5))
        rewrite.click()
    }
}

extension SelectionRewriteUITests {
    @MainActor
    func testSayingHowRewritesTheSelectionWithTheSpokenInstruction() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        // The delivery fixture's clock keeps Done from landing inside the 0.75 s minimum capture.
        app.launchArguments += ["-seed-dictation", "-seed-dictation-english", "-seed-dictation-delivery",
                                "-seed-dictation-verified"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.prepareForInteraction())
        let rewrite = app.buttons["menu-bar-rewrite-selection"]
        XCTAssertTrue(rewrite.waitForStableFrame(timeout: 5))
        rewrite.click()
        let sayHow = app.buttons["rewrite-say-how"]
        XCTAssertTrue(sayHow.waitForHittable(timeout: 5))
        sayHow.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        let done = app.buttons["rewrite-say-how-done"]
        XCTAssertTrue(done.waitForHittable(timeout: 5))
        done.click()
        let preview = app.staticTexts["rewrite-preview"]
        XCTAssertTrue(preview.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: preview).hasPrefix("- "))
        XCTAssertTrue(app.buttons["rewrite-replace"].exists)
        XCTAssertFalse(app.buttons["menu-bar-paste-last"].exists, "An instruction is not a dictation to paste again")
        app.buttons["rewrite-choose-again"].click()
        XCTAssertTrue(app.staticTexts["rewrite-instruction"].waitForExistenceFast(timeout: 5), "What was said stays shown")
    }
}
