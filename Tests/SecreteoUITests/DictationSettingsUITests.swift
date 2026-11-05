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

    private func launchEnabled(defaults: String = "") throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        let extra = defaults.isEmpty ? "" : ",\(defaults)"
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = "{\"globalDictationEnabled\":true\(extra)}"
        app.launchSecreteo()
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        app.buttons["menu-settings"].click()
        XCTAssertTrue(app.control(withIdentifier: "settings-root").waitForExistence(timeout: 5))
        return app
    }

    /// Synthesized input is global, so it must never reach another app.
    private func requireForeground(_ app: XCUIApplication) throws {
        guard app.state == .runningForeground else { throw XCTSkip("The app is not in front") }
    }

    func testTurningDictationOnMakesThisAppTheOwner() throws {
        let app = try launch()
        defer { finishUITestApplication(app) }
        let recorder = app.control(withIdentifier: "settings-dictation-hotkey-recorder")
        XCTAssertTrue(recorder.exists)
        XCTAssertTrue(renderedText(of: recorder).contains("⌃⌥⌘D"))
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-shortcut-default").exists, "Only a changed one")
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-shortcut-recovered").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-shortcut-retry").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-sounds").exists, "Off, only the toggle shows")
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

        for identifier in [
            "settings-dictation-mouse-recorder", "settings-dictation-modifier-key", "settings-dictation-sounds",
            "settings-dictation-compact", "settings-dictation-speech-gate", "settings-dictation-auto-stop",
            "settings-dictation-corrections", "settings-dictation-caret-case", "settings-dictation-language",
            "settings-dictation-microphone-device", "settings-dictation-text-mode", "settings-dictation-filler",
            "settings-dictation-dict-trigger", "settings-dictation-dict-replacement", "settings-dictation-dict-add"
        ] {
            XCTAssertTrue(app.control(withIdentifier: identifier).waitForExistence(timeout: 5), identifier)
        }
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-mouse-clear").exists, "No button is set")
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-auto-stop-pause").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-modifier-unavailable").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-modifier-fn-note").exists)
        attachScreenshot(named: "pr-settings-dictation-controls")
    }

    func testChoosingAShortcutShowsItAndOffersTheDefaultBack() throws {
        let app = try launchEnabled()
        defer { finishUITestApplication(app) }
        let recorder = app.control(withIdentifier: "settings-dictation-hotkey-recorder")
        try requireForeground(app)

        recorder.click()
        app.typeKey("j", modifierFlags: [.control, .option, .command])

        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: recorder).contains("⌃⌥⌘J") })
        let useDefault = app.control(withIdentifier: "settings-dictation-shortcut-default")
        XCTAssertTrue(useDefault.waitForExistence(timeout: 5))

        useDefault.click()

        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: recorder).contains("⌃⌥⌘D") })
    }

    func testPauseLengthAndTheFnNoteAppearWithTheirChoices() throws {
        let app = try launchEnabled(defaults: #""dictationModifierKey":"function","dictationAutoStop":true"#)
        defer { finishUITestApplication(app) }

        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-auto-stop-pause").waitForExistence(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-modifier-fn-note").exists)
    }

    func testAMouseButtonCanBeCleared() throws {
        let app = try launchEnabled(defaults: #""dictationMouseButton":3"#)
        defer { finishUITestApplication(app) }
        let clear = app.control(withIdentifier: "settings-dictation-mouse-clear")
        XCTAssertTrue(clear.waitForExistence(timeout: 5))

        clear.click()

        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !clear.exists })
    }

    func testAReplacementCanBeAddedAndRemovedInCleanMode() throws {
        let app = try launchEnabled(defaults: #""dictationTextMode":"clean""#)
        defer { finishUITestApplication(app) }
        try requireForeground(app)
        let trigger = app.control(withIdentifier: "settings-dictation-dict-trigger")
        XCTAssertTrue(trigger.waitForExistence(timeout: 5))

        trigger.click()
        trigger.typeText("portabos")
        let replacement = app.control(withIdentifier: "settings-dictation-dict-replacement")
        replacement.click()
        replacement.typeText("Portavoz")
        app.control(withIdentifier: "settings-dictation-dict-add").click()

        let remove = app.control(withIdentifier: "settings-dictation-dict-remove")
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-dict-add-heard").exists)

        remove.click()

        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !remove.exists })
    }

    func testAMalformedShortcutIsRecovered() throws {
        let app = try launchEnabled(defaults: #""dictationHotkeyKeyCode":-1"#)
        defer { finishUITestApplication(app) }

        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-shortcut-recovered").waitForExistence(timeout: 5))
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
