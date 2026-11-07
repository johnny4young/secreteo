import DictationKit
import DictationStore
import Foundation
import SpeechCore
import XCTest

@testable import DictationSession

final class DictationIntentTests: XCTestCase {
    @MainActor
    func testDictationRequestsAreAnsweredNowAndNeverReplayed() async throws {
        let previous = SecreteoAppIntentBridge.dictationHandler
        defer { SecreteoAppIntentBridge.dictationHandler = previous }
        SecreteoAppIntentBridge.dictationHandler = nil
        XCTAssertEqual(SecreteoAppIntentBridge.requestDictation(.toggle), .notReady, "nobody listening yet")

        var handled: [SecreteoAppIntentBridge.DictationRequest] = []
        SecreteoAppIntentBridge.dictationHandler = { request in
            handled.append(request)
            return request == .pasteLast ? .nothingToPaste : .accepted
        }
        XCTAssertTrue(handled.isEmpty, "a request made before launch is not replayed")

        _ = try await DictateIntent().perform()
        do {
            _ = try await PasteLastDictationIntent().perform()
            XCTFail("an empty paste must say so")
        } catch {
            XCTAssertEqual(error as? SecreteoDictationIntentError, .nothingToPaste)
        }
        XCTAssertEqual(handled, [.toggle, .pasteLast])
    }

    @MainActor
    func testWithoutDictationTheActionsSayItIsUnavailable() async {
        let previous = SecreteoAppIntentBridge.dictationHandler
        defer { SecreteoAppIntentBridge.dictationHandler = previous }
        DictationFeature.answerIntentsWithoutDictation()
        XCTAssertEqual(SecreteoAppIntentBridge.requestDictation(.toggle), .unavailable)
        do {
            _ = try await DictateIntent().perform()
            XCTFail("a build without dictation must say so")
        } catch {
            XCTAssertEqual(error as? SecreteoDictationIntentError, .unavailable)
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
        XCTAssertEqual(outcome(.toggle, phase: .recovery(.cancelled)), .busy)
        XCTAssertEqual(outcome(.pasteLast, phase: .recovery(.cancelled)), .accepted, "like the menu's Paste last")
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
    func testAnIntentDictatesAndPastesLikeTheShortcutAfterAskingFirst() async {
        func run(_ act: (DictationControllerHarness, DictationSessionDependencies,
                         SecreteoAppIntentBridge.DictationRequest) -> Void) async -> (Int, [String]) {
            let text = "Send the report."
            let harness = DictationControllerHarness(text: text)
            defer { harness.controller.cancel() }
            var asked = 0
            var owner = harness.dependencies
            owner.admission = DictationAdmission(
                acquire: { _ in asked += 1; return .success(DictationLease()) }, isEligible: { true })
            act(harness, owner, .toggle)
            let heard = await TestPolling.until { harness.controller.partialText == text }
            XCTAssertTrue(heard)
            harness.now = harness.now.addingTimeInterval(1)
            act(harness, owner, .toggle)
            let delivered = await TestPolling.until { harness.insertions == [text] }
            XCTAssertTrue(delivered)
            act(harness, owner, .pasteLast)
            _ = await TestPolling.until { harness.insertions == [text, text] }
            return (asked, harness.insertions)
        }
        let shortcut = await run { harness, dependencies, request in
            switch request {
            case .toggle: harness.controller.toggle(using: dependencies)
            case .pasteLast: harness.controller.pasteLastDictation(using: dependencies)
            }
        }
        let intent = await run { harness, dependencies, request in
            XCTAssertEqual(harness.controller.performIntent(request, using: dependencies), .accepted)
        }
        XCTAssertEqual(intent.1, shortcut.1)
        XCTAssertEqual(intent.0, shortcut.0 + 2, "the start and the paste each ask before acting; finishing does not")
    }

    @MainActor
    func testAPasteThatSendsNothingSaysWhy() {
        let harness = DictationControllerHarness(text: "Send the report.")
        defer { harness.controller.cancel() }
        harness.controller.lastText.remember("Envía el informe.")
        var noAccessibility = harness.dependencies
        noAccessibility.admission = .open
        noAccessibility.canInsert = { false }

        XCTAssertEqual(harness.controller.performIntent(.pasteLast, using: noAccessibility), .needsAccessibility)
        XCTAssertTrue(harness.insertions.isEmpty)
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

    @MainActor
    func testOpenDictationsRoutesWithItsSearchEvenBeforeTheAppCanShowIt() async throws {
        let previous = SecreteoAppIntentBridge.navigationHandler
        defer { SecreteoAppIntentBridge.navigationHandler = previous }
        SecreteoAppIntentBridge.navigationHandler = nil
        _ = SecreteoAppIntentBridge.consumeNavigationRequest()

        let intent = OpenDictationsIntent()
        intent.search = "  informe  "
        _ = try await intent.perform()

        var shown: [SecreteoAppIntentBridge.NavigationRequest] = []
        SecreteoAppIntentBridge.navigationHandler = {
            SecreteoAppIntentBridge.consumeNavigationRequest().map { shown.append($0) }
        }
        XCTAssertEqual(shown, [.dictations("informe")], "a request made while opening is shown once the app can")
        XCTAssertNil(SecreteoAppIntentBridge.consumeNavigationRequest())
    }

    func testSearchReadsOnlyWhileTheHistoryIsSharedWithAgentsAndShortcuts() async throws {
        let store = try DictationStore.inMemory()
        let now = Date()
        let policy = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, exposesToAgents: false, at: now)
        for (offset, text) in ["Send the report on Friday.", "No borres estas notas."].enumerated() {
            _ = try await store.recordDictation(
                DictationRecord(
                    id: DictationRecordID(), createdAt: now.addingTimeInterval(Double(offset)), duration: 1,
                    text: text, originalText: nil, mode: .literal, language: nil, engine: "parakeet",
                    applicationName: "Slack", applicationBundleID: nil, delivery: .verified),
                admittedGeneration: policy.generation, at: now)
        }
        let reader = AppDictationIntentReader(store: store)

        do {
            _ = try await SecreteoDictationSearchAction.search("report", limit: 10, reader: reader)
            XCTFail("an unshared history returns nothing")
        } catch {
            XCTAssertEqual(error as? SecreteoDictationIntentError, .notShared)
        }

        _ = try await store.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, exposesToAgents: true, at: now)
        let found = try await SecreteoDictationSearchAction.search("  report ", limit: 10, reader: reader)
        let newest = try await SecreteoDictationSearchAction.search("", limit: 1, reader: reader)
        XCTAssertEqual(found, ["Send the report on Friday."])
        XCTAssertEqual(newest, ["No borres estas notas."])
    }

    @MainActor
    func testASearchFromAShortcutReplacesOtherHistoryFilters() async throws {
        let model = DictationHistoryModel(store: try DictationStore.inMemory())
        await model.apply(DictationRecordFilter(applicationName: "Slack"))
        model.show(search: "report")
        XCTAssertEqual(model.filter, DictationRecordFilter(query: "report"))
    }

    @MainActor
    func testOpenDictationsSearchesAClosedOrAnAlreadyLoadedHistory() async throws {
        let previous = SecreteoAppIntentBridge.navigationHandler
        defer { SecreteoAppIntentBridge.navigationHandler = previous }
        let name = "DictationIntentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let feature = try DictationFeature(
            usesTemporaryStore: true, arguments: ["-seed-dictation-history", "-seed-dictation-history-records"],
            defaults: defaults)
        var opened = 0
        feature.installDictationNavigation { opened += 1 }

        SecreteoAppIntentBridge.requestNavigation(.dictations("informe"))
        XCTAssertEqual(feature.history.filter, DictationRecordFilter(query: "informe"), "searched when it loads")
        XCTAssertEqual(opened, 1)

        feature.history.show(search: "")
        await feature.loadDictationHistory()
        XCTAssertEqual(feature.history.records.count, 2)
        SecreteoAppIntentBridge.requestNavigation(.dictations("report"))
        let reloaded = await TestPolling.until {
            feature.history.records.map(\.text) == ["Send the report on Friday."]
        }
        XCTAssertTrue(reloaded, "an open window reloads with the new search")
        XCTAssertEqual(opened, 2)
    }
}
