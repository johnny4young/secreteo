import XCTest

/// The history lives in the disposable launch's scratch database, so turning it on or
/// deleting rows never touches a real one.
@MainActor
final class DictationHistoryUITests: SecreteoUITestCase {
    private func launchHistory(_ arguments: String...) throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += arguments
        app.launchSecreteo()
        let row = app.buttons["menu-bar-history"]
        XCTAssertTrue(row.waitForStableFrame(timeout: 30))
        row.click()
        XCTAssertTrue(app.control(withIdentifier: "dictation-history").waitForExistence(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "dictation-history-title").exists)
        return app
    }

    func testHistoryStartsOffAndTurnsOnFromItsWindow() throws {
        let app = try launchHistory()
        defer { finishUITestApplication(app) }

        let status = app.control(withIdentifier: "dictation-history-status")
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: status) == "History is off. New dictations are not saved."
        })
        XCTAssertFalse(app.control(withIdentifier: "dictation-history-delete-all").exists)
        app.buttons["dictation-history-enable"].click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: status) == "Kept on this Mac for 30 days." })
        XCTAssertTrue(app.control(withIdentifier: "dictation-history-empty").waitForExistence(timeout: 5))
        XCTAssertFalse(app.control(withIdentifier: "dictation-history-error").exists)
        attachScreenshot(named: "pr-dictation-history-empty")
    }

    func testSavedDictationsCanBeFilteredAndDeletedOneByOneOrAll() throws {
        let app = try launchHistory("-seed-dictation-history", "-seed-dictation-history-records")
        defer { finishUITestApplication(app) }

        let newest = app.control(withIdentifier: text(0))
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: newest) == "No borres estas notas." })
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: details(0))).contains("Notes"))
        XCTAssertTrue(app.control(withIdentifier: original(0)).exists)
        XCTAssertTrue(app.buttons[copy(0)].exists)
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: details(1))).contains("Not delivered"))
        XCTAssertFalse(app.control(withIdentifier: "dictation-history-more").exists, "Two rows fit one page")
        XCTAssertTrue(app.control(withIdentifier: "dictation-history-app-filter").exists)
        attachScreenshot(named: "pr-dictation-history-list")

        app.control(withIdentifier: "dictation-history-undelivered-filter").click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: newest) == "Send the report on Friday." })
        XCTAssertFalse(app.control(withIdentifier: text(1)).exists)
        app.buttons[delete(0)].click()
        XCTAssertTrue(app.control(withIdentifier: "dictation-history-no-results").waitForExistence(timeout: 5))
        app.control(withIdentifier: "dictation-history-undelivered-filter").click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: newest) == "No borres estas notas." })

        app.buttons["dictation-history-delete-all"].click()
        let confirm = app.buttons["dictation-history-delete-all-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.control(withIdentifier: "dictation-history-empty").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dictation-history-delete-all"].exists)
    }

    func testADictationSavedToHistorySaysSoInsteadOfNothingWasSaved() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += [
            "-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-verified", "-seed-dictation-history"
        ]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }

        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 30))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistence(timeout: 5))
        dictate.click()
        let detail = app.staticTexts["dictation-panel-delivery-detail"]
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: detail) == "Saved to your dictation history."
        })
    }

    func testSettingsAskForHistoryConsentWithEverySwitchOff() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        app.buttons["menu-settings"].click()
        let root = app.control(withIdentifier: "settings-root")
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        root.scroll(byDeltaX: 0, deltaY: -1_800)

        let toggle = app.control(withIdentifier: "settings-dictation-history")
        XCTAssertTrue(toggle.waitForStableFrame(timeout: 5))
        XCTAssertFalse(isOn(toggle))
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-history-retention").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-history-error").exists)
        toggle.click()
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-history-retention").waitForExistence(timeout: 5))
        XCTAssertFalse(isOn(app.control(withIdentifier: "settings-dictation-history-original")))
        root.scroll(byDeltaX: 0, deltaY: -1_800)
        attachScreenshot(named: "pr-settings-dictation-history")
    }

    private func isOn(_ element: XCUIElement) -> Bool {
        element.value as? Int == 1 || element.value as? String == "1"
    }

    private func text(_ index: Int) -> String { "dictation-history-text-\(index)" }
    private func original(_ index: Int) -> String { "dictation-history-original-\(index)" }
    private func details(_ index: Int) -> String { "dictation-history-details-\(index)" }
    private func copy(_ index: Int) -> String { "dictation-history-copy-\(index)" }
    private func delete(_ index: Int) -> String { "dictation-history-delete-\(index)" }
}
