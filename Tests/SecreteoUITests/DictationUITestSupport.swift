import XCTest

/// Runs the real app with a temporary store. Input is synthesized globally, so nothing
/// is clicked until this app is in front.
class SecreteoUITestCase: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    func finishUITestApplication(_ application: XCUIApplication) {
        application.terminate()
    }

    /// Evidence for a PR, so it must show the state it settled on.
    @MainActor
    func attachScreenshot(named name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

enum UITestLocale {
    static let environmentLocale = "en"
}

extension XCUIApplication {
    @MainActor
    static func secreteo(showMenuBarContent: Bool = false) throws -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-use-temp-store", "-AppleLanguages", "(en)"]
        if showMenuBarContent { application.launchArguments.append("-show-menu-content") }
        return application
    }

    @MainActor
    func launchSecreteo() {
        launch()
        activate()
        XCTAssertTrue(wait(for: .runningForeground, timeout: 30))
    }

    @MainActor
    @discardableResult
    func prepareForInteraction(timeout: TimeInterval = 10) -> Bool {
        activate()
        return wait(for: .runningForeground, timeout: timeout)
    }
}

extension XCUIApplication {
    @MainActor
    func control(withIdentifier identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

extension XCUIElement {
    @MainActor
    func waitForHittable(timeout: TimeInterval) -> Bool {
        waitForStableFrame(timeout: timeout)
    }

    @MainActor
    func waitForDisappearance(timeout: TimeInterval) -> Bool {
        waitForUITestCondition(timeout: timeout) { !self.exists }
    }

    @MainActor
    func waitForExistenceFast(timeout: TimeInterval) -> Bool {
        waitForExistence(timeout: timeout)
    }

    @MainActor
    func waitForStableFrame(timeout: TimeInterval) -> Bool {
        waitForExistence(timeout: timeout) && waitForUITestCondition(timeout: timeout) { self.isHittable }
    }
}

@MainActor
func renderedText(of element: XCUIElement) -> String {
    [element.value as? String, element.label].compactMap { $0 }.joined(separator: " ")
}

@MainActor
func waitForUITestCondition(timeout: TimeInterval, _ condition: @MainActor () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}
