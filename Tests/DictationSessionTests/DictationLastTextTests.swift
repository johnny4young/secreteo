import XCTest
@testable import DictationSession

@MainActor
final class DictationLastTextTests: XCTestCase {
    func testExpiredTextIsDroppedFromMemoryWithNobodyAsking() async {
        var finishWait: CheckedContinuation<Void, Never>?
        var waited: Duration?
        let lastText = DictationLastText(observesSystem: false, waitForExpiry: { delay in
            waited = delay
            await withCheckedContinuation { finishWait = $0 }
        })

        lastText.remember("Synthetic words", alternate: "Other words")
        _ = await TestPolling.until { finishWait != nil }
        finishWait?.resume()

        let dropped = await TestPolling.until { lastText.hasStoredText == false }
        XCTAssertTrue(dropped)
        XCTAssertEqual(waited, .seconds(DictationLastText.lifetime))
    }

    func testANewerTextOutlivesTheEarlierExpiry() async {
        var finishWaits: [CheckedContinuation<Void, Never>] = []
        let lastText = DictationLastText(observesSystem: false, waitForExpiry: { _ in
            await withCheckedContinuation { finishWaits.append($0) }
        })

        lastText.remember("First")
        _ = await TestPolling.until { finishWaits.count == 1 }
        lastText.remember("Second")
        _ = await TestPolling.until { finishWaits.count == 2 }
        finishWaits[0].resume()
        await Task.yield()

        XCTAssertEqual(lastText.current, "Second")
        finishWaits[1].resume()
        let dropped = await TestPolling.until { lastText.hasStoredText == false }
        XCTAssertTrue(dropped)
    }
}
