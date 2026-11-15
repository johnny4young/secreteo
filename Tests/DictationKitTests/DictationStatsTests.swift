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

    func testAppSharesAddUpToAHundredWithTheRestLast() {
        func summary(_ dictations: Int, _ apps: [(String, Int)]) -> DictationStatsSummary {
            DictationStatsSummary(
                days: [DictationStatsDay(
                    day: "2027-01-15",
                    totals: .init(dictations: dictations, words: 0, spokenDuration: 0, notDelivered: 0))],
                topApplications: apps.map { DictationStatsApplication(name: $0.0, dictations: $0.1, words: 0) })
        }
        func shares(_ summary: DictationStatsSummary) -> [String] {
            summary.applicationShares().map { "\($0.name ?? "rest") \($0.percent)" }
        }

        XCTAssertEqual(shares(summary(0, [])), [])
        XCTAssertEqual(shares(summary(4, [("Slack", 2), ("Mail", 1), ("Notes", 1)])),
                       ["Slack 50", "Mail 25", "Notes 25"])
        XCTAssertEqual(shares(summary(3, [("Slack", 1), ("Mail", 1), ("Notes", 1)])),
                       ["Slack 34", "Mail 33", "Notes 33"], "rounding still adds up to 100")
        XCTAssertEqual(shares(summary(100, [("Mail", 41), ("Slack", 27), ("Xcode", 18), ("Notes", 14)])),
                       ["Mail 41", "Slack 27", "Xcode 18", "Notes 14"], "a fourth app that is all the rest keeps its name")
        XCTAssertEqual(shares(summary(100, [("Mail", 40), ("Slack", 20), ("Xcode", 10), ("Notes", 8), ("Zed", 7)])),
                       ["Mail 40", "Slack 20", "Xcode 10", "rest 30"])
        XCTAssertEqual(shares(summary(10, [("Mail", 4)])), ["Mail 40", "rest 60"], "dictations without an app are the rest")
        XCTAssertEqual(shares(summary(1000, [("Mail", 998), ("Slack", 1)])), ["Mail 100"])
    }
}
