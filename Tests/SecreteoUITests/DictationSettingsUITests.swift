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

    private func assertControlsExist(
        _ identifiers: [String], in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        // One tree read covers settled controls; missing ones retain their individual wait.
        var nodes = (try? app.snapshot().children) ?? []
        var present = Set<String>()
        while let node = nodes.popLast() {
            present.insert(node.identifier)
            nodes.append(contentsOf: node.children)
        }
        for identifier in identifiers {
            XCTAssertTrue(
                present.contains(identifier) || app.control(withIdentifier: identifier).waitForExistence(timeout: 5),
                identifier, file: file, line: line)
        }
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
        let setUp = app.buttons["menu-bar-set-up-dictation"]
        XCTAssertTrue(setUp.exists, "Off, the menu offers setup, not a dead Dictate")
        XCTAssertTrue(renderedText(of: setUp).contains("Turn On Dictation"), "The button names the missing step")
        XCTAssertFalse(app.buttons["menu-bar-dictate"].exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-failed-to-start").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-tab-text").exists, "Off, there is no text to shape")
        XCTAssertFalse(app.control(withIdentifier: "settings-tab-polish").exists)
        assertControlsExist(["settings-tab-dictation", "settings-tab-history", "settings-tab-general"], in: app)
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

        assertControlsExist(SettingsTabIdentifier.allCases.map(\.rawValue), in: app)
        assertControlsExist([
            "settings-dictation-practice-field", "settings-dictation-practice-start",
            "settings-dictation-mouse-recorder", "settings-dictation-modifier-key", "settings-dictation-sounds",
            "settings-dictation-compact", "settings-dictation-indicator-capsule", "settings-dictation-speech-gate",
            "settings-dictation-compact-elapsed", "settings-dictation-compact-backdrop",
            "settings-dictation-auto-stop", "settings-dictation-engine", "settings-dictation-language",
            "settings-dictation-microphone-device"
        ], in: app)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-mouse-clear").exists, "No button is set")
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-auto-stop-pause").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-modifier-unavailable").exists)
        XCTAssertTrue(
            app.control(withIdentifier: "settings-dictation-modifier-fn-note").exists, "Fn is held by default")
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-modifier-fn-settings").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-practice-missing").exists)
        attachScreenshot(named: "pr-settings-tab-dictation")

        try requireForeground(app)
        app.control(withIdentifier: "settings-root").scroll(byDeltaX: 0, deltaY: -1_200)
        attachScreenshot(named: "pr-settings-tab-dictation-bottom")

        app.openSettingsTab(.text)
        assertControlsExist([
            "settings-dictation-text-mode", "settings-dictation-filler", "settings-dictation-dict-trigger",
            "settings-dictation-dict-replacement", "settings-dictation-dict-add", "settings-dictation-profiles",
            "settings-dictation-vocabulary-field", "settings-dictation-vocabulary-add",
            "settings-dictation-corrections", "settings-dictation-caret-case"
        ], in: app)
        attachScreenshot(named: "pr-settings-tab-text")

        app.openSettingsTab(.polish)
        assertControlsExist([
            "settings-dictation-polish-engine", "settings-dictation-polish-preview", "settings-dictation-recipes",
            "settings-dictation-recipe-new", "settings-dictation-translate", "settings-dictation-rewrite-hotkey",
            "settings-dictation-paste-last-hotkey"
        ], in: app)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-paste-last-taken").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-rewrite-taken").exists)
        attachScreenshot(named: "pr-settings-tab-polish")

        app.openSettingsTab(.history)
        assertControlsExist(["settings-dictation-history", "settings-dictation-stats"], in: app)

        app.openSettingsTab(.general)
        assertControlsExist([
            "settings-model-memory-lightweight", "settings-dictation-prewarm", "settings-launch-at-login",
            "settings-version"
        ], in: app)
    }

    /// A system switch reports its own value.
    private func switchIsOn(_ element: XCUIElement) -> Bool {
        element.value as? Int == 1 || element.value as? String == "1"
    }

    func testTheIndicatorIsChosenByPicture() throws {
        let app = try launchEnabled()
        defer { finishUITestApplication(app) }
        let capsule = app.control(withIdentifier: "settings-dictation-indicator-capsule")
        let small = app.control(withIdentifier: "settings-dictation-compact")
        XCTAssertTrue(app.revealInSettings(small))
        XCTAssertTrue(capsule.isSelected, "The capsule with your words is the default")
        XCTAssertFalse(small.isSelected)
        let elapsed = app.control(withIdentifier: "settings-dictation-compact-elapsed")
        let backdrop = app.control(withIdentifier: "settings-dictation-compact-backdrop")
        XCTAssertTrue(app.revealInSettings(backdrop))
        XCTAssertFalse(elapsed.isEnabled, "The small indicator's looks wait while the capsule is chosen")
        XCTAssertFalse(backdrop.isEnabled)
        XCTAssertFalse(switchIsOn(elapsed), "Off by default")
        XCTAssertFalse(switchIsOn(backdrop), "Off by default")

        small.click()

        XCTAssertTrue(waitForUITestCondition(timeout: 5) { small.isSelected && !capsule.isSelected })
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { elapsed.isEnabled && backdrop.isEnabled })
        elapsed.click()
        backdrop.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { self.switchIsOn(elapsed) && self.switchIsOn(backdrop) })
        attachScreenshot(named: "pr-indicator-settings")
    }

    func testTheTabsKeepTheirLookInDark() throws {
        let app = try launchEnabled(arguments: ["-AppleInterfaceStyle", "Dark"])
        defer { finishUITestApplication(app) }

        app.openSettingsTab(.polish)
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-polish-preview").waitForExistence(timeout: 5))
        attachScreenshot(named: "pr-settings-tab-polish-dark")

        app.openSettingsTab(.general)
        XCTAssertTrue(app.control(withIdentifier: "settings-open-notices").waitForExistence(timeout: 5))
        attachScreenshot(named: "pr-settings-tab-general-dark")
    }

    func testOpeningSettingsWithEditableReplacementsStaysAtTheTop() throws {
        let app = try launchEnabled(defaults: #""dictationTextMode":"clean""#)
        defer { finishUITestApplication(app) }

        let enabled = app.control(withIdentifier: "settings-dictation-enabled")

        XCTAssertTrue(enabled.waitForStableFrame(timeout: 5))
        app.openSettingsTab(.text)
        let mode = app.control(withIdentifier: "settings-dictation-text-mode")
        let trigger = app.control(withIdentifier: "settings-dictation-dict-trigger")
        XCTAssertTrue(mode.waitForStableFrame(timeout: 5), "No text field takes focus and scrolls the tab")
        XCTAssertTrue(trigger.isEnabled, "Clean mode makes the replacements editable")
        XCTAssertLessThan(mode.frame.minY, trigger.frame.minY)
        XCTAssertLessThan(
            mode.frame.minY - app.control(withIdentifier: "settings-tab-text").frame.maxY, 60,
            "The first row sits right under the tabs")
    }

    func testTheRewriteShortcutTurnsOnWithoutAConflict() throws {
        let app = try launchEnabled()
        defer { finishUITestApplication(app) }
        let toggle = app.control(withIdentifier: "settings-dictation-rewrite-hotkey")
        XCTAssertTrue(app.revealInSettings(toggle, tab: .polish))
        XCTAssertTrue(toggle.label.contains("⌃⌥⌘R"), "The shortcut is read with the switch")
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
        XCTAssertTrue(app.revealInSettings(toggle, tab: .polish))
        XCTAssertTrue(toggle.label.contains("⌃⌥⌘V"), "The shortcut is read with the switch")
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
        XCTAssertTrue(app.revealInSettings(importRow, tab: .general))

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
        app.openSettingsTab(.dictation)
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
        let ultra = app.control(withIdentifier: "settings-dictation-engine-ultra")
        XCTAssertTrue(app.revealInSettings(ultra))
        XCTAssertTrue(engine.exists)
        XCTAssertTrue(ultra.isSelected)
        XCTAssertTrue(renderedText(of: engine).contains("Parakeet Ultra"), "The group reads its choice")
        for other in ["settings-dictation-engine-parakeet", "settings-dictation-engine-apple"] {
            XCTAssertTrue(app.control(withIdentifier: other).exists, other)
            XCTAssertFalse(app.control(withIdentifier: other).isSelected, other)
        }
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

    func testAppleSpeechDownloadsOnlyTheDetector() throws {
        let app = try launchEnabled(
            defaults: #""dictationLiveSpeechEngine":"appleSpeech""#, arguments: ["-seed-model-download-held"])
        defer { finishUITestApplication(app) }
        let download = app.control(withIdentifier: "settings-dictation-model-download")
        let progress = app.control(withIdentifier: "settings-dictation-model-progress")
        XCTAssertTrue(app.revealInSettings(download))
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-ultra-download").exists)

        download.click()

        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        // The fixture holds the detector alone at 20%; with Parakeet in the set it would read 40%.
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            if let fraction = progress.value as? Double { return abs(fraction - 0.2) < 0.01 }
            let percent = "\(progress.value ?? "")".trimmingCharacters(in: .whitespaces)
            return percent == "20%" || percent == "20 %"
        }, "\(progress.value ?? "nil")")
        attachScreenshot(named: "pr-settings-apple-speech")
    }

    func testFreeingTheModelSoonRulesOutLoadingItAtLaunch() throws {
        let app = try launchEnabled(defaults: #""dictationPrewarm":true"#)
        defer { finishUITestApplication(app) }
        let lightweight = app.control(withIdentifier: "settings-model-memory-lightweight")
        let prewarm = app.control(withIdentifier: "settings-dictation-prewarm")
        XCTAssertTrue(app.revealInSettings(lightweight, tab: .general))
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
        XCTAssertTrue(app.revealInSettings(trigger, tab: .text))

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
        XCTAssertTrue(app.revealInSettings(remove, tab: .text))

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
        let allow = app.control(withIdentifier: "settings-dictation-accessibility")
        XCTAssertTrue(allow.exists)

        allow.click()

        let guide = app.control(withIdentifier: "accessibility-guide")
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "The icon to drag floats beside System Settings")
        XCTAssertTrue(app.control(withIdentifier: "accessibility-guide-icon").exists)
        attachScreenshot(named: "pr-accessibility-guide")
        app.control(withIdentifier: "accessibility-guide-close").click()
        XCTAssertTrue(guide.waitForDisappearance(timeout: 5))
    }

    func testUnfinishedPracticeIsNamedInTheHeader() throws {
        let app = try launchEnabled(arguments: ["-seed-dictation-practice-missing"])
        defer { finishUITestApplication(app) }

        let practice = app.control(withIdentifier: "settings-dictation-practice-missing")
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-practice-field").exists, "Right below it")
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

    func testWithNoOwnerTheMenuOffersToTakeDictation() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        // The board draws this state dark.
        app.launchArguments += ["-seed-dictation-no-owner", "-AppleInterfaceStyle", "Dark"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }

        let take = app.buttons["menu-bar-take-ownership"]
        let title = app.control(withIdentifier: "menu-state-title")
        XCTAssertTrue(take.waitForStableFrame(timeout: 30))
        XCTAssertFalse(app.buttons["menu-bar-dictate"].exists)
        XCTAssertFalse(app.buttons["menu-bar-set-up-dictation"].exists, "Setup is done; only ownership is missing")
        XCTAssertTrue(renderedText(of: title).contains("Standing by"))
        attachScreenshot(named: "pr-menu-standing-by")

        take.click()

        XCTAssertTrue(app.buttons["menu-bar-dictate"].waitForExistence(timeout: 5))
        XCTAssertFalse(take.exists)
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: title).contains("Ready") })
    }

    func testAllPermissionsGrantedOfferNoActions() throws {
        let app = try launch()
        defer { finishUITestApplication(app) }

        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-microphone").exists)
        XCTAssertFalse(app.control(withIdentifier: "settings-dictation-accessibility").exists)
    }
}
