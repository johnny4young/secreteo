import DictationKit
import Foundation
import SpeechCore
import XCTest

final class DictationDayLogTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func record(_ text: String, at date: Date) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: date, duration: 1, text: text, originalText: nil, mode: .literal,
            language: nil, engine: "parakeet", applicationName: "Notes", applicationBundleID: nil,
            delivery: .verified)
    }

    func testRecordsAcrossMidnightFallOnTheirOwnLocalDay() {
        let records = [
            record("after midnight", at: date(11, 0, 1)),
            record("before midnight", at: date(10, 23, 59)),
            record("two days ago", at: date(9, 8, 0)),
            record("last week", at: date(4, 8, 0))
        ]

        let log = DictationDayLog(records: records, now: date(11, 9, 41), calendar: calendar)

        XCTAssertEqual(log.sections.map(\.day), [.today, .yesterday, .earlier, .earlier])
        XCTAssertEqual(log.sections.map(\.start), [date(11, 0, 0), date(10, 0, 0), date(9, 0, 0), date(4, 0, 0)])
        XCTAssertEqual(log.sections.map { $0.entries.map(\.record.text) },
                       [["after midnight"], ["before midnight"], ["two days ago"], ["last week"]])
        XCTAssertEqual(log.meaning, [])

        // The same instants seen from Madrid are all on the 11th and the 10th.
        var madrid = calendar
        madrid.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let moved = DictationDayLog(records: Array(records.prefix(2)), now: date(11, 9, 41), calendar: madrid)
        XCTAssertEqual(moved.sections.map(\.entries.count), [2])
    }

    func testAnOlderPageContinuesTheLastDayAndKeepsEveryIndex() {
        let first = [record("a", at: date(11, 9, 0)), record("b", at: date(10, 18, 0))]
        let older = [record("c", at: date(10, 7, 0)), record("d", at: date(8, 7, 0))]

        let page = DictationDayLog(records: first, now: date(11, 9, 41), calendar: calendar)
        let both = DictationDayLog(records: first + older, now: date(11, 9, 41), calendar: calendar)

        XCTAssertEqual(page.sections.map { $0.entries.map(\.index) }, [[0], [1]])
        XCTAssertEqual(both.sections.map { $0.entries.map(\.index) }, [[0], [1, 2], [3]])
        XCTAssertEqual(Array(both.sections.prefix(2).map(\.id)), page.sections.map(\.id),
                       "loaded days keep their identity when older rows arrive")
    }

    func testMeaningRowsStayOutOfTheDaysAndKeepTheirRank() {
        let records = [
            record("word match", at: date(10, 9, 0)),
            record("closest in meaning", at: date(3, 9, 0)),
            record("also close", at: date(11, 9, 0))
        ]

        let log = DictationDayLog(records: records, meaningCount: 2, now: date(11, 9, 41), calendar: calendar)

        XCTAssertEqual(log.sections.map { $0.entries.map(\.record.text) }, [["word match"]])
        XCTAssertEqual(log.meaning.map(\.record.text), ["closest in meaning", "also close"])
        XCTAssertEqual(log.meaning.map(\.index), [1, 2])

        let onlyMeaning = DictationDayLog(records: records, meaningCount: 9, now: date(11, 9, 41), calendar: calendar)
        XCTAssertEqual(onlyMeaning.sections, [])
        XCTAssertEqual(onlyMeaning.meaning.count, 3)
    }
}
