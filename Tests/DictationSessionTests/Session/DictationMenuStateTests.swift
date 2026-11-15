import DictationKit
import Foundation
import Testing

@testable import DictationSession

struct DictationMenuStateTests {
    @Test(arguments: [
        (true, true, true, false, DictationMenuState.ready),
        (false, true, true, false, .live),
        (true, false, false, false, .setUp),
        (true, false, true, true, .standingBy),
        // On but preparing, taking over or blocked by an older peer: never "off".
        (true, false, true, false, .notReady)
    ])
    func eachOwnershipStateHasItsHeader(
        _ idle: Bool, _ canDictate: Bool, _ enabled: Bool, _ canTake: Bool, _ expected: DictationMenuState
    ) {
        let state = DictationFeature.menuState(
            isIdle: idle, canDictate: canDictate, isEnabled: enabled, canTakeOwnership: canTake)
        #expect(state == expected)
    }

    @Test @MainActor
    func aRangeChangeDuringARefreshKeepsTheWeekAtSevenDays() async throws {
        let store = SuspendingStatsStore()
        let model = DictationStatsModel(store: store)
        await model.load()
        await model.show(range: 30)
        #expect(model.week.days.count == 7)

        store.suspendNextThirtyDayLoad()
        let refresh = Task { await model.update(isEnabled: true) }
        try #require(await store.waitUntilSuspended())
        await model.show(range: 7)
        store.resume()
        await refresh.value

        #expect(model.week.days.count == 7)
        #expect(model.summary.days.count == 7)
    }
}

@MainActor
private final class SuspendingStatsStore: DictationStatsStore {
    private var held: CheckedContinuation<Void, Never>?
    private var suspendThirty = false
    private var suspended = false

    func suspendNextThirtyDayLoad() { suspendThirty = true }

    func waitUntilSuspended() async -> Bool {
        for _ in 0..<200 where !suspended { try? await Task.sleep(for: .milliseconds(5)) }
        return suspended
    }

    func resume() {
        held?.resume()
        held = nil
    }

    nonisolated func dictationStatsEnabled() async throws -> Bool { true }
    nonisolated func setDictationStatsEnabled(_ isEnabled: Bool) async throws {}
    nonisolated func recordDictationStats(_ sample: DictationStatsSample, at now: Date, calendar: Calendar)
        async throws -> Bool { true }
    nonisolated func deleteDictationStats() async throws {}

    nonisolated func dictationStatsSummary(days: [String]) async throws -> DictationStatsSummary {
        await hold(if: days.count == 30)
        return DictationStatsSummary(
            days: days.map { DictationStatsDay(day: $0, totals: .zero) }, topApplications: [])
    }

    private func hold(if thirty: Bool) async {
        guard thirty, suspendThirty else { return }
        suspendThirty = false
        suspended = true
        await withCheckedContinuation { held = $0 }
    }
}
