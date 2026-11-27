import DictationKit
import DictationStore
import Foundation
import SpeechCore
import Synchronization
import XCTest

@testable import DictationSession

@MainActor
final class DictationMenuTests: XCTestCase {
    private func makeDefaults(enabled: Bool = true) -> UserDefaults {
        let name = "DictationMenuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        defaults.set(enabled, forKey: DictationController.defaultsKey)
        return defaults
    }

    private func makeFeature(_ defaults: UserDefaults, arguments: [String] = []) throws -> DictationFeature {
        try DictationFeature(usesTemporaryStore: true, arguments: arguments, defaults: defaults)
    }

    func testTheHeaderSaysWhoOwnsDictation() async throws {
        let off = try makeFeature(makeDefaults(enabled: false))
        off.start()
        XCTAssertEqual(off.menuState, .setUp)
        XCTAssertEqual(off.menuTitle, "Dictation is off")
        XCTAssertNil(off.menuDetail)

        let defaults = makeDefaults()
        defaults.set(LiveSpeechSelection.parakeet.rawValue, forKey: LiveSpeechSelection.dictationKey)
        let owner = try makeFeature(defaults)
        owner.start()
        XCTAssertEqual(owner.menuState, .ready)
        XCTAssertEqual(owner.menuTitle, "Ready")
        XCTAssertEqual(owner.menuDetail, "Parakeet · On this Mac")

        let other = try makeFeature(makeDefaults(), arguments: ["-seed-dictation-no-owner"])
        other.start()
        let standsBy = await TestPolling.until { other.menuState == .standingBy }
        XCTAssertTrue(standsBy)
        XCTAssertEqual(other.menuTitle, "Standing by")
        XCTAssertEqual(other.menuDetail, "Another app handles dictation on this Mac")
    }

    func testTheLastDictationLeavesTheMenuWithPasteLast() throws {
        let feature = try makeFeature(makeDefaults())
        feature.controller.lastText.remember("Send the report.", app: "Mail")
        XCTAssertNil(feature.lastDictation, "Not started, so not the owner")

        feature.start()
        XCTAssertEqual(feature.lastDictation?.text, "Send the report.")
        XCTAssertEqual(feature.lastDictation?.app, "Mail")

        feature.controller.lastText.clear()
        XCTAssertNil(feature.lastDictation)
    }

    func testTheKeyCapsAreTheRealTriggers() throws {
        let defaults = makeDefaults()
        let feature = try makeFeature(defaults)
        feature.start()
        XCTAssertEqual(feature.holdKeyLabel, "fn", "Holding Fn is the default")
        XCTAssertEqual(feature.dictationShortcutLabel, HotkeySetting.default.label)
        XCTAssertNil(feature.pasteLastShortcutLabel)
        XCTAssertNil(feature.rewriteSelectionShortcutLabel)

        defaults.set(ModifierKeySetting.off.rawValue, forKey: ModifierKeySetting.defaultsKey)
        XCTAssertNil(feature.holdKeyLabel)
        defaults.set(ModifierKeySetting.function.rawValue, forKey: ModifierKeySetting.defaultsKey)
        defaults.set(true, forKey: PasteLastShortcut.defaultsKey)
        defaults.set(true, forKey: RewriteSelectionShortcut.defaultsKey)
        XCTAssertEqual(feature.holdKeyLabel, "fn")
        XCTAssertEqual(feature.pasteLastShortcutLabel, "⌃⌥⌘V")
        XCTAssertEqual(feature.rewriteSelectionShortcutLabel, "⌃⌥⌘R")
    }

    func testTheEntryKeepsItsAppAndTimeOnlyWhileTheTextLives() {
        let clock = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        let lastText = DictationLastText(now: { clock.withLock { $0 } }, observesSystem: false, waitForExpiry: { _ in })
        lastText.remember("Synthetic words", app: "Notes")
        XCTAssertEqual(
            lastText.currentEntry,
            .init(text: "Synthetic words", app: "Notes", storedAt: Date(timeIntervalSince1970: 1_800_000_000)))

        clock.withLock { $0 += DictationLastText.lifetime }
        XCTAssertNil(lastText.currentEntry)

        lastText.remember("Other words")
        XCTAssertNil(lastText.currentEntry?.app, "A newer text never inherits the earlier app")
        lastText.clear()
        XCTAssertNil(lastText.currentEntry)
    }

    func testTheWeekStaysSevenDaysWhateverTheHistoryShows() async throws {
        let store = try DictationStore.inMemory()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = Mutex(start)
        let model = DictationStatsModel(store: store, now: { clock.withLock { $0 } })
        await model.update(isEnabled: true)
        await model.show(range: 30)
        XCTAssertEqual(model.summary.days.count, 30)
        XCTAssertEqual(model.week.days.count, 7)
        XCTAssertEqual(model.today, .zero)

        model.record(DictationStatsSample(
            id: DictationRecordID(), day: DictationStatsCalendar.day(of: start, calendar: .current),
            words: 80, spokenDuration: 30, applicationName: "Mail", delivered: true))
        let counted = await TestPolling.until { model.today?.words == 80 }
        XCTAssertTrue(counted, "The week follows each recorded sample")
        XCTAssertEqual(model.week.totals.dictations, 1)

        clock.withLock { $0 = Calendar.current.date(byAdding: .day, value: 1, to: start)! }
        XCTAssertNil(model.today, "Yesterday's week does not pass for today")
        await model.refreshWeek()
        XCTAssertEqual(model.today, .zero)
        XCTAssertEqual(model.week.totals.words, 80)
        XCTAssertEqual(DictationMenuFormat.bars(model.week.days), [0, 0, 0, 0, 0, 1, 0])
    }

    func testTheCardAndTodayAreWorded() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(DictationMenuFormat.age(of: now.addingTimeInterval(-59), now: now), "Just now")
        XCTAssertEqual(DictationMenuFormat.age(of: now.addingTimeInterval(-125), now: now), "2 min ago")
        XCTAssertEqual(DictationMenuFormat.eyebrow(app: "Mail"), "Last dictation · Mail")
        XCTAssertEqual(DictationMenuFormat.eyebrow(app: nil), "Last dictation")
        let one = DictationStatsTotals(dictations: 1, words: 80, spokenDuration: 30, notDelivered: 0)
        XCTAssertEqual(DictationMenuFormat.detail(one), "1 dictation · ~2 min saved")
        let many = DictationStatsTotals(dictations: 23, words: 1_284, spokenDuration: 66, notDelivered: 0)
        XCTAssertEqual(DictationMenuFormat.detail(many), "23 dictations · ~31 min saved")
    }
}
