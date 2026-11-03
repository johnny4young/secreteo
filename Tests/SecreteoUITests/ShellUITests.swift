import XCTest

/// Runs the real app with a temporary store. The status item cannot be automated, so
/// `-show-menu-content` mounts its exact content in a window.
@MainActor
final class ShellUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-use-temp-store", "-show-menu-content", "-AppleLanguages", "(en)"]
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testMenuContentShowsItsCommands() {
        app.launch()
        XCTAssertTrue(element("menu-content").waitForExistence(timeout: 30))
        XCTAssertTrue(element("menu-settings").exists)
        XCTAssertTrue(element("menu-quit").exists)
        screenshot("pr-menu")
    }

    func testSettingsOpensFromTheMenuAndTogglesLaunchAtLogin() {
        app.launch()
        XCTAssertTrue(element("menu-settings").waitForExistence(timeout: 30))
        element("menu-settings").click()

        let toggle = element("settings-launch-at-login")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(element("settings-root").exists)
        XCTAssertTrue(element("settings-version").exists)
        XCTAssertTrue(element("settings-open-notices").exists)
        XCTAssertEqual(toggle.value as? Int, 0)

        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)
        XCTAssertFalse(element("settings-launch-at-login-error").exists)
        screenshot("pr-settings")
    }

    func testAFailedLaunchAtLoginChangeIsShown() {
        app.launchArguments.append("-fail-launch-at-login")
        app.launch()
        XCTAssertTrue(element("menu-settings").waitForExistence(timeout: 30))
        element("menu-settings").click()

        let toggle = element("settings-launch-at-login")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.click()

        XCTAssertTrue(element("settings-launch-at-login-error").waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 0)
        screenshot("pr-settings-error")
    }

    func testQuitEndsTheApp() {
        app.launch()
        XCTAssertTrue(element("menu-quit").waitForExistence(timeout: 30))
        element("menu-quit").click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }
}
