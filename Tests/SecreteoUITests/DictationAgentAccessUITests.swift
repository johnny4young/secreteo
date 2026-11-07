import XCTest

/// The consent lives in the disposable launch's scratch database.
@MainActor
final class DictationAgentAccessUITests: SecreteoUITestCase {
    func testAgentAccessStartsOffAndEndsWithTheHistory() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        app.buttons["menu-settings"].click()
        let root = app.control(withIdentifier: "settings-root")
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        root.scroll(byDeltaX: 0, deltaY: -1_800)

        let history = app.control(withIdentifier: "settings-dictation-history")
        XCTAssertTrue(history.waitForStableFrame(timeout: 5))
        XCTAssertFalse(
            app.control(withIdentifier: "settings-dictation-history-agents").exists, "hidden while history is off")
        history.click()
        let agents = app.control(withIdentifier: "settings-dictation-history-agents")
        XCTAssertTrue(agents.waitForExistence(timeout: 5))
        root.scroll(byDeltaX: 0, deltaY: -1_800)
        XCTAssertFalse(isOn(agents))

        agents.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { self.isOn(agents) })
        attachScreenshot(named: "pr-settings-dictation-agent-access")

        history.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !agents.exists })
        history.click()
        let again = app.control(withIdentifier: "settings-dictation-history-agents")
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertFalse(isOn(again), "turning history back on does not share it again")
    }

    private func isOn(_ element: XCUIElement) -> Bool {
        element.value as? Int == 1 || element.value as? String == "1"
    }
}
