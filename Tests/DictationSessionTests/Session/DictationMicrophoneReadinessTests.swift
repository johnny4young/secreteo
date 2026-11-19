import Foundation
import SpeechCore
import XCTest
@testable import DictationSession

@MainActor
final class DictationMicrophoneReadinessTests: XCTestCase {
    @MainActor
    private final class Probe {
        var ready = 0
        var meters = 0
        var failures: [DictationMicrophoneReadiness.Failure] = []
    }

    private struct Rig {
        let readiness: DictationMicrophoneReadiness
        let probe: Probe
        let input: AsyncThrowingStream<AudioChunk, Error>.Continuation
        let audio: AsyncStream<AudioChunk>
        let pump: Task<Void, Never>
    }

    private func makeRig() -> Rig {
        let probe = Probe()
        let readiness = DictationMicrophoneReadiness(
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            onReady: { probe.ready += 1 },
            onFailure: { probe.failures.append($0) })
        let (stream, input) = AsyncThrowingStream.makeStream(of: AudioChunk.self)
        let (audio, feed) = AsyncStream.makeStream(
            of: AudioChunk.self, bufferingPolicy: .bufferingNewest(DictationRelayPolicy.capacity))
        let pump = readiness.pump(stream: stream, feed: feed, updateMeter: { _ in probe.meters += 1 })
        return Rig(readiness: readiness, probe: probe, input: input, audio: audio, pump: pump)
    }

    private func chunk(_ value: Float, seconds: Double = 0.1) -> AudioChunk {
        AudioChunk(
            channel: .microphone, samples: [Float](repeating: value, count: Int(16_000 * seconds)),
            sampleRate: 16_000, timestamp: 0)
    }

    private func send(_ chunk: AudioChunk, to rig: Rig) async -> Bool {
        let before = rig.probe.meters
        rig.input.yield(chunk)
        return await TestPolling.until { rig.probe.meters == before + 1 }
    }

    private func finish(_ rig: Rig) async -> Int {
        rig.input.finish()
        await rig.pump.value
        var relayed = 0
        for await _ in rig.audio { relayed += 1 }
        rig.readiness.finish()
        return relayed
    }

    func testSilentBuffersWaitForTheFirstAudibleOne() async {
        let rig = makeRig()
        for value: Float in [0, 0.000_05, -0.000_1] {
            let handled = await send(chunk(value), to: rig)
            XCTAssertTrue(handled)
        }
        XCTAssertNotNil(rig.readiness.firstFrameAt, "The capture clock starts at the first buffer")
        XCTAssertEqual(rig.probe.ready, 0, "Digital silence is not a working microphone yet")
        let audible = await send(chunk(0.01), to: rig)
        XCTAssertTrue(audible)
        XCTAssertEqual(rig.probe.ready, 1)
        let more = await send(chunk(0.2), to: rig)
        XCTAssertTrue(more)
        XCTAssertEqual(rig.probe.ready, 1, "Ready fires once")
        let relayed = await finish(rig)
        XCTAssertEqual(relayed, 5, "Silent buffers still reach the model")
        XCTAssertEqual(rig.probe.failures, [])
    }

    func testAudibleFirstBufferIsReadyAtOnce() async {
        let rig = makeRig()
        let handled = await send(chunk(0.1), to: rig)
        XCTAssertTrue(handled)
        XCTAssertEqual(rig.probe.ready, 1)
        XCTAssertNotNil(rig.readiness.firstFrameAt)
        _ = await finish(rig)
    }

    func testExactZerosBecomeReadyAfterTheFallback() async {
        let rig = makeRig()
        let steps = Int((DictationMicrophoneReadiness.silentFallback / 0.1).rounded())
        for _ in 1..<steps {
            let handled = await send(chunk(0), to: rig)
            XCTAssertTrue(handled)
        }
        XCTAssertEqual(rig.probe.ready, 0)
        let last = await send(chunk(0), to: rig)
        XCTAssertTrue(last)
        XCTAssertEqual(rig.probe.ready, 1, "A muted or gated input never stays in preparing")
        let relayed = await finish(rig)
        XCTAssertEqual(relayed, steps)
    }

    func testNoBufferStillFailsAtTheFirstBufferDeadline() async {
        let rig = makeRig()
        let (deadline, expire) = AsyncStream.makeStream(of: Void.self)
        rig.readiness.beginDeadline { for await _ in deadline { return } }
        expire.yield()
        let failed = await TestPolling.until { rig.probe.failures == [.noAudio] }
        XCTAssertTrue(failed)
        XCTAssertEqual(rig.probe.ready, 0)
        _ = await finish(rig)
    }

    func testSilentFirstBufferStillDisarmsTheDeadline() async {
        let rig = makeRig()
        let (deadline, expire) = AsyncStream.makeStream(of: Void.self)
        rig.readiness.beginDeadline { for await _ in deadline { return } }
        let handled = await send(chunk(0), to: rig)
        XCTAssertTrue(handled)
        expire.yield()
        expire.finish()
        rig.input.finish()
        await rig.pump.value
        XCTAssertEqual(rig.probe.failures, [], "A silent buffer is still audio for the deadline")
        rig.readiness.finish()
    }
}
