import AppKit
import DictationKit
import SpeechCore
import XCTest

@testable import DictationSession

@MainActor
final class DictationHistoryRecordingTests: XCTestCase {
    func testAVerifiedDictationIsSavedWithItsDestinationAndThePanelSaysSo() async throws {
        let (controller, feature) = try makeFeature()
        await feature.history.load()
        await feature.history.update(isEnabled: true)

        try await dictate(controller, using: feature.makeDictationSessionDependencies())
        let saved = await eventually { feature.history.records.count == 1 }

        XCTAssertTrue(saved)
        let record = try XCTUnwrap(feature.history.records.first)
        XCTAssertEqual(record.text, "No borres estas notas.")
        XCTAssertEqual(record.delivery, .verified)
        XCTAssertEqual(record.applicationName, "Dictation test receiver")
        XCTAssertFalse(record.engine.isEmpty)
        XCTAssertEqual(controller.deliveryPrivacyLine, L10n.text("Saved to your dictation history."))
        controller.cancel()
    }

    func testNothingIsSavedWhenHistoryIsOffOrTheSessionIsPractice() async throws {
        let (controller, feature) = try makeFeature()
        await feature.history.load()
        try await dictate(controller, using: feature.makeDictationSessionDependencies())
        XCTAssertEqual(controller.deliveryPrivacyLine, L10n.text("Nothing was saved in Secreteo."))

        await feature.history.update(isEnabled: true)
        let holder = UUID()
        feature.practice.show(holder, isKey: true)
        defer { feature.practice.hide(holder) }
        let practice = feature.practice.route(feature.makeDictationSessionDependencies(), appIsActive: true)
        try await dictate(controller, using: practice)

        await feature.history.load()
        XCTAssertEqual(feature.history.records, [])
        controller.cancel()
    }

    func testStatisticsCountADictationWithTheHistoryOffButNeverPractice() async throws {
        let (controller, feature) = try makeFeature()
        await feature.history.load()
        await feature.stats.update(isEnabled: true)
        let dependencies = feature.makeDictationSessionDependencies()
        // The session clock may be a fixture; count on the day it reports.
        let day = [DictationStatsCalendar.day(of: dependencies.now(), calendar: .current)]

        try await dictate(controller, using: dependencies)
        var totals = DictationStatsTotals.zero
        for _ in 0..<200 where totals.dictations == 0 {
            totals = try await feature.dictationStore.dictationStatsSummary(days: day).totals
            try await Task.sleep(for: .milliseconds(10))
        }
        let apps = try await feature.dictationStore.dictationStatsSummary(days: day).topApplications
        XCTAssertEqual(totals.dictations, 1)
        XCTAssertEqual(totals.words, 4)
        XCTAssertEqual(apps.first?.name, "Dictation test receiver")
        XCTAssertEqual(feature.history.records, [], "statistics never save the text")

        let holder = UUID()
        feature.practice.show(holder, isKey: true)
        defer { feature.practice.hide(holder) }
        let practice = feature.practice.route(feature.makeDictationSessionDependencies(), appIsActive: true)
        try await dictate(controller, using: practice)
        try await Task.sleep(for: .milliseconds(200))
        let afterPractice = try await feature.dictationStore.dictationStatsSummary(days: day).totals
        XCTAssertEqual(afterPractice.dictations, 1, "practice is never counted")
        controller.cancel()
    }

    func testDeletingEverythingWhileADictationFinishesKeepsItOut() async throws {
        let (_, feature) = try makeFeature()
        let history = feature.history
        await history.load()
        await history.update(isEnabled: true)
        let writer = try XCTUnwrap(history.admit())

        await history.deleteAll()
        let completed = await writer(record())
        await history.load()

        XCTAssertTrue(completed, "A refused write is consent working, not a failure")
        XCTAssertEqual(history.records, [])
        XCTAssertNotNil(history.admit(), "History stays on after deleting its contents")
    }

    func testSecureCancelledAndEmptyDeliveriesAreNeverSaved() async {
        XCTAssertNil(DictationHistorySession.delivery(for: .refused(.secureField)))
        XCTAssertNil(DictationHistorySession.delivery(for: .refused(.cancelled)))
        XCTAssertNil(DictationHistorySession.delivery(for: .refused(.emptyText)))
        XCTAssertEqual(DictationHistorySession.delivery(for: .refused(.targetChanged)), .notDelivered)
        XCTAssertEqual(DictationHistorySession.delivery(for: .dispatched), .dispatched)
        XCTAssertEqual(DictationHistorySession.delivery(for: .verified), .verified)
    }

    private func makeFeature() throws -> (DictationController, DictationFeature) {
        let suite = "dictation-history-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DictationController.defaultsKey)
        let feature = try DictationFeature(
            usesTemporaryStore: true,
            arguments: ["-use-temp-store", "-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-verified"],
            defaults: defaults)
        return (DictationController(presentsPanel: false), feature)
    }

    private func dictate(_ controller: DictationController, using dependencies: DictationSessionDependencies)
        async throws {
        let dependencies = dependencies.skippingStopTail()
        controller.toggle(using: dependencies)
        let listening = await eventually { controller.partialText == "No borres estas notas." }
        XCTAssertTrue(listening)
        controller.toggle(using: dependencies)
        let delivered = await eventually { controller.phase == .verified(4) }
        XCTAssertTrue(delivered)
        _ = await eventually { controller.history?.state != .saving }
    }

    private func record() -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: Date(), duration: 1, text: "Hola", originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: nil,
            applicationBundleID: nil, delivery: .verified)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        return await TestPolling.until(condition)
    }
}
