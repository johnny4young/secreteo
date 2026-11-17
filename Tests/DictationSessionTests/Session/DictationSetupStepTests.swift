import XCTest

@testable import DictationSession

final class DictationSetupStepTests: XCTestCase {
    private func step(
        enabled: Bool = true, microphone: Bool = true, accessibility: Bool = true,
        model: DictationFeature.ModelState = .ready, practice: Bool = true
    ) -> DictationSetupStep? {
        DictationFeature.setupStep(
            isEnabled: enabled, microphoneIsAuthorized: microphone, accessibilityIsGranted: accessibility,
            modelState: model, practiceIsComplete: practice)
    }

    func testTheFirstMissingPieceIsTheOneOffered() {
        XCTAssertEqual(step(enabled: false, microphone: false, model: .missing, practice: false), .turnOn)
        XCTAssertEqual(step(microphone: false, accessibility: false, model: .missing), .allowMicrophone)
        XCTAssertEqual(step(accessibility: false, model: .missing), .allowAccessibility)
        XCTAssertEqual(step(model: .missing, practice: false), .downloadModel)
        XCTAssertEqual(step(model: .failed), .downloadModel, "A failed download is offered again")
        XCTAssertEqual(step(model: .downloading), .downloadingModel)
        XCTAssertEqual(step(practice: false), .practice)
        XCTAssertNil(step())
    }

    @MainActor
    func testADisposableLaunchNeedsNoPracticeUnlessSeeded() throws {
        let name = "DictationSetupStepTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let feature = try DictationFeature(usesTemporaryStore: true, arguments: [], defaults: defaults)
        feature.start()
        XCTAssertTrue(feature.practiceIsComplete)
        XCTAssertEqual(feature.setupStep, .turnOn)
        let seeded = try DictationFeature(
            usesTemporaryStore: true, arguments: ["-seed-dictation-practice-missing"], defaults: defaults)
        seeded.start()
        XCTAssertFalse(seeded.practiceIsComplete)
    }
}
