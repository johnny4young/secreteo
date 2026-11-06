import AppKit
import XCTest

/// First-run setup, which a disposable launch shows only when a test forces it.
@MainActor
final class OnboardingUITests: SecreteoUITestCase {
    private func launch(_ arguments: [String] = [], defaults: String? = nil) throws -> XCUIApplication {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-show-onboarding"] + arguments
        if let defaults { app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = defaults }
        app.launchSecreteo()
        XCTAssertTrue(app.control(withIdentifier: "onboarding-dictation").waitForExistence(timeout: 30))
        return app
    }

    /// Synthesized input is global, so it must never reach another app.
    private func requireForeground(_ app: XCUIApplication) throws {
        guard app.state == .runningForeground else { throw XCTSkip("The app is not in front") }
    }

    private func isOn(_ element: XCUIElement) -> Bool {
        element.value as? Int == 1 || element.value as? String == "1"
    }

    func testTheStepsWalkForwardAndBackAndDoneLeavesDictationOff() throws {
        let app = try launch()
        defer { finishUITestApplication(app) }
        let toggle = app.control(withIdentifier: "onboarding-dictation-toggle")
        XCTAssertTrue(toggle.exists)
        XCTAssertFalse(isOn(toggle))
        XCTAssertTrue(app.control(withIdentifier: "onboarding-skip").exists)
        XCTAssertFalse(app.control(withIdentifier: "onboarding-back").exists, "The first step has nothing behind it")
        XCTAssertFalse(app.control(withIdentifier: "onboarding-microphone-allow").exists, "Off, only the switch shows")
        attachScreenshot(named: "pr-onboarding-dictation")

        try requireForeground(app)
        let next = app.control(withIdentifier: "onboarding-continue")
        next.click()
        XCTAssertTrue(app.control(withIdentifier: "onboarding-model").waitForExistence(timeout: 5))
        let prepare = app.control(withIdentifier: "onboarding-model-prepare")
        XCTAssertTrue(prepare.waitForStableFrame(timeout: 5))
        prepare.click()
        XCTAssertTrue(app.control(withIdentifier: "onboarding-model-ready").waitForExistence(timeout: 5))
        XCTAssertFalse(app.control(withIdentifier: "onboarding-model-preparing").exists)
        XCTAssertFalse(app.control(withIdentifier: "onboarding-model-error").exists)
        attachScreenshot(named: "pr-onboarding-model")

        app.control(withIdentifier: "onboarding-back").click()
        XCTAssertTrue(app.control(withIdentifier: "onboarding-dictation").waitForExistence(timeout: 5))
        XCTAssertFalse(isOn(app.control(withIdentifier: "onboarding-dictation-toggle")), "Continuing never turns it on")
        next.click()
        XCTAssertTrue(app.control(withIdentifier: "onboarding-model-ready").waitForExistence(timeout: 5))
        next.click()

        XCTAssertTrue(app.control(withIdentifier: "onboarding-practice").waitForExistence(timeout: 5))
        let start = app.control(withIdentifier: "onboarding-dictation-practice-start")
        XCTAssertTrue(start.exists)
        XCTAssertFalse(start.isEnabled, "Off, the field waits instead of explaining")
        XCTAssertTrue(app.control(withIdentifier: "onboarding-dictation-practice-field").exists)
        XCTAssertEqual(next.label, "Done")
        attachScreenshot(named: "pr-onboarding-practice")

        next.click()
        XCTAssertTrue(app.control(withIdentifier: "onboarding-practice").waitForDisappearance(timeout: 5))
        XCTAssertTrue(app.buttons["menu-bar-set-up-dictation"].exists, "Dictation stayed off")
    }

    func testAFailedPreparationCanBeRetriedWithoutDownloading() throws {
        let app = try launch(["-simulate-onboarding-model-recovery"])
        defer { finishUITestApplication(app) }
        try requireForeground(app)
        app.control(withIdentifier: "onboarding-continue").click()
        let prepare = app.control(withIdentifier: "onboarding-model-prepare")
        XCTAssertTrue(prepare.waitForStableFrame(timeout: 5))
        prepare.click()

        let failure = app.control(withIdentifier: "onboarding-model-error")
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertEqual(renderedText(of: failure), "Models could not be downloaded. Check your connection and try again.")
        XCTAssertTrue(app.control(withIdentifier: "onboarding-model-retry").exists)
        XCTAssertTrue(app.control(withIdentifier: "onboarding-skip").exists)
        attachScreenshot(named: "onboarding-model-recovery")

        app.control(withIdentifier: "onboarding-model-continue-without").click()
        XCTAssertTrue(app.control(withIdentifier: "onboarding-practice").waitForExistence(timeout: 5))
        app.control(withIdentifier: "onboarding-back").click()
        XCTAssertTrue(failure.waitForExistence(timeout: 5), "Going back keeps the failure")
        app.control(withIdentifier: "onboarding-model-retry").click()
        XCTAssertTrue(app.control(withIdentifier: "onboarding-model-ready").waitForExistence(timeout: 5))
        XCTAssertFalse(failure.exists)
        XCTAssertFalse(app.control(withIdentifier: "onboarding-model-retry").exists)
        XCTAssertFalse(prepare.exists)
    }

    func testSkipClosesSetup() throws {
        let app = try launch()
        defer { finishUITestApplication(app) }
        try requireForeground(app)
        app.control(withIdentifier: "onboarding-skip").click()
        XCTAssertTrue(app.control(withIdentifier: "onboarding-dictation").waitForDisappearance(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "menu-content").exists, "Only setup closes")
    }

    func testTurningDictationOnShowsTheShortcutAndGrantedPermissions() throws {
        let app = try launch()
        defer { finishUITestApplication(app) }
        try requireForeground(app)
        let toggle = app.control(withIdentifier: "onboarding-dictation-toggle")
        toggle.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { self.isOn(toggle) })
        XCTAssertTrue(app.control(withIdentifier: "settings-dictation-hotkey-recorder").waitForExistence(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "onboarding-microphone-allowed").exists)
        XCTAssertTrue(app.control(withIdentifier: "onboarding-accessibility-allowed").exists)
        XCTAssertFalse(app.control(withIdentifier: "onboarding-microphone-allow").exists)
        XCTAssertFalse(app.control(withIdentifier: "onboarding-accessibility-allow").exists)
        attachScreenshot(named: "onboarding-dictation-on")
    }

    func testMissingPermissionsOfferAllow() throws {
        let app = try launch(
            ["-seed-dictation-permissions-missing"], defaults: #"{"globalDictationEnabled":true}"#)
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.control(withIdentifier: "onboarding-microphone-allow").waitForExistence(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "onboarding-accessibility-allow").exists)
        XCTAssertFalse(app.control(withIdentifier: "onboarding-microphone-allowed").exists)
        XCTAssertFalse(app.control(withIdentifier: "onboarding-accessibility-allowed").exists)
    }

    func testThePracticeStepReceivesDictationWithoutTheClipboard() throws {
        var arguments = ["-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-verified"]
        if UITestLocale.environmentLocale == "en" { arguments.append("-seed-dictation-english") }
        let app = try launch(arguments, defaults: #"{"globalDictationEnabled":true}"#)
        defer { finishUITestApplication(app) }
        try requireForeground(app)
        app.control(withIdentifier: "onboarding-continue").click()
        app.control(withIdentifier: "onboarding-continue").click()

        let expected = UITestLocale.environmentLocale == "en" ? "Don't delete these notes." : "No borres estas notas."
        let start = app.buttons["onboarding-dictation-practice-start"]
        XCTAssertTrue(start.waitForStableFrame(timeout: 5))
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(app.buttons["onboarding-dictation-practice-clear"].exists)
        let clipboard = NSPasteboard.general.changeCount
        start.click()
        let transcript = app.staticTexts["dictation-panel-transcript"]
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: transcript).contains(expected) })
        start.click()

        let field = app.control(withIdentifier: "onboarding-dictation-practice-field")
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { field.value as? String == expected })
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboard, "Practice never borrows the clipboard")
        attachScreenshot(named: "onboarding-dictation-practice")
        XCTAssertTrue(app.dialogs["dictation-panel"].waitForDisappearance(timeout: 5))
        app.buttons["onboarding-dictation-practice-clear"].click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { field.value as? String != expected })
    }
}
