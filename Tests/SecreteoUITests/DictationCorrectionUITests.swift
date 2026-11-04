import XCTest

/// The fixture receiver verifies every paste in memory, so the second dictation can correct the first.
final class DictationCorrectionUITests: SecreteoUITestCase {
    @MainActor
    func testASpokenCorrectionChangesTheLastDictationInsteadOfPasting() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-english", "-seed-dictation-delivery",
                                "-seed-dictation-verified", "-seed-dictation-correction"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationCorrectionCommands":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        let status = app.staticTexts["dictation-panel-delivery-status"]
        for _ in 0..<2 {
            XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
            dictate.click()
            XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
            dictate.click()
            XCTAssertTrue(status.waitForExistenceFast(timeout: 5))
            if renderedText(of: status).contains("Changed") { break }
            XCTAssertTrue(status.waitForDisappearance(timeout: 5))
        }
        XCTAssertTrue(renderedText(of: status).contains("“notes” to “files”"))
        let learn = app.buttons["dictation-panel-learn-correction"]
        XCTAssertTrue(learn.waitForHittable(timeout: 4), "A new spelling is offered, never learned silently")
        XCTAssertTrue(renderedText(of: learn).contains("files"))
        learn.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: status).contains("From now on, “notes” is written “files”.")
        })
        XCTAssertFalse(learn.exists)
    }

}
