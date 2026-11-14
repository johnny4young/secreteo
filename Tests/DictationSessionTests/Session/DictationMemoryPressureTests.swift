import XCTest

@testable import DictationSession

@MainActor
final class DictationMemoryPressureTests: XCTestCase {
    func testTheEndRunsOnceAfterPressureThatGaveSomethingBack() {
        let pressure = DictationMemoryPressure()
        let ends = EndLog()
        pressure.releases { true }
        pressure.whenItEnds { ends.record(stillActive: pressure.isActive) }

        pressure.changed(isActive: false)
        XCTAssertTrue(ends.reports.isEmpty, "no pressure has ended yet")

        pressure.changed(isActive: true)
        pressure.changed(isActive: true)
        XCTAssertTrue(ends.reports.isEmpty)

        pressure.changed(isActive: false)
        pressure.changed(isActive: false)
        XCTAssertEqual(ends.reports, [false], "once, and after the flag is down so a prewarm may run")
    }

    func testPressureThatGaveNothingBackRestoresNothing() {
        let pressure = DictationMemoryPressure()
        let ends = EndLog()
        pressure.releases { false }
        pressure.whenItEnds { ends.record(stillActive: pressure.isActive) }

        pressure.changed(isActive: true)
        pressure.changed(isActive: false)

        XCTAssertTrue(ends.reports.isEmpty, "a model that idled out stays out")
    }

    func testEachEpisodeAnswersForItself() {
        let pressure = DictationMemoryPressure()
        let ends = EndLog()
        let gives = GiveBack()
        pressure.releases { gives.next() }
        pressure.whenItEnds { ends.record(stillActive: pressure.isActive) }

        gives.answers = [true]
        pressure.changed(isActive: true)
        pressure.changed(isActive: false)
        gives.answers = [false]
        pressure.changed(isActive: true)
        pressure.changed(isActive: false)

        XCTAssertEqual(ends.reports, [false], "the second episode gave nothing back")
    }
}

@MainActor
private final class GiveBack {
    var answers: [Bool] = []

    func next() -> Bool {
        answers.isEmpty ? false : answers.removeFirst()
    }
}

@MainActor
private final class EndLog {
    private(set) var reports: [Bool] = []

    func record(stillActive: Bool) {
        reports.append(stillActive)
    }
}
