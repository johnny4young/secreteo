import XCTest

@testable import DictationSession

@MainActor
final class DictationMemoryPressureTests: XCTestCase {
    func testTheEndRunsOnceWhenPressureEndsAndNeverOnACalmReport() {
        let pressure = DictationMemoryPressure()
        let ends = EndLog()
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
}

@MainActor
private final class EndLog {
    private(set) var reports: [Bool] = []

    func record(stillActive: Bool) {
        reports.append(stillActive)
    }
}
