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

    func testSearchAndFiltersNarrowTheHistory() throws {
        let app = try launchHistory("-seed-dictation-history", "-seed-dictation-history-records")
        defer { finishUITestApplication(app) }

        let first = app.control(withIdentifier: text(0))
        let second = app.control(withIdentifier: text(1))
        XCTAssertTrue(second.waitForExistence(timeout: 5))

        let search = app.control(withIdentifier: "dictation-history-search")
        search.click()
        search.typeText("repor")
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: first) == "Send the report on Friday." && !second.exists
        })
        search.typeText("tzz")
        XCTAssertTrue(app.control(withIdentifier: "dictation-history-no-results").waitForExistence(timeout: 5))
        attachScreenshot(named: "pr-dictation-history-search")
        app.buttons["dictation-history-search-clear"].click()
        XCTAssertTrue(second.waitForExistence(timeout: 5))

        app.control(withIdentifier: "dictation-history-app-filter").click()
        let notes = app.menuItems["Notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: first) == "No borres estas notas." && !second.exists
        })
        app.control(withIdentifier: "dictation-history-undelivered-filter").click()
        XCTAssertTrue(app.control(withIdentifier: "dictation-history-no-results").waitForExistence(timeout: 5))
    }

    func testADictationSavedToHistorySaysSoInsteadOfNothingWasSaved() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += [
            "-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-verified", "-seed-dictation-history"
        ]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }

        // History turns on in the background at launch; the window shows when it has.
        let history = app.buttons["menu-bar-history"]
        XCTAssertTrue(history.waitForStableFrame(timeout: 30))
        history.click()
        let status = app.control(withIdentifier: "dictation-history-status")
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: status) == "Kept on this Mac for 30 days." })
        // The history window covers the menu's window, so it closes before Dictate is clicked.
        app.windows["Dictation History"].buttons[XCUIIdentifierCloseWindow].click()
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
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

    func testStatisticsSummarizeTheWeekWithoutTheHistory() throws {
        let app = try launchHistory("-seed-dictation-stats")
        defer { finishUITestApplication(app) }

        XCTAssertTrue(app.control(withIdentifier: "dictation-stats").waitForExistence(timeout: 5))
        let dictations = app.control(withIdentifier: "dictation-stats-dictations")
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: dictations).contains("4") })
        for identifier in ["dictation-stats-words", "dictation-stats-speaking", "dictation-stats-saved"] {
            XCTAssertTrue(app.control(withIdentifier: identifier).exists, identifier)
        }
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: statsApp(0))).contains("Slack"))
        XCTAssertTrue(app.control(withIdentifier: "dictation-stats-not-delivered").exists)
        XCTAssertFalse(app.control(withIdentifier: "dictation-stats-empty").exists)
        XCTAssertTrue(app.control(withIdentifier: "dictation-history-enable").exists, "the history itself stays off")
        attachScreenshot(named: "pr-dictation-stats")

        XCTAssertTrue(app.control(withIdentifier: "dictation-stats-range").exists)
        app.radioButtons["30 days"].click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: dictations).contains("4") })
    }

    func testStatisticsStartOffAndTurnOnFromSettings() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        app.buttons["menu-settings"].click()
        let root = app.control(withIdentifier: "settings-root")
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        root.scroll(byDeltaX: 0, deltaY: -1_800)

        let toggle = app.control(withIdentifier: "settings-dictation-stats")
        XCTAssertTrue(toggle.waitForStableFrame(timeout: 5))
        XCTAssertFalse(isOn(toggle))
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-stats-error").exists)
        toggle.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { self.isOn(toggle) })
        app.buttons["settings-dictation-stats-delete"].click()
        let confirm = app.buttons["settings-dictation-stats-delete-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(confirm.waitForDisappearance(timeout: 5))
        XCTAssertTrue(isOn(toggle), "deleting the totals keeps counting on")
    }

    private func isOn(_ element: XCUIElement) -> Bool {
        element.value as? Int == 1 || element.value as? String == "1"
    }

    private func text(_ index: Int) -> String { "dictation-history-text-\(index)" }
    private func original(_ index: Int) -> String { "dictation-history-original-\(index)" }
    private func details(_ index: Int) -> String { "dictation-history-details-\(index)" }
    private func copy(_ index: Int) -> String { "dictation-history-copy-\(index)" }
    private func delete(_ index: Int) -> String { "dictation-history-delete-\(index)" }
    private func statsApp(_ index: Int) -> String { "dictation-stats-app-\(index)" }
}
