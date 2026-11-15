import DictationKit
import Foundation
import Observation

/// The statistics consent and the summary the Dictations page shows.
@MainActor
@Observable
final class DictationStatsModel {
    static let ranges = [7, 30]

    private(set) var isEnabled = false
    private(set) var range = 7
    private(set) var summary = DictationStatsSummary(days: [], topApplications: [])
    /// Always the last 7 days, for the menu; `summary` follows the chosen range.
    private(set) var week = DictationStatsSummary(days: [], topApplications: [])
    private(set) var failure: String?
    @ObservationIgnored private let store: any DictationStatsStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let pendingWrites: DictationPendingWrites?

    init(
        store: any DictationStatsStore, now: @escaping @Sendable () -> Date = Date.init,
        pendingWrites: DictationPendingWrites? = nil
    ) {
        self.store = store
        self.now = now
        self.pendingWrites = pendingWrites
    }

    func load() async {
        do {
            isEnabled = try await LoadDictationStatsConsent(store: store).execute(())
            try await refresh()
            failure = nil
        } catch {
            failure = L10n.text("Dictation statistics could not be loaded.")
        }
    }

    func update(isEnabled: Bool) async {
        do {
            self.isEnabled = try await UpdateDictationStatsConsent(store: store).execute(isEnabled)
            try await refresh()
            failure = nil
        } catch {
            failure = L10n.text("The statistics setting could not be saved.")
        }
    }

    func show(range: Int) async {
        guard Self.ranges.contains(range), range != self.range else { return }
        self.range = range
        try? await refresh()
    }

    func deleteAll() async {
        do {
            try await DeleteDictationStats(store: store).execute(())
            try await refresh()
            failure = nil
        } catch {
            failure = L10n.text("The statistics could not be deleted.")
        }
    }

    func record(_ sample: DictationStatsSample) {
        // The store still checks consent; this only spares the database while statistics are off.
        guard isEnabled else { return }
        let store = store
        let now = now
        let finished = pendingWrites?.begin()
        Task { [weak self] in
            defer { finished?() }
            _ = try? await RecordDictationStats(store: store, now: now).execute(sample)
            try? await self?.refresh()
        }
    }

    /// Today's totals, or nil once the loaded week ends on an earlier day.
    var today: DictationStatsTotals? {
        guard let last = week.days.last, last.day == DictationStatsCalendar.day(of: now(), calendar: .current)
        else { return nil }
        return last.totals
    }

    /// The menu asks when it opens, so a week loaded yesterday does not pass for today.
    func refreshWeek() async {
        guard isEnabled, today == nil else { return }
        try? await refresh()
    }

    private func refresh() async throws {
        // Read once: a range change during the await must not turn this refresh's week into 30 days.
        let range = range
        let load = LoadDictationStatsSummary(store: store, now: now)
        let loaded = try await load.execute(range)
        let week = range == 7 ? loaded : try await load.execute(7)
        if range == self.range { summary = loaded }
        self.week = week
    }
}
