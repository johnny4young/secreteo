import Foundation
import SpeechCore

/// One finished dictation as the statistics see it: counts and time, never text.
public struct DictationStatsSample: Equatable, Sendable {
    public let id: DictationRecordID
    /// The local calendar day it started, `yyyy-MM-dd`.
    public let day: String
    public let words: Int
    public let spokenDuration: TimeInterval
    public let applicationName: String?
    public let delivered: Bool

    public init(
        id: DictationRecordID, day: String, words: Int, spokenDuration: TimeInterval,
        applicationName: String?, delivered: Bool
    ) {
        self.id = id
        self.day = day
        self.words = words
        self.spokenDuration = spokenDuration
        self.applicationName = applicationName
        self.delivered = delivered
    }

    public var isValid: Bool {
        DictationStatsCalendar.isDay(day) && words >= 0 && spokenDuration.isFinite && spokenDuration >= 0
            && (applicationName?.unicodeScalars.count ?? 0) <= DictationRecord.maximumLabelLength
    }
}

/// Totals for one day, or for a range when summed.
public struct DictationStatsTotals: Equatable, Sendable {
    public var dictations: Int
    public var words: Int
    public var spokenDuration: TimeInterval
    public var notDelivered: Int

    public static let zero = Self(dictations: 0, words: 0, spokenDuration: 0, notDelivered: 0)

    public init(dictations: Int, words: Int, spokenDuration: TimeInterval, notDelivered: Int) {
        self.dictations = dictations
        self.words = words
        self.spokenDuration = spokenDuration
        self.notDelivered = notDelivered
    }

    /// Typing the same words at 40 per minute, minus the time spent speaking.
    public var estimatedTimeSaved: TimeInterval {
        max(0, Double(words) / DictationStatsCalendar.typingWordsPerMinute * 60 - spokenDuration)
    }
}

public struct DictationStatsDay: Equatable, Sendable {
    public let day: String
    public let totals: DictationStatsTotals

    public init(day: String, totals: DictationStatsTotals) {
        self.day = day
        self.totals = totals
    }
}

public struct DictationStatsApplication: Equatable, Sendable {
    public let name: String
    public let dictations: Int
    public let words: Int

    public init(name: String, dictations: Int, words: Int) {
        self.name = name
        self.dictations = dictations
        self.words = words
    }
}

/// A range of days, oldest first with empty days filled, and the busiest apps.
public struct DictationStatsSummary: Equatable, Sendable {
    public let days: [DictationStatsDay]
    public let topApplications: [DictationStatsApplication]

    public init(days: [DictationStatsDay], topApplications: [DictationStatsApplication]) {
        self.days = days
        self.topApplications = topApplications
    }

    public var totals: DictationStatsTotals {
        days.reduce(into: .zero) { sum, day in
            sum.dictations += day.totals.dictations
            sum.words += day.totals.words
            sum.spokenDuration += day.totals.spokenDuration
            sum.notDelivered += day.totals.notDelivered
        }
    }
}

/// One segment of the per-app share bar; a nil name is every other app together.
public struct DictationApplicationShare: Equatable, Sendable {
    public let name: String?
    public let percent: Int

    public init(name: String?, percent: Int) {
        self.name = name
        self.percent = percent
    }
}

extension DictationStatsSummary {
    /// Each busiest app's share of the range's dictations, then every other app and the
    /// dictations without one. The percentages add up to 100; a share that rounds to nothing is left out.
    public func applicationShares(limit: Int = 4) -> [DictationApplicationShare] {
        let total = totals.dictations
        guard total > 0, limit > 0 else { return [] }
        let named = topApplications.filter { $0.dictations > 0 }.prefix(limit)
        var counts = named.map { min($0.dictations, total) }
        counts.append(max(0, total - counts.reduce(0, +)))
        var percents = counts.map { $0 * 100 / total }
        let remainders = counts.enumerated().sorted {
            let lhs = $0.element * 100 % total, rhs = $1.element * 100 % total
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }
        for index in remainders.prefix(max(0, 100 - percents.reduce(0, +))).map(\.offset) {
            percents[index] += 1
        }
        let names: [String?] = named.map(\.name) + [nil]
        return zip(names, percents).filter { $0.1 > 0 }.map { DictationApplicationShare(name: $0.0, percent: $0.1) }
    }
}

public enum DictationStatsCalendar {
    public static let retentionDays = 365
    public static let typingWordsPerMinute = 40.0
    public static let topApplicationCount = 5

    public static func day(of date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The `count` days ending with `date`'s day, oldest first.
    public static func days(endingAt date: Date, count: Int, calendar: Calendar) -> [String] {
        (0..<max(count, 0)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date).map { day(of: $0, calendar: calendar) }
        }
    }

    public static func isDay(_ value: String) -> Bool {
        value.count == 10 && value.enumerated().allSatisfy { index, character in
            [4, 7].contains(index) ? character == "-" : character.isASCII && character.isNumber
        }
    }

    /// Words as a person would count them: runs of letters or digits.
    public static func wordCount(_ text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }
}
