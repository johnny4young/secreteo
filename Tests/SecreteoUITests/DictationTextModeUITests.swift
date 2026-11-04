import AppKit
import XCTest

final class DictationTextModeUITests: SecreteoUITestCase {

    @MainActor
    func testSessionModeOverrideCancelsAndRestartsWithoutChangingDefaults() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments.append("-seed-dictation")
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationTextMode":"literal"}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForHittable(timeout: 5))
        dictate.click()
        let mode = app.control(withIdentifier: "dictation-panel-text-mode")
        XCTAssertTrue(mode.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: mode).contains("Literal"))
        try select(.clean, prefix: "dictation-panel-text-mode", in: app)
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: mode).contains(cleanTitle) })
        app.buttons["dictation-panel-cancel"].click()
        XCTAssertTrue(mode.waitForDisappearance(timeout: 5))
        XCTAssertTrue(app.prepareForInteraction())
        dictate.click()
        XCTAssertTrue(mode.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(renderedText(of: mode).contains("Literal"), "A cancelled session must not retain its override")
        app.buttons["dictation-panel-cancel"].click()
        XCTAssertTrue(mode.waitForDisappearance(timeout: 5))
    }

    private enum Mode: String { case literal, clean }

    @MainActor
    private func select(_ mode: Mode, prefix: String, in app: XCUIApplication) throws {
        let picker = app.control(withIdentifier: prefix)
        XCTAssertTrue(picker.waitForHittable(timeout: 5))
        picker.click()
        let option = app.menuItems[prefix + "-" + mode.rawValue]
        XCTAssertTrue(option.waitForExistenceFast(timeout: 5))
        option.click()
    }

    private var cleanTitle: String { UITestLocale.environmentLocale == "es" ? "Limpio" : "Clean" }

    @MainActor
    private func makeApplication(in app: XCUIApplication) throws -> URL {
        let root = URL(fileURLWithPath: try XCTUnwrap(app.launchEnvironment["TMPDIR"]), isDirectory: true)
        let directory = root.appendingPathComponent("dictation-profile-applications/Fixture.app/Contents")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plist = directory.appendingPathComponent("Info.plist")
        let values = ["CFBundleIdentifier": "com.johnny4young.secreteo.profile.fixture", "CFBundlePackageType": "APPL",
                      "CFBundleName": "Fixture", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: plist)
        return plist
    }
}
