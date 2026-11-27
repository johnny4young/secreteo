import DictationKit
import DictationStore
import SpeechCore
import Synchronization
import XCTest

@testable import DictationSession

@MainActor
final class DictationMemoryPressureTests: XCTestCase {
    func testTheEndRunsOnceAfterPressureThatGaveSomethingBack() {
        let pressure = DictationMemoryPressure()
        let ends = EndLog()
        pressure.releases { true }
        pressure.whenItEnds { ends.record(stillActive: pressure.isActive) }

        pressure.changed(isActive: false)
        XCTAssertTrue(ends.reports.isEmpty, "no pressure has ended yet")

        pressure.changed(isActive: true)
        pressure.changed(isActive: true)
        XCTAssertTrue(ends.reports.isEmpty)

        pressure.changed(isActive: false)
        pressure.changed(isActive: false)
        XCTAssertEqual(ends.reports, [false], "once, and after the flag is down so a prewarm may run")
    }

    func testPressureThatGaveNothingBackRestoresNothing() {
        let pressure = DictationMemoryPressure()
        let ends = EndLog()
        pressure.releases { false }
        pressure.whenItEnds { ends.record(stillActive: pressure.isActive) }

        pressure.changed(isActive: true)
        pressure.changed(isActive: false)

        XCTAssertTrue(ends.reports.isEmpty, "a model that idled out stays out")
    }

    func testEachEpisodeAnswersForItself() {
        let pressure = DictationMemoryPressure()
        let ends = EndLog()
        let gives = GiveBack()
        pressure.releases { gives.next() }
        pressure.whenItEnds { ends.record(stillActive: pressure.isActive) }

        gives.answers = [true]
        pressure.changed(isActive: true)
        pressure.changed(isActive: false)
        gives.answers = [false]
        pressure.changed(isActive: true)
        pressure.changed(isActive: false)

        XCTAssertEqual(ends.reports, [false], "the second episode gave nothing back")
    }

    func testOnPressureRunsWithoutTriggeringPrewarmRestoreWhenNoModelWasHeld() {
        let pressure = DictationMemoryPressure()
        let ends = EndLog()
        var evicted = 0
        pressure.releases { false }
        pressure.onPressure { evicted += 1 }
        pressure.whenItEnds { ends.record(stillActive: pressure.isActive) }

        pressure.changed(isActive: true)
        pressure.changed(isActive: false)

        XCTAssertEqual(evicted, 1)
        XCTAssertTrue(ends.reports.isEmpty, "cache eviction alone must not trigger a speech model prewarm")
    }

    func testMemoryPressureEvictsSemanticLibraryAndNextSearchReloadsIt() async throws {
        let suite = "DictationMemoryPressureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let feature = try DictationFeature(
            usesTemporaryStore: true, arguments: [], defaults: defaults,
            environment: .disposable(permissionsAreMissing: false))
        let semantic = try XCTUnwrap(feature.history.semantic)
        let policy = try await feature.dictationStore.setDictationHistoryPolicy(
            isEnabled: true, keepsOriginal: false, retentionDays: 30, exposesToAgents: false, at: Date())
        let record = DictationRecord(
            id: DictationRecordID(), createdAt: Date(), duration: 1,
            text: "Send the weekly report on Friday", originalText: nil,
            mode: .literal, language: nil, engine: "parakeet", applicationName: "Notes",
            applicationBundleID: nil, delivery: .verified)
        let saved = try await feature.dictationStore.recordDictation(
            record, admittedGeneration: policy.generation, at: Date())
        XCTAssertEqual(saved, .saved)
        await semantic.index(record)

        let first = try await semantic.ranking(for: "summary", matching: .all)
        XCTAssertEqual(first, [record.id])
        let cachedBefore = await semantic.hasCachedLibrary
        XCTAssertTrue(cachedBefore)

        feature.memoryPressureChanged(isUnderPressure: true)
        var evicted = false
        for _ in 0..<200 {
            if await !semantic.hasCachedLibrary {
                evicted = true
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(evicted, "memory pressure must drop the cached embedding library")

        let reloaded = try await semantic.ranking(for: "summary", matching: .all)
        XCTAssertEqual(reloaded, [record.id])
        let cachedAfter = await semantic.hasCachedLibrary
        XCTAssertTrue(cachedAfter)
    }

    func testSpeechDetectorReleaseRunsExactlyOnceOnFinishOrDeinit() {
        let count = Mutex(0)
        var token: SpeechDetectorRelease? = SpeechDetectorRelease { count.withLock { $0 += 1 } }
        token?.finish()
        token?.finish()
        token = nil
        XCTAssertEqual(count.withLock { $0 }, 1)

        var abandoned: SpeechDetectorRelease? = SpeechDetectorRelease { count.withLock { $0 += 1 } }
        XCTAssertNotNil(abandoned)
        abandoned = nil
        XCTAssertEqual(count.withLock { $0 }, 2, "dropping an unfinished token must still release the warm slot")
    }
}

@MainActor
private final class GiveBack {
    var answers: [Bool] = []

    func next() -> Bool {
        answers.isEmpty ? false : answers.removeFirst()
    }
}

@MainActor
private final class EndLog {
    private(set) var reports: [Bool] = []

    func record(stillActive: Bool) {
        reports.append(stillActive)
    }
}
