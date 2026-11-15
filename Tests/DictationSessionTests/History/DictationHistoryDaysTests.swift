import DictationKit
import Foundation
import SpeechCore
import XCTest

@testable import DictationSession

@MainActor
final class DictationHistoryDaysTests: XCTestCase {
    private final class Clock {
        var now: Date
        var calendar: Calendar
        init(now: Date, calendar: Calendar) {
            self.now = now
            self.calendar = calendar
        }
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func record(at date: Date, delivery: DictationRecordDelivery = .verified) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: date, duration: 1, text: "Send the report.", originalText: nil,
            mode: .polish, language: nil, engine: "parakeet", applicationName: "Notes", applicationBundleID: nil,
            delivery: delivery)
    }

    func testTodayBecomesYesterdayOnlyWhenTheDayIsReadAgain() throws {
        let bogota = calendar("America/Bogota")
        let evening = try XCTUnwrap(bogota.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 23)))
        let clock = Clock(now: evening, calendar: bogota)
        let days = DictationHistoryDays(clock: { clock.now }, calendar: { clock.calendar })
        let records = [record(at: evening.addingTimeInterval(-60))]

        XCTAssertEqual(days.log(records: records, meaningCount: 0).sections.map(\.day), [.today])

        clock.now = evening.addingTimeInterval(2 * 3_600)
        XCTAssertEqual(days.log(records: records, meaningCount: 0).sections.map(\.day), [.today],
                       "the clock is read when the system announces a change, not on every draw")
        days.refresh()
        XCTAssertEqual(days.log(records: records, meaningCount: 0).sections.map(\.day), [.yesterday])

        clock.calendar = calendar("Pacific/Honolulu")
        days.refresh()
        XCTAssertEqual(days.log(records: records, meaningCount: 0).sections.map(\.day), [.today],
                       "a new time zone moves the day line")
    }

    func testTheSameRowsAreGroupedOnce() throws {
        let utc = calendar("UTC")
        let noon = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12)))
        let days = DictationHistoryDays(clock: { noon }, calendar: { utc })
        var records = [record(at: noon), record(at: noon.addingTimeInterval(-86_400))]

        let first = days.log(records: records, meaningCount: 0)
        XCTAssertEqual(days.log(records: records, meaningCount: 0), first)
        days.refresh()
        _ = days.log(records: records, meaningCount: 0)
        XCTAssertEqual(days.builds, 1, "a redraw or a refresh within the day groups nothing again")

        XCTAssertEqual(days.log(records: records, meaningCount: 1).meaning.count, 1)
        records[0] = record(at: noon, delivery: .notDelivered)
        XCTAssertEqual(days.log(records: records, meaningCount: 1).sections.first?.entries.first?.record.delivery,
                       .notDelivered, "a row updated in place is not served from the old grouping")
        XCTAssertEqual(days.builds, 3)
    }

    func testADeliveredRowReadsInsertedWhateverItsMode() {
        XCTAssertEqual(DictationHistoryFormat.face(for: .verified), .inserted)
        XCTAssertEqual(DictationHistoryFormat.face(for: .dispatched), .sent)
        XCTAssertEqual(DictationHistoryFormat.face(for: .notDelivered), .notSent)
        XCTAssertEqual(SecreteoGlyphFace.inserted.accessibilityName, "Inserted")
    }

    func testTimesFollowTheSystemHourCycleAndWordsTheirNumber() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let afternoon = Date(timeIntervalSince1970: 14 * 3_600 + 5 * 60)

        let twelve = DictationHistoryFormat.time(afternoon, locale: Locale(identifier: "en_US"), timeZone: utc)
        let twentyFour = DictationHistoryFormat.time(
            afternoon, locale: Locale(identifier: "en_US@hours=h23"), timeZone: utc)
        XCTAssertTrue(twelve.hasPrefix("2:05"), twelve)
        XCTAssertEqual(twentyFour, "14:05")

        XCTAssertEqual(DictationHistoryFormat.wordsNoun(1), "word")
        XCTAssertEqual(DictationHistoryFormat.wordsNoun(2), "words")
        XCTAssertEqual(DictationHistoryFormat.words(1), "1 word")
        XCTAssertEqual(DictationHistoryFormat.words(0), "0 words")
    }
}
