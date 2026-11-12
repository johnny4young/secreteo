import XCTest

/// Settings lists the shared model folder of a disposable store with two synthetic models:
/// one this app keeps alone, one a fixture app named Portavoz also keeps.
@MainActor
final class DictationModelListUITests: SecreteoUITestCase {
    // Rows are sorted by store key, so the detector comes before the speech model.
    private func row(_ index: Int) -> String { "settings-model-\(index)" }
    private func name(_ index: Int) -> String { "settings-model-name-\(index)" }
    private func size(_ index: Int) -> String { "settings-model-size-\(index)" }
    private func shared(_ index: Int) -> String { "settings-model-shared-\(index)" }
    private func remove(_ index: Int) -> String { "settings-model-remove-\(index)" }

    func testRemovingAModelDropsOnlyThisAppsClaim() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-model-shelf"]
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.buttons["menu-settings"].waitForStableFrame(timeout: 30))
        app.buttons["menu-settings"].click()
        XCTAssertTrue(app.control(withIdentifier: "settings-root").waitForExistence(timeout: 5))

        let detector = 0, speech = 1
        let sharedRemove = app.control(withIdentifier: remove(speech))
        XCTAssertTrue(app.revealInSettings(sharedRemove))
        XCTAssertTrue(app.control(withIdentifier: row(speech)).exists)
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: name(speech))).contains("Sample Speech Model"))
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: name(detector))).contains("Sample Voice Detector"))
        XCTAssertTrue(app.control(withIdentifier: size(speech)).exists)
        XCTAssertTrue(app.control(withIdentifier: size(detector)).exists)
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: shared(speech))).contains("Portavoz"))
        XCTAssertFalse(app.control(withIdentifier: shared(detector)).exists, "Only this app keeps it")
        XCTAssertTrue(app.control(withIdentifier: remove(detector)).exists)
        attachScreenshot(named: "pr-settings-models")

        sharedRemove.click()
        let confirm = app.control(withIdentifier: "settings-model-remove-confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()

        XCTAssertTrue(sharedRemove.waitForNonExistence(timeout: 5), "This app no longer keeps it")
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: name(speech))).contains("Sample Speech Model"),
                      "Portavoz still keeps it")
        XCTAssertTrue(renderedText(of: app.control(withIdentifier: shared(speech))).contains("Portavoz"))

        let soloRemove = app.control(withIdentifier: remove(detector))
        XCTAssertTrue(app.revealInSettings(soloRemove))
        soloRemove.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()

        // The speech model moves up to the first row once the detector is gone.
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            !app.control(withIdentifier: name(speech)).exists
                && renderedText(of: app.control(withIdentifier: name(detector))).contains("Sample Speech Model")
        })
        XCTAssertFalse(app.control(withIdentifier: "settings-model-remove-failed").exists)
        attachScreenshot(named: "pr-settings-models-after-remove")
    }
}
