import XCTest

/// Polish runs a deterministic fixture rewrite; no engine, model or network is involved.
final class DictationPolishUITests: SecreteoUITestCase {

    @MainActor
    func testPolishIsOfferedInSettingsWithAnOllamaModel() throws {
        let app = try launchSettings(
            #""dictationTextMode":"polish","dictationPolishEngine":"ollama""#, arguments: ["-seed-ollama-models"])
        defer { finishUITestApplication(app) }
        let mode = app.control(withIdentifier: "settings-dictation-text-mode")
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(renderedText(of: mode).contains("Polish"))
        let engine = app.control(withIdentifier: "settings-dictation-polish-engine")
        let model = app.control(withIdentifier: "settings-dictation-polish-ollama-model")
        XCTAssertTrue(reveal(model, in: app))
        XCTAssertTrue(renderedText(of: engine).contains("Ollama"))
        XCTAssertTrue(renderedText(of: model).contains("None"))
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-polish-ollama-missing").exists)

        model.click()
        let qwen = app.menuItems["qwen3:8b"]
        XCTAssertTrue(qwen.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(app.menuItems["llama3.2:3b"].exists)
        qwen.click()

        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: model).contains("qwen3:8b") })
        // Polish is the last section, so the evidence shows it whole at the bottom.
        app.control(withIdentifier: "settings-root").scroll(byDeltaX: 0, deltaY: -2_000)
        attachScreenshot(named: "pr-settings-polish-ollama")
    }

    @MainActor
    func testOllamaThatDoesNotAnswerCanBeCheckedAgain() throws {
        let app = try launchSettings(#""dictationPolishEngine":"ollama""#)
        defer { finishUITestApplication(app) }
        let missing = app.control(withIdentifier: "settings-dictation-polish-ollama-missing")
        XCTAssertTrue(reveal(missing, in: app))
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-polish-ollama-retry").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-polish-ollama-model").exists)
    }

    @MainActor
    func testOllamaWithNoModelsSaysSo() throws {
        let app = try launchSettings(#""dictationPolishEngine":"ollama""#, arguments: ["-seed-ollama-empty"])
        defer { finishUITestApplication(app) }
        let empty = app.control(withIdentifier: "settings-dictation-polish-ollama-empty")
        XCTAssertTrue(reveal(empty, in: app))
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-polish-ollama-retry").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-polish-ollama-model").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-polish-ollama-checking").exists)
    }

    @MainActor
    func testAppleIntelligenceThatCannotRunSaysWhyAndOllamaCanBeChosen() throws {
        let app = try launchSettings(
            #""dictationPolishEngine":"appleOnDevice""#, arguments: ["-simulate-no-apple-intelligence"])
        defer { finishUITestApplication(app) }
        let unavailable = app.control(withIdentifier: "settings-dictation-polish-unavailable")
        XCTAssertTrue(reveal(unavailable, in: app))
        XCTAssertTrue(renderedText(of: unavailable).contains("Apple Intelligence is turned off"))
        // Polish is the last section, so the evidence shows it whole at the bottom.
        app.control(withIdentifier: "settings-root").scroll(byDeltaX: 0, deltaY: -2_000)
        attachScreenshot(named: "pr-settings-polish-apple-unavailable")
        let engine = app.control(withIdentifier: "settings-dictation-polish-engine")

        engine.click()
        let ollama = app.menuItems["Ollama"]
        XCTAssertTrue(ollama.waitForExistenceFast(timeout: 5))
        ollama.click()

        XCTAssertTrue(unavailable.waitForDisappearance(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-polish-ollama-missing").waitForExistence(timeout: 5))
    }

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
    private func launchSettings(_ defaults: String, arguments: [String] = []) throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += arguments
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = "{\"globalDictationEnabled\":true,\(defaults)}"
        app.launchSecreteo()
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        app.buttons["menu-settings"].click()
        XCTAssertTrue(app.control(withIdentifier: "settings-root").waitForExistence(timeout: 5))
        return app
    }

    /// The form leaves rows below the fold out of the accessibility tree, and Polish is last.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard app.state == .runningForeground else { return false }
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            app.control(withIdentifier: "settings-root").scroll(byDeltaX: 0, deltaY: -400)
        }
        return element.waitForStableFrame(timeout: 5)
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
