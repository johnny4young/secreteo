import Foundation
import Synchronization
import XCTest
import SpeechCore

@testable import DictationSession

@MainActor
final class DictationTrailingSilenceTests: XCTestCase {
    func testASilentTailEndsAfterATenthOfASecond() {
        let silence = DictationTrailingSilence()
        let fired = Mutex(0)
        silence.offer(chunk(level: 0.001, milliseconds: 100))
        silence.finishRequested()
        silence.onSilence { fired.withLock { $0 += 1 } }

        silence.offer(chunk(level: 0.001, milliseconds: 50))
        XCTAssertFalse(silence.isSilent, "Half the required silence is not enough")
        silence.offer(chunk(level: 0.001, milliseconds: 50))
        silence.offer(chunk(level: 0.001, milliseconds: 50))

        XCTAssertTrue(silence.isSilent)
        XCTAssertEqual(fired.withLock { $0 }, 1)
    }

    func testSpeechAfterTheGestureKeepsTheWholeTail() {
        let silence = DictationTrailingSilence()
        silence.offer(chunk(level: 0.001, milliseconds: 100))
        silence.finishRequested()
        silence.offer(chunk(level: 0.2, milliseconds: 80))
        for _ in 0..<5 { silence.offer(chunk(level: 0.001, milliseconds: 80)) }

        XCTAssertFalse(silence.isSilent, "A word still being spoken is never cut")
    }

    func testAudioBeforeTheGestureNeverCountsAsTail() {
        let silence = DictationTrailingSilence()
        for _ in 0..<5 { silence.offer(chunk(level: 0.001, milliseconds: 100)) }

        XCTAssertFalse(silence.isSilent)
    }

    func testANoisyRoomSetsItsOwnQuiet() {
        let silence = DictationTrailingSilence()
        silence.offer(chunk(level: 0.3, milliseconds: 100))
        silence.offer(chunk(level: 0.02, milliseconds: 100))
        silence.finishRequested()
        silence.offer(chunk(level: 0.03, milliseconds: 120))

        XCTAssertTrue(silence.isSilent, "Room noise is not speech")

        let speech = DictationTrailingSilence()
        speech.offer(chunk(level: 0.02, milliseconds: 100))
        speech.finishRequested()
        speech.offer(chunk(level: 0.05, milliseconds: 120))
        XCTAssertFalse(speech.isSilent, "More than twice the room is speech")
    }

    func testAShortSoundInsideALongBufferIsHeard() {
        let silence = DictationTrailingSilence()
        silence.offer(chunk(level: 0.001, milliseconds: 100))
        silence.finishRequested()
        var samples = [Float](repeating: 0.001, count: 1_600)
        for index in 800..<960 { samples[index] = index.isMultiple(of: 2) ? 0.1 : -0.1 }
        silence.offer(AudioChunk(channel: .microphone, samples: samples, sampleRate: 16_000, timestamp: 0))

        XCTAssertFalse(silence.isSilent)
    }

    func testTheStopTailEndsEarlyOnSilence() async {
        let clock = ControlledTestSleep()
        let silence = DictationTrailingSilence()
        silence.offer(chunk(level: 0.001, milliseconds: 100))
        silence.finishRequested()
        let ended = Task { await DictationController.stopTailEnded(wait: { try await clock.wait(for: $0) }, silence: silence) }
        let waiting = await clock.waitUntilCallCount(1)
        XCTAssertTrue(waiting)
        let requested = await clock.requestedDuration(at: 0)
        XCTAssertEqual(requested, .milliseconds(250))

        silence.offer(chunk(level: 0.001, milliseconds: 120))

        let result = await ended.value
        XCTAssertTrue(result, "Silence ends the tail before 250 ms")
    }

    func testTheStopTailRunsInFullWithoutSilenceAndStopsWhenCancelled() async {
        let clock = ControlledTestSleep()
        let silence = DictationTrailingSilence()
        silence.finishRequested()
        let full = Task { await DictationController.stopTailEnded(wait: { try await clock.wait(for: $0) }, silence: silence) }
        _ = await clock.waitUntilCallCount(1)
        let resumed = await clock.resumeCall(at: 0)
        XCTAssertTrue(resumed)
        let fullResult = await full.value
        XCTAssertTrue(fullResult)

        let cancelled = Task { await DictationController.stopTailEnded(wait: { try await clock.wait(for: $0) }, silence: silence) }
        _ = await clock.waitUntilCallCount(2)
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        XCTAssertFalse(cancelledResult, "A cancelled stop never stops the microphone")
    }

    private func chunk(level: Float, milliseconds: Int) -> AudioChunk {
        let count = 16 * milliseconds
        let samples = (0..<count).map { $0.isMultiple(of: 2) ? level : -level }
        return AudioChunk(channel: .microphone, samples: samples, sampleRate: 16_000, timestamp: 0)
    }
}
