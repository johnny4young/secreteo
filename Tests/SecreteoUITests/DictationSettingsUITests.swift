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

    private func launchEnabled(defaults: String = "", arguments: [String] = []) throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += arguments
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
            "settings-dictation-practice-field", "settings-dictation-practice-start",
            "settings-dictation-mouse-recorder", "settings-dictation-modifier-key",
            "settings-dictation-paste-last-hotkey", "settings-dictation-rewrite-hotkey", "settings-dictation-sounds",
            "settings-dictation-compact", "settings-dictation-speech-gate", "settings-dictation-auto-stop",
            "settings-dictation-corrections", "settings-dictation-caret-case",
            "settings-model-memory-lightweight", "settings-dictation-prewarm", "settings-dictation-language",
            "settings-dictation-microphone-device", "settings-dictation-text-mode", "settings-dictation-filler",
            "settings-dictation-dict-trigger", "settings-dictation-dict-replacement", "settings-dictation-dict-add",
            "settings-dictation-vocabulary-field", "settings-dictation-vocabulary-add"
        ] {
            XCTAssertTrue(app.control(withIdentifier: identifier).waitForExistence(timeout: 5), identifier)
        }
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-mouse-clear").exists, "No button is set")
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-paste-last-taken").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-rewrite-taken").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-auto-stop-pause").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-modifier-unavailable").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-modifier-fn-note").exists)
        attachScreenshot(named: "pr-settings-dictation-controls")

        try requireForeground(app)
        app.control(withIdentifier: "settings-root").scroll(byDeltaX: 0, deltaY: -600)
        attachScreenshot(named: "pr-settings-dictation-controls-middle")
        app.control(withIdentifier: "settings-root").scroll(byDeltaX: 0, deltaY: -1_200)
        attachScreenshot(named: "pr-settings-dictation-controls-bottom")
    }

    func testOpeningSettingsWithEditableReplacementsStaysAtTheTop() throws {
        let app = try launchEnabled(defaults: #""dictationTextMode":"clean""#)
        defer { finishUITestApplication(app) }

        let enabled = app.control(withIdentifier: "settings-dictation-enabled")

        XCTAssertTrue(enabled.waitForStableFrame(timeout: 5), "No text field takes focus and scrolls the form")
    }

    func testTheRewriteShortcutTurnsOnWithoutAConflict() throws {
        let app = try launchEnabled()
        defer { finishUITestApplication(app) }
        let toggle = app.control(withIdentifier: "settings-dictation-rewrite-hotkey")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(toggle.value as? Int == 1 || toggle.value as? String == "1", "Off until chosen")

        toggle.click()

        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            toggle.value as? Int == 1 || toggle.value as? String == "1"
        })
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-rewrite-taken").exists)
    }

    func testThePasteLastShortcutTurnsOnWithoutAConflict() throws {
        let app = try launchEnabled()
        defer { finishUITestApplication(app) }
        let toggle = app.control(withIdentifier: "settings-dictation-paste-last-hotkey")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(toggle.value as? Int == 1 || toggle.value as? String == "1", "Off until chosen")

        toggle.click()

        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            toggle.value as? Int == 1 || toggle.value as? String == "1"
        })
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-paste-last-taken").exists)
    }

    func testPortavozSettingsArePreviewedAndImportedOnce() throws {
        let app = try launchEnabled(arguments: ["-seed-portavoz-preferences"])
        defer { finishUITestApplication(app) }
        let importRow = app.control(withIdentifier: "settings-portavoz-import")
        let confirm = app.control(withIdentifier: "settings-portavoz-import-confirm")
        XCTAssertTrue(importRow.waitForStableFrame(timeout: 5))

        importRow.click()

        XCTAssertTrue(confirm.waitForStableFrame(timeout: 5))
        // Language, sounds and the small indicator. Clean already shows, and shortcuts never import.
        XCTAssertEqual(app.staticTexts.matching(identifier: "settings-portavoz-import-item").count, 3)
        attachScreenshot(named: "pr-settings-portavoz-import")
        app.control(withIdentifier: "settings-portavoz-import-cancel").click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !confirm.exists })
        XCTAssertTrue(importRow.exists, "Cancel imports nothing")

        importRow.click()
        XCTAssertTrue(confirm.waitForStableFrame(timeout: 5))
        confirm.click()

        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !importRow.exists }, "Nothing is left to import")
        let sounds = app.control(withIdentifier: "settings-dictation-sounds")
        XCTAssertTrue(sounds.waitForExistence(timeout: 5))
        XCTAssertTrue(sounds.value as? Int == 1 || sounds.value as? String == "1")
    }

    func testADownloadShowsHowFarItGot() throws {
        let app = try launch("-seed-model-download-held")
        defer { finishUITestApplication(app) }
        let download = app.control(withIdentifier: "settings-dictation-model-download")
        let progress = app.control(withIdentifier: "settings-dictation-model-progress")
        XCTAssertTrue(download.waitForStableFrame(timeout: 5))

        download.click()

        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        // The fixture stops at 40%, and macOS reports it as a fraction or a percentage.
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            (progress.value as? Double).map { abs($0 - 0.4) < 0.01 } == true || "\(progress.value ?? "")".contains("40")
        }, "\(progress.value ?? "nil")")
        attachScreenshot(named: "pr-settings-model-progress")
    }

    func testUltraIsDownloadedOnlyWhenAsked() throws {
        let app = try launchEnabled(arguments: ["-seed-model-download-held"])
        defer { finishUITestApplication(app) }
        let engine = app.control(withIdentifier: "settings-dictation-engine")
        let download = app.control(withIdentifier: "settings-dictation-ultra-download")
        let progress = app.control(withIdentifier: "settings-dictation-ultra-progress")
        XCTAssertTrue(app.revealInSettings(engine))
        XCTAssertTrue(app.revealInSettings(download), "Ultra is the default, and nothing has fetched it yet")
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-ultra-failed").exists)

        download.click()

        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        // The fixture stops Ultra at 40%, and macOS reports it as a fraction or a percentage.
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            (progress.value as? Double).map { abs($0 - 0.4) < 0.01 } == true || "\(progress.value ?? "")".contains("40")
        }, "\(progress.value ?? "nil")")
        attachScreenshot(named: "pr-settings-speech-engine")
    }

    func testFreeingTheModelSoonRulesOutLoadingItAtLaunch() throws {
        let app = try launchEnabled(defaults: #""dictationPrewarm":true"#)
        defer { finishUITestApplication(app) }
        let lightweight = app.control(withIdentifier: "settings-model-memory-lightweight")
        let prewarm = app.control(withIdentifier: "settings-dictation-prewarm")
        // The form leaves rows below the fold out of the accessibility tree.
        app.control(withIdentifier: "settings-root").scroll(byDeltaX: 0, deltaY: -600)
        XCTAssertTrue(lightweight.waitForStableFrame(timeout: 5))
        XCTAssertTrue(prewarm.isEnabled)
        XCTAssertTrue(prewarm.value as? Int == 1 || prewarm.value as? String == "1")

        lightweight.click()

        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !prewarm.isEnabled })
        XCTAssertTrue(prewarm.value as? Int == 0 || prewarm.value as? String == "0", "Off, not greyed out on")
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

    func testAVocabularyTermCanBeRemoved() throws {
        let app = try launchEnabled(defaults: #""customVocabulary":"Secreteo""#)
        defer { finishUITestApplication(app) }
        let remove = app.control(withIdentifier: "settings-dictation-vocabulary-remove")
        XCTAssertTrue(remove.waitForExistence(timeout: 5))

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
