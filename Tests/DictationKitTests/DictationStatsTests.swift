import DictationKit
import Foundation
import XCTest

final class DictationStatsTests: XCTestCase {
    func testWordsDaysAndTimeSavedAreCountedPlainly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(DictationStatsCalendar.wordCount("Send the report — on Friday, ¿vale?"), 6)
        XCTAssertEqual(DictationStatsCalendar.wordCount("  "), 0)
        XCTAssertEqual(DictationStatsCalendar.days(endingAt: now, count: 3, calendar: calendar),
                       ["2027-01-13", "2027-01-14", "2027-01-15"])
        XCTAssertEqual(
            DictationStatsTotals(dictations: 1, words: 80, spokenDuration: 30, notDelivered: 0).estimatedTimeSaved, 90)
        XCTAssertEqual(
            DictationStatsTotals(dictations: 1, words: 10, spokenDuration: 60, notDelivered: 0).estimatedTimeSaved, 0)
    }
}
