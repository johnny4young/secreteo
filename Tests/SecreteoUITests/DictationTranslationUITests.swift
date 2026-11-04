import XCTest

/// Translation runs a deterministic fixture; no Apple language pack is read or downloaded.
final class DictationTranslationUITests: SecreteoUITestCase {
    @MainActor
    func testATranslatedDictationCanStillBePastedInTheOriginal() throws {
        let app = try launchTranslating()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let target = app.control(withIdentifier: "dictation-panel-translate")
        XCTAssertTrue(target.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: target).contains("EN"))
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-delivery-status"].waitForExistenceFast(timeout: 5))
        XCTAssertFalse(app.staticTexts["dictation-panel-polish-notice"].exists)
        XCTAssertTrue(app.buttons["menu-bar-paste-original"].waitForExistenceFast(timeout: 5))
        XCTAssertFalse(app.buttons["menu-bar-paste-unpolished"].exists)
    }

    @MainActor
    func testMissingLanguagesPasteTheOriginalAndSaySo() throws {
        let app = try launchTranslating("-seed-dictation-translate-missing")
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-delivery-status"].waitForExistenceFast(timeout: 5))
        let notice = app.staticTexts["dictation-panel-polish-notice"]
        XCTAssertTrue(notice.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: notice).contains("Settings"))
        XCTAssertFalse(app.buttons["menu-bar-paste-original"].exists)
    }

    @MainActor
    func testTranslatingCanBeSkippedToPasteTheOriginal() throws {
        let app = try launchTranslating("-seed-dictation-translate-held")
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        dictate.click()
        let skip = app.buttons["dictation-panel-skip-translation"]
        XCTAssertTrue(skip.waitForHittable(timeout: 4))
        XCTAssertTrue(app.staticTexts["dictation-panel-translate-hint"].exists)
        XCTAssertTrue(renderedText(of: app.staticTexts["dictation-panel-state"]).contains("Translating"))
        skip.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-delivery-status"].waitForExistenceFast(timeout: 5))
        XCTAssertTrue(app.staticTexts["dictation-panel-polish-notice"].waitForExistenceFast(timeout: 5))
        XCTAssertFalse(app.buttons["menu-bar-paste-original"].exists)
    }

    @MainActor
    private func launchTranslating(_ arguments: String...) throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-verified"]
            + arguments
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationTextMode":"clean","dictationTranslationTarget":"en","dictationLanguage":"es"}"#
        app.launchSecreteo()
        return app
    }
}
