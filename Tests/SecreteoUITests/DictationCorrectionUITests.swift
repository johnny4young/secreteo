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
        for attempt in 0..<2 {
            XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
            dictate.click()
            XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
            dictate.click()
            if attempt == 0 {
                XCTAssertTrue(waitForQuietDelivery(app), "A plain dictation leaves no result")
            } else {
                XCTAssertTrue(status.waitForExistenceFast(timeout: 5), "A correction has something to offer")
            }
        }
        XCTAssertTrue(renderedText(of: status).contains("“notes” to “files”"))
        let learn = app.buttons["dictation-panel-learn-correction"]
        XCTAssertTrue(learn.waitForHittable(timeout: 4), "A new spelling is offered, never learned silently")
        XCTAssertTrue(renderedText(of: learn).contains("files"))
        XCTAssertEqual(app.dialogs["dictation-panel"].frame.height, 56, accuracy: 1, "The result is one pill, not a card")
        attachScreenshot(named: "pr-panel-result")
        learn.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: status).contains("From now on, “notes” is written “files”.")
        })
        XCTAssertFalse(learn.exists)
    }

}
