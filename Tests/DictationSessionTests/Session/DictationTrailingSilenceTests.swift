import Foundation
import os
import Synchronization
import XCTest
import SpeechCore

@testable import DictationSession

@MainActor
final class DictationTrailingSilenceTests: XCTestCase {
    func testASilentTailEndsAfterATenthOfASecond() {
        let tail = TailFeed()
        let fired = Mutex(0)
        tail.offer(level: 0.001, milliseconds: 100)
        tail.silence.finishRequested()
        tail.silence.onSilence { fired.withLock { $0 += 1 } }

        tail.offer(level: 0.001, milliseconds: 50)
        XCTAssertFalse(tail.silence.isSilent, "Half the required silence is not enough")
        tail.offer(level: 0.001, milliseconds: 50)
        tail.offer(level: 0.001, milliseconds: 50)

        XCTAssertTrue(tail.silence.isSilent)
        XCTAssertEqual(fired.withLock { $0 }, 1)
    }

    func testSpeechAfterTheGestureKeepsTheWholeTail() {
        let tail = TailFeed()
        tail.offer(level: 0.001, milliseconds: 100)
        tail.silence.finishRequested()
        tail.offer(level: 0.2, milliseconds: 80)
        for _ in 0..<5 { tail.offer(level: 0.001, milliseconds: 80) }

        XCTAssertFalse(tail.silence.isSilent, "A word still being spoken is never cut")
    }

    func testAudioBeforeTheGestureNeverCountsAsTail() {
        let tail = TailFeed()
        for _ in 0..<5 { tail.offer(level: 0.001, milliseconds: 100) }

        XCTAssertFalse(tail.silence.isSilent)
    }

    func testAudioStillInFlightAtTheGestureIsNotTail() {
        let tail = TailFeed()
        tail.offer(level: 0.001, milliseconds: 100, sampleRate: 24_000)
        tail.advance(milliseconds: 150)
        tail.silence.finishRequested()
        // A Bluetooth-sized buffer that was mostly recorded before the gesture.
        tail.offer(level: 0.001, milliseconds: 170, sampleRate: 24_000)

        XCTAssertFalse(tail.silence.isSilent, "Only 20 ms of this buffer follows the gesture")
        tail.offer(level: 0.001, milliseconds: 100, sampleRate: 24_000)
        XCTAssertTrue(tail.silence.isSilent)
    }

    func testANoisyRoomSetsItsOwnQuiet() {
        let room = TailFeed()
        room.offer(level: 0.3, milliseconds: 100)
        room.offer(level: 0.004, milliseconds: 100)
        room.silence.finishRequested()
        room.offer(level: 0.007, milliseconds: 120)
        XCTAssertTrue(room.silence.isSilent, "Room noise is not speech")

        let speech = TailFeed()
        speech.offer(level: 0.004, milliseconds: 100)
        speech.silence.finishRequested()
        speech.offer(level: 0.009, milliseconds: 120)
        XCTAssertFalse(speech.silence.isSilent, "More than twice the room is speech")
    }

    func testSpeechBeforeTheGestureIsNeverTakenForTheRoom() {
        let tail = TailFeed()
        for _ in 0..<10 { tail.offer(level: 0.05, milliseconds: 85) }
        tail.silence.finishRequested()
        tail.offer(level: 0.03, milliseconds: 85)
        tail.offer(level: 0.03, milliseconds: 85)

        XCTAssertFalse(tail.silence.isSilent, "A fading last word is louder than any room")
    }

    func testZerosFromARestartedStreamAreNotSilence() {
        let tail = TailFeed()
        tail.offer(level: 0.001, milliseconds: 100)
        tail.silence.finishRequested()
        tail.offer(level: 0, milliseconds: 150)

        XCTAssertFalse(tail.silence.isSilent)
    }

    func testAShortSoundInsideALongBufferIsHeard() {
        let tail = TailFeed()
        tail.offer(level: 0.001, milliseconds: 100)
        tail.silence.finishRequested()
        var samples = [Float](repeating: 0.001, count: 1_600)
        for index in 800..<960 { samples[index] = index.isMultiple(of: 2) ? 0.1 : -0.1 }
        tail.offer(samples, sampleRate: 16_000)

        XCTAssertFalse(tail.silence.isSilent)
    }

    func testAShortRemainderJoinsTheWindowBeforeIt() {
        var samples = [Float](repeating: 0, count: 165)
        for index in 160..<165 { samples[index] = 0.5 }
        let chunk = AudioChunk(channel: .microphone, samples: samples, sampleRate: 16_000, timestamp: 0)

        XCTAssertEqual(DictationTrailingSilence.loudestWindow(chunk), (5 * 0.25 / 165).squareRoot(), accuracy: 1e-6)
    }

    func testTheStopTailEndsEarlyOnSilence() async {
        let clock = ControlledTestSleep()
        let tail = TailFeed()
        let silence = tail.silence
        tail.offer(level: 0.001, milliseconds: 100)
        silence.finishRequested()
        let ended = Task { await DictationController.stopTailEnded(wait: { try await clock.wait(for: $0) }, silence: silence) }
        let waiting = await clock.waitUntilCallCount(1)
        XCTAssertTrue(waiting)
        let requested = await clock.requestedDuration(at: 0)
        XCTAssertEqual(requested, .milliseconds(250))

        tail.offer(level: 0.001, milliseconds: 120)

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

}

/// Offers back-to-back audio on a held clock, so a test decides how long passes before the gesture.
@MainActor
private final class TailFeed {
    private let clock = OSAllocatedUnfairLock(initialState: ContinuousClock.now)
    private var audioTime: TimeInterval = 0
    let silence: DictationTrailingSilence

    init() {
        let clock = clock
        silence = DictationTrailingSilence(now: { clock.withLock { $0 } })
    }

    func advance(milliseconds: Int) {
        clock.withLock { $0 += .milliseconds(milliseconds) }
    }

    func offer(level: Float, milliseconds: Int, sampleRate: Double = 16_000) {
        let count = Int(sampleRate) * milliseconds / 1_000
        offer((0..<count).map { $0.isMultiple(of: 2) ? level : -level }, sampleRate: sampleRate)
    }

    func offer(_ samples: [Float], sampleRate: Double) {
        silence.offer(AudioChunk(channel: .microphone, samples: samples, sampleRate: sampleRate, timestamp: audioTime))
        audioTime += Double(samples.count) / sampleRate
    }
}
