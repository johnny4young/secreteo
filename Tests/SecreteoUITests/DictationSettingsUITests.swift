import XCTest

@MainActor
final class DictationSettingsUITests: SecreteoUITestCase {
    private func launch(_ arguments: String...) throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += arguments
        app.launchSecreteo()
        app.buttons["menu-settings"].click()
        XCTAssertTrue(app.control(withIdentifier: "settings-root").waitForExistence(timeout: 5))
        return app
    }

    func testTurningDictationOnMakesThisAppTheOwner() throws {
        let app = try launch()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-shortcut").exists)
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: "settings-dictation-shortcut")).contains("⌃⌥⌘D"))
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-model-download").exists)
        attachScreenshot(named: "pr-settings-dictation")

        app.control(withIdentifier: "settings-dictation-enabled").click()

        let enabled = app.control(withIdentifier: "settings-dictation-enabled")
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { enabled.value as? Int == 1 || enabled.value as? String == "1" })
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-handoff-failed").waitForExistence(timeout: 1))
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-take-ownership").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-shortcut-unavailable").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-model-progress").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-model-failed").exists)
    }

    func testMissingPermissionsOfferTheirOwnActions() throws {
        let app = try launch("-seed-dictation-permissions-missing")
        defer { finishUITestApplication(app) }

        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-microphone").waitForExistence(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-accessibility").exists)
    }

    func testAllPermissionsGrantedOfferNoActions() throws {
        let app = try launch()
        defer { finishUITestApplication(app) }

        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-microphone").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-accessibility").exists)
    }
}
