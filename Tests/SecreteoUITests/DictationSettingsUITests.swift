import XCTest

@MainActor
final class DictationSettingsUITests: SecreteoUITestCase {
    private func launch(_ arguments: String...) throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += arguments
        app.launchSecreteo()
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
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
        XCTAssertTrue(app.buttons["menu-bar-set-up-dictation"].exists, "Off, the menu offers setup, not a dead Dictate")
        XCTAssertFalse(app.buttons["menu-bar-dictate"].exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-failed-to-start").exists)
        attachScreenshot(named: "pr-settings-dictation")

        app.control(withIdentifier: "settings-dictation-enabled").click()

        let enabled = app.control(withIdentifier: "settings-dictation-enabled")
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { enabled.value as? Int == 1 || enabled.value as? String == "1" })
        XCTAssertTrue(app.buttons["menu-bar-dictate"].waitForExistence(timeout: 5), "Only the owner offers Dictate")
        XCTAssertFalse(app.buttons["menu-bar-set-up-dictation"].exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-handoff-failed").exists)
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

    func testAnOlderPortavozGetsOneInstructionAndNoDictate() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments.append("-seed-dictation-legacy-peer")
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        XCTAssertFalse(app.buttons["menu-bar-dictate"].exists)

        app.buttons["menu-settings"].click()

        let message = app.control(withIdentifier: "settings-dictation-unavailable")
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(renderedText(of: message).contains("Portavoz"))
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-reset").exists, "Only a corrupt file resets")
    }

    func testACorruptOwnershipFileCanBeResetAndDictationTakenAgain() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments.append("-seed-dictation-corrupt-ownership")
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        XCTAssertFalse(app.buttons["menu-bar-dictate"].exists)

        app.buttons["menu-settings"].click()

        let reset = app.control(withIdentifier: "settings-dictation-reset")
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-unavailable").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-take-ownership").exists)

        reset.click()

        let take = app.control(withIdentifier: "settings-dictation-take-ownership")
        XCTAssertTrue(take.waitForExistence(timeout: 5), "A reset leaves no owner, so the user chooses again")
        XCTAssertFalse(reset.exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-unavailable").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-reset-failed").exists)

        take.click()

        XCTAssertTrue(app.buttons["menu-bar-dictate"].waitForExistence(timeout: 5))
    }

    func testAllPermissionsGrantedOfferNoActions() throws {
        let app = try launch()
        defer { finishUITestApplication(app) }

        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-microphone").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-accessibility").exists)
    }
}
