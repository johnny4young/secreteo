import Foundation
import SpeechCore

/// The loaded history as a day log: word matches grouped by local day, newest first,
/// then the rows found by meaning only, which are ranked and so keep no day.
public struct DictationDayLog: Equatable, Sendable {
    public enum Day: Equatable, Sendable {
        case today, yesterday, earlier
    }

    /// A row and its position in the loaded list, which names its controls.
    public struct Entry: Equatable, Identifiable, Sendable {
        public let index: Int
        public let record: DictationRecord
        public var id: DictationRecordID { record.id }
    }

    public struct Section: Equatable, Identifiable, Sendable {
        /// The first instant of the day in the calendar that grouped it.
        public let start: Date
        public let day: Day
        public let entries: [Entry]
        public var id: Date { start }
    }

    public let sections: [Section]
    public let meaning: [Entry]

    /// `meaningCount` rows at the end of `records` matched by meaning only.
    public init(records: [DictationRecord], meaningCount: Int = 0, now: Date, calendar: Calendar) {
        let wordCount = records.count - min(max(meaningCount, 0), records.count)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var sections: [Section] = []
        var start: Date?
        var entries: [Entry] = []
        func close() {
            guard let start, !entries.isEmpty else { return }
            let day: Day = start == today ? .today : start == yesterday ? .yesterday : .earlier
            sections.append(Section(start: start, day: day, entries: entries))
        }
        for (index, record) in records.prefix(wordCount).enumerated() {
            let day = calendar.startOfDay(for: record.createdAt)
            if day != start {
                close()
                start = day
                entries = []
            }
            entries.append(Entry(index: index, record: record))
        }
        close()
        self.sections = sections
        meaning = records.enumerated().dropFirst(wordCount).map { Entry(index: $0.offset, record: $0.element) }
    }
}
