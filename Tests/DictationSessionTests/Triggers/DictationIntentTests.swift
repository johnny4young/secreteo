import Foundation
import XCTest

@testable import DictationSession

final class DictationIntentTests: XCTestCase {
    @MainActor
    func testDictationRequestsAreAnsweredDuringThePostAndNeverReplayed() async throws {
        XCTAssertEqual(SecreteoAppIntentBridge.requestDictation(.toggle), .notReady, "nobody listening yet")
        XCTAssertNil(SecreteoAppIntentBridge.consumeDictationRequest(), "a late dictation must not start after launch")

        let observer = NotificationCenter.default.addObserver(
            forName: SecreteoAppIntentBridge.dictationRequested, object: nil, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                if SecreteoAppIntentBridge.consumeDictationRequest() == .pasteLast {
                    SecreteoAppIntentBridge.answerDictationRequest(.nothingToPaste)
                } else {
                    SecreteoAppIntentBridge.answerDictationRequest(.accepted)
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = try await DictateIntent().perform()
        do {
            _ = try await PasteLastDictationIntent().perform()
            XCTFail("an empty paste must say so")
        } catch {
            XCTAssertEqual(error as? SecreteoDictationIntentError, .nothingToPaste)
        }
    }

    @MainActor
    func testOutcomesFollowTheAdmissionAndPhase() async {
        func outcome(
            _ request: SecreteoAppIntentBridge.DictationRequest, refusal: DictationAdmissionRefusal? = nil,
            phase: DictationController.Phase = .idle, pastable: Bool = true
        ) -> SecreteoAppIntentBridge.DictationRequestOutcome {
            DictationController.dictationIntentOutcome(
                for: request, refusal: refusal, phase: phase, hasPastableText: pastable)
        }
        XCTAssertEqual(outcome(.toggle, refusal: .dictationOff), .dictationOff)
        XCTAssertEqual(outcome(.pasteLast, refusal: .dictationOff), .dictationOff)
        XCTAssertEqual(outcome(.toggle, refusal: .notOwner), .notOwner)
        XCTAssertEqual(outcome(.pasteLast, refusal: .notOwner), .notOwner)
        XCTAssertEqual(outcome(.toggle, refusal: .unavailable(.legacyPeerActive)), .unavailable)
        XCTAssertEqual(outcome(.toggle, refusal: .transferring), .busy)
        XCTAssertEqual(outcome(.toggle, refusal: .busy), .busy)
        XCTAssertEqual(outcome(.toggle), .accepted)
        XCTAssertEqual(outcome(.toggle, phase: .listening), .accepted, "a second run finishes the dictation")
        XCTAssertEqual(outcome(.toggle, phase: .delivering), .busy)
        XCTAssertEqual(outcome(.pasteLast, phase: .listening), .busy)
        XCTAssertEqual(outcome(.pasteLast, pastable: false), .nothingToPaste)
        XCTAssertEqual(outcome(.pasteLast), .accepted)
    }

    @MainActor
    func testAnIntentNeverStartsOrPastesWhileAnotherAppOwnsDictation() async {
        let harness = DictationControllerHarness(text: "Send the report.")
        defer { harness.controller.cancel() }
        harness.controller.lastText.remember("Envía el informe.")
        var asked: [DictationAdmissionKind] = []
        var refused = harness.dependencies
        refused.admission = DictationAdmission(
            acquire: { kind in asked.append(kind); return .failure(.notOwner) }, isEligible: { false })

        XCTAssertEqual(harness.controller.performIntent(.toggle, using: refused), .notOwner)
        XCTAssertEqual(harness.controller.performIntent(.pasteLast, using: refused), .notOwner)
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(asked, [.global, .global], "asked through the shortcut's admission")
        XCTAssertEqual(harness.controller.phase, .idle)
        XCTAssertEqual(harness.loads, 0, "no model load and no capture")
        XCTAssertTrue(harness.insertions.isEmpty)
        XCTAssertEqual(harness.controller.lastText.current, "Envía el informe.", "the refusal keeps the text")
    }

    @MainActor
    func testAnIntentDictatesAndPastesLikeTheShortcut() async {
        let text = "Send the report."
        let harness = DictationControllerHarness(text: text)
        defer { harness.controller.cancel() }
        var leases = 0
        var owner = harness.dependencies
        owner.admission = DictationAdmission(
            acquire: { _ in leases += 1; return .success(DictationLease()) }, isEligible: { true })

        XCTAssertEqual(harness.controller.performIntent(.pasteLast, using: owner), .nothingToPaste)
        XCTAssertEqual(harness.controller.performIntent(.toggle, using: owner), .accepted)
        let heard = await TestPolling.until { harness.controller.partialText == text }
        XCTAssertTrue(heard)
        harness.now = harness.now.addingTimeInterval(1)
        XCTAssertEqual(harness.controller.performIntent(.toggle, using: owner), .accepted)
        let delivered = await TestPolling.until { harness.insertions == [text] }
        XCTAssertTrue(delivered)

        XCTAssertEqual(harness.controller.performIntent(.pasteLast, using: owner), .accepted)
        let pasted = await TestPolling.until { harness.insertions == [text, text] }
        XCTAssertTrue(pasted)
        XCTAssertGreaterThanOrEqual(leases, 4, "each start and paste asks first, then takes its own lease")
    }

    @MainActor
    func testTheAppRefusesAnIntentWhileAnOlderPortavozDictates() async throws {
        let name = "DictationIntentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: DictationController.defaultsKey)
        let feature = try DictationFeature(
            usesTemporaryStore: true, arguments: ["-seed-dictation-legacy-peer"], defaults: defaults)
        feature.start()
        let refused = await TestPolling.until { feature.unavailableMessage != nil }
        XCTAssertTrue(refused)

        XCTAssertEqual(feature.performDictationIntent(.toggle), .notOwner)
        XCTAssertEqual(feature.performDictationIntent(.pasteLast), .notOwner)
        XCTAssertEqual(feature.controller.phase, .idle)
    }
}
