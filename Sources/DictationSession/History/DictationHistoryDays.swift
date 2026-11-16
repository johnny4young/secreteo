import DictationKit
import Foundation
import Observation

/// The day the log is read against, and the last grouping. The clock is read only
/// when the system says the day, the time zone or the clock changed.
@MainActor
@Observable
final class DictationHistoryDays {
    private(set) var now: Date
    private(set) var calendar: Calendar
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let currentCalendar: () -> Calendar
    @ObservationIgnored private var cached: (key: Key, log: DictationDayLog)?
    /// How many times the rows were grouped, for tests.
    @ObservationIgnored private(set) var builds = 0

    private struct Key: Equatable {
        let records: [DictationRecord]
        let meaningCount: Int
        let today: Date
        let timeZone: TimeZone
    }

    init(clock: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current }) {
        self.clock = clock
        currentCalendar = calendar
        now = clock()
        self.calendar = calendar()
    }

    func refresh() {
        calendar = currentCalendar()
        now = clock()
    }

    /// Typing in the search field redraws the page with the same rows; they are grouped once.
    func log(records: [DictationRecord], meaningCount: Int) -> DictationDayLog {
        let key = Key(
            records: records, meaningCount: meaningCount, today: calendar.startOfDay(for: now),
            timeZone: calendar.timeZone)
        if let cached, cached.key == key { return cached.log }
        builds += 1
        let log = DictationDayLog(records: records, meaningCount: meaningCount, now: now, calendar: calendar)
        cached = (key, log)
        return log
    }
}
