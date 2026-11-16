import Foundation
import LocalModelStore
import XCTest

@testable import DictationSession

final class OnboardingModelPreparationTests: XCTestCase {
    @MainActor
    func testFailedPreparationIsVisibleAndRetryReplacesFailureWithReady() async {
        let model = OnboardingModelPreparation()
        await model.prepare { throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(model.phase, .failed(.network))
        XCTAssertEqual(model.attempt, 1)
        await model.prepare {
            XCTAssertEqual(model.phase, .preparing)
        }
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.attempt, 2)
        await model.prepare { XCTFail("ready models must not prepare again") }
        XCTAssertEqual(model.attempt, 2)
    }

    @MainActor
    func testEachModelSaysWhereItStands() async {
        let model = OnboardingModelPreparation()
        XCTAssertEqual(model.speechStatus(isInstalled: false), .missing)
        XCTAssertEqual(model.speechStatus(isInstalled: true), .installed(copied: false))
        XCTAssertEqual(model.detectorStatus(isInstalled: false), .missing)
        XCTAssertEqual(model.detectorStatus(isInstalled: true), .ready(copied: false))

        await model.prepare {
            XCTAssertEqual(model.speechStatus(isInstalled: false), .downloading)
            XCTAssertEqual(model.speechStatus(isInstalled: true), .installed(copied: false))
            XCTAssertEqual(model.detectorStatus(isInstalled: false), .downloading)
            model.entered(.installing(copying: true))
            XCTAssertEqual(model.speechStatus(isInstalled: false), .copying, "A copy is not called a download")

            model.entered(.warming(copied: true))
            XCTAssertEqual(model.speechStatus(isInstalled: true), .installed(copied: true))
            XCTAssertEqual(model.detectorStatus(isInstalled: false), .ready(copied: false))
        }
        XCTAssertEqual(model.speechStatus(isInstalled: true), .ready(copied: true))
        XCTAssertFalse(model.speechStatus(isInstalled: true).isReady, "A copy says where it came from")
        XCTAssertTrue(model.detectorStatus(isInstalled: true).isReady)
        model.entered(.warming(copied: false))
        XCTAssertEqual(model.speechStatus(isInstalled: true), .ready(copied: true), "A late report changes nothing")
    }

    @MainActor
    func testTheCapsuleNeverEmptiesOrShowsAMadeUpNumber() async {
        let model = OnboardingModelPreparation()
        model.downloaded(0.5)
        XCTAssertNil(model.fraction, "Nothing is being prepared yet")
        await model.prepare {
            XCTAssertNil(model.fraction, "No bytes reported, no number")
            model.downloaded(0.4)
            model.downloaded(0.72)
            model.downloaded(0.6)
            XCTAssertEqual(model.fraction, 0.72)
            model.downloaded(nil)
            XCTAssertEqual(model.fraction, 0.72, "The store clearing its fraction does not empty the capsule")

            model.entered(.warming(copied: false))
            XCTAssertTrue(model.isWarming)
            XCTAssertNil(model.fraction, "Warming up has no measure")
            throw URLError(.timedOut)
        }
        await model.prepare {
            XCTAssertFalse(model.isWarming, "A retry starts before the warm-up again")
            XCTAssertNil(model.fraction)
        }
    }

    func testThePassingLightCrossesTheWholeCapsule() {
        let width: CGFloat = 448, band = width * OnboardingModelStep.sweepShare
        XCTAssertEqual(OnboardingModelStep.sweepOffset(at: 0, width: width), -band, accuracy: 0.001)
        let end = OnboardingModelStep.sweepOffset(at: OnboardingModelStep.sweepPeriod - 0.0001, width: width)
        XCTAssertEqual(end, width, accuracy: 0.1)
    }

    func testAStepChangeIsAnnouncedWithItsTitleAndPlace() {
        XCTAssertEqual(OnboardingView.announcement(step: 0, count: 3), "Dictate Anywhere. Step 1 of 3")
        XCTAssertEqual(OnboardingView.announcement(step: 2, count: 3), "Try It Here. Step 3 of 3")
    }

    func testTheFieldKeepsRoomUnderItsWordsForTheCapsuleAndItsNotice() {
        XCTAssertGreaterThanOrEqual(
            OnboardingPracticeStep.roomUnderWords, DictationPanelLayout.capsuleHeight(showsNotice: true))
    }

    func testTheTitleLeansItsLastWord() {
        XCTAssertEqual(OnboardingTitle.split("Dictate Anywhere").lead, "Dictate ")
        XCTAssertEqual(OnboardingTitle.split("Dictate Anywhere").emphasis, "Anywhere")
        XCTAssertEqual(OnboardingTitle.split("Dictar en cualquier app").lead, "Dictar en cualquier ")
        XCTAssertEqual(OnboardingTitle.split("Listo").lead, "")
        XCTAssertEqual(OnboardingTitle.split("Listo").emphasis, "Listo")
    }

    func testThePracticeFieldKeepsTheTailProvisionalAndShowsTheRealKey() {
        let idle = OnboardingPracticeStep.words(delivered: "Hola.", confirmed: "old", partial: "tail", isLive: false)
        XCTAssertEqual(idle.settled, "Hola.")
        XCTAssertEqual(idle.provisional, "")
        let live = OnboardingPracticeStep.words(delivered: "Hola.", confirmed: "Esto es", partial: "una prueba", isLive: true)
        XCTAssertEqual(live.settled, "Hola. Esto es")
        XCTAssertEqual(live.provisional, " una prueba")
        let first = OnboardingPracticeStep.words(delivered: "", confirmed: "", partial: "hola", isLive: true)
        XCTAssertEqual(first.settled + first.provisional, "hola")

        XCTAssertEqual(OnboardingPracticeStep.keyLabel(modifier: .function, shortcut: "⌃⌥⌘D"), "fn")
        XCTAssertEqual(OnboardingPracticeStep.keyLabel(modifier: .rightOption, shortcut: "⌃⌥⌘D"), "⌥")
        XCTAssertEqual(OnboardingPracticeStep.keyLabel(modifier: .rightCommand, shortcut: "⌃⌥⌘D"), "⌘")
        XCTAssertEqual(OnboardingPracticeStep.keyLabel(modifier: .off, shortcut: "⌃⌥⌘D"), "⌃⌥⌘D")
    }

    @MainActor
    func testRepeatedAdmissionWhilePreparingDoesNotStartAnotherLoad() async {
        let model = OnboardingModelPreparation()
        await model.prepare {
            await model.prepare { XCTFail("preparation is already in flight") }
            XCTAssertEqual(model.phase, .preparing)
            XCTAssertEqual(model.attempt, 1)
        }
        XCTAssertEqual(model.phase, .ready)
    }

    @MainActor
    func testFailuresUseClosedCategoriesAndNeverExposeDescriptions() async {
        let cases: [(any Error, OnboardingModelPreparation.Failure)] = [
            (URLError(.timedOut), .network),
            (URLError(.cannotWriteToFile), .unavailable),
            (URLError(.cancelled), .cancelled),
            (CancellationError(), .cancelled),
            (LocalModelStore.LocalModelStoreError.downloadFailed(
                path: "private/model.bin",
                underlying: String(describing: URLError(.notConnectedToInternet))), .network),
            (LocalModelStore.LocalModelStoreError.checksumMismatch(
                path: "private/model.bin", expected: "a", actual: "b"), .unavailable),
            (LocalModelStore.LocalModelStoreError.outOfSpace(path: "Encoder.mlmodelc/weights/weight.bin"), .storage),
            (LocalModelStore.LocalModelStoreError.busy(id: "parakeet"), .unavailable),
            (DictationFeatureError.modelMissing, .unavailable),
            (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError), .storage),
            (NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), .storage),
            (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
            ]), .storage),
            (NSError(domain: NSURLErrorDomain, code: URLError.cannotWriteToFile.rawValue, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
            ]), .storage),
            (NSError(domain: NSURLErrorDomain, code: URLError.cannotCreateFile.rawValue, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EDQUOT))
            ]), .storage),
            (NSError(domain: NSURLErrorDomain, code: URLError.cannotWriteToFile.rawValue, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
            ]), .storage),
            (NSError(domain: NSURLErrorDomain, code: URLError.cannotWriteToFile.rawValue, userInfo: [
                NSMultipleUnderlyingErrorsKey: [
                    NSError(domain: NSURLErrorDomain, code: URLError.unknown.rawValue),
                    NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
                ]
            ]), .storage),
            (NSError(domain: "private.invalid", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "secret-token /private/model/path https://private.invalid"
            ]), .unavailable)
        ]
        for (error, expected) in cases {
            let model = OnboardingModelPreparation()
            await model.prepare { throw error }
            XCTAssertEqual(model.phase, .failed(expected))
            XCTAssertFalse(expected.message.contains("secret-token"))
            XCTAssertFalse(expected.message.contains("/private/"))
            XCTAssertFalse(expected.message.contains("https://"))
        }
    }

    @MainActor
    func testFixtureRequiresDisposableStoreAndNeverCallsRealPreparation() async throws {
        let flag = "-simulate-onboarding-model-recovery"
        XCTAssertNil(OnboardingModelPreparation.disposableFixtureResult(arguments: [flag], attempt: 1))
        XCTAssertNil(OnboardingModelPreparation.disposableFixtureResult(arguments: ["-use-temp-store"], attempt: 1))
        let arguments = ["-use-temp-store", flag]
        let first = try XCTUnwrap(OnboardingModelPreparation.disposableFixtureResult(arguments: arguments, attempt: 1))
        XCTAssertThrowsError(try first.get()) { error in
            XCTAssertEqual(OnboardingModelPreparation.Failure.classify(error), .network)
        }
        let second = try XCTUnwrap(OnboardingModelPreparation.disposableFixtureResult(arguments: arguments, attempt: 2))
        XCTAssertNoThrow(try second.get())
    }
}
