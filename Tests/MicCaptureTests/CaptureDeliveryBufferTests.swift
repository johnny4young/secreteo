import AVFAudio
import Foundation
import os
import SpeechCore
import XCTest
@testable import MicCapture

final class CaptureDeliveryBufferTests: XCTestCase {
    private func buffer(frames: Int = 8, packets: Int = 4, chunk: Int = 3) -> CaptureDeliveryBuffer {
        CaptureDeliveryBuffer(channel: .microphone, limits: .init(frames: frames, packets: packets, chunkFrames: chunk))
    }

    private func append(_ values: [Float], to buffer: CaptureDeliveryBuffer, gap: Int = 0) {
        XCTAssertTrue(buffer.append(samples: values, rate: 10, timestamp: Double(gap) / 10,
                                    plan: .init(paddingFrameCount: gap, paddingTimestamp: 0,
                                                deliveredFrameCount: gap + values.count)))
    }

    func testStopDrainsExactSamplesAndSymbolicGapInBoundedChunks() async throws {
        let buffer = buffer()
        append([1, 2, 3, 4], to: buffer, gap: 13)
        XCTAssertEqual(buffer.highWater.frames, 4)
        buffer.finish()
        var samples: [Float] = []
        var times: [Double] = []
        for try await chunk in buffer.stream() {
            XCTAssertLessThanOrEqual(chunk.samples.count, 3)
            times.append(chunk.timestamp)
            samples += chunk.samples
        }
        XCTAssertEqual(samples, Array(repeating: 0, count: 13) + [1, 2, 3, 4])
        XCTAssertEqual(times, [0, 0.3, 0.6, 0.9, 1.2, 1.3, 1.6])
        XCTAssertEqual(buffer.report().acceptedFrames, 17)
        XCTAssertEqual(buffer.report().paddingFrames, 13)
    }

    func testBackpressureFailsOnceWithoutEvictingAcceptedPCM() async throws {
        let buffer = buffer()
        let failures = OSAllocatedUnfairLock(initialState: 0)
        buffer.setFailureHandler { failures.withLock { $0 += 1 } }
        append([1, 2, 3, 4], to: buffer)
        append([5, 6, 7, 8], to: buffer)
        XCTAssertFalse(buffer.append(samples: [9], rate: 10, timestamp: 0,
                                     plan: .init(paddingFrameCount: 0, paddingTimestamp: 0, deliveredFrameCount: 9)))
        buffer.finish(failure: .sourceFailed)
        var samples: [Float] = []
        do {
            for try await chunk in buffer.stream() { samples += chunk.samples }
            XCTFail("overflow must not become a successful end")
        } catch let failure as CaptureDeliveryFailure {
            XCTAssertEqual(failure.cause, .overloaded)
        }
        XCTAssertEqual(samples, [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(buffer.report().acceptedFrames, 8)
        XCTAssertEqual(buffer.report().rejectedFrames, 1)
        XCTAssertEqual(failures.withLock { $0 }, 1)
        XCTAssertEqual(buffer.highWater.frames, 8)
    }

    func testInvalidNativeGeometryDoesNotInventAZeroRejectedFrameCount() {
        let buffer = buffer()
        buffer.finish(failure: .invalidFormat)
        XCTAssertEqual(buffer.report().acceptedFrames, 0)
        XCTAssertNil(buffer.report().rejectedFrames)
        XCTAssertEqual(buffer.report().failure, .invalidFormat)
    }

    func testTinyCallbacksCannotGrowMetadataPastItsIndependentLimit() {
        let buffer = buffer(frames: 100, packets: 2)
        append([1], to: buffer)
        append([2], to: buffer)
        XCTAssertFalse(buffer.append(samples: [3], rate: 10, timestamp: 0,
                                     plan: .init(paddingFrameCount: 0, paddingTimestamp: 0, deliveredFrameCount: 3)))
        XCTAssertEqual(buffer.highWater.packets, 2)
        XCTAssertEqual(buffer.highWater.frames, 2)
        XCTAssertEqual(buffer.report().failure, .overloaded)
    }

    func testNativeAndResampledOversizeAreRejectedBeforeCopying() throws {
        for (input, source, target, rejected) in [(9, 10.0, 10.0, 9), (8, 10.0, 20.0, 16)] {
            let buffer = buffer()
            XCTAssertThrowsError(try buffer.admitNativeFrames(input, sourceRate: source, targetRate: target))
            XCTAssertEqual(buffer.report().acceptedFrames, 0)
            XCTAssertEqual(buffer.report().rejectedFrames, Int64(rejected))
        }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let native = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 9))
        native.frameLength = 9
        let buffer = buffer()
        XCTAssertThrowsError(try Downmix.mono(from: native) {
            try buffer.admitNativeFrames($0, sourceRate: 48_000, targetRate: 48_000)
        })
    }

    func testTwoHourGapConsumesNoQueuedSilenceAllocation() async throws {
        let buffer = buffer(frames: 4, packets: 1, chunk: 4096)
        let gap = 2 * 60 * 60 * 48_000
        append([0.25], to: buffer, gap: gap)
        buffer.finish()
        var frames = 0
        var final: Float?
        for try await chunk in buffer.stream() {
            frames += chunk.samples.count
            final = chunk.samples.last
            XCTAssertLessThanOrEqual(chunk.samples.count, 4096)
        }
        XCTAssertEqual(frames, gap + 1)
        XCTAssertEqual(final, 0.25)
        XCTAssertEqual(buffer.highWater.frames, 1)
        XCTAssertEqual(buffer.highWater.packets, 1)
    }

    func testCancellationWakesAnEmptyConsumerAndRetiresProducer() async {
        let buffer = buffer()
        let failed = expectation(description: "producer retired")
        buffer.setFailureHandler { failed.fulfill() }
        let consumer = Task {
            do {
                for try await _ in buffer.stream() {}
                try Task.checkCancellation()
            } catch { return error is CancellationError }
            return false
        }
        consumer.cancel()
        let cancelled = await consumer.value
        XCTAssertTrue(cancelled)
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertFalse(buffer.isAccepting)
    }

    func testCancellationWhileParkedWakesAndReleasesTheConsumer() async {
        let parked = expectation(description: "consumer parked")
        let retired = expectation(description: "producer retired")
        let buffer = CaptureDeliveryBuffer(channel: .system, onConsumerWait: { parked.fulfill() })
        buffer.setFailureHandler { retired.fulfill() }
        let consumer = Task {
            do {
                for try await _ in buffer.stream() {}
                try Task.checkCancellation()
                return false
            } catch { return error is CancellationError }
        }
        await fulfillment(of: [parked], timeout: 1)
        consumer.cancel()
        let cancelled = await consumer.value
        XCTAssertTrue(cancelled)
        await fulfillment(of: [retired], timeout: 1)
        XCTAssertFalse(buffer.isAccepting)
    }

    func testFinishedStreamDoesNotRetainItsBuffer() async throws {
        var owner: CaptureDeliveryBuffer? = buffer()
        weak let weakOwner = owner
        var stream: AsyncThrowingStream<AudioChunk, Error>? = owner?.stream()
        owner?.finish()
        if let sequence = stream { for try await _ in sequence {} }
        stream = nil
        owner = nil
        XCTAssertNil(weakOwner)
    }

    func testFixedStressMatrixWrapsRingWithoutFrameLossOrRetention() async throws {
        for _ in 0..<25 {
            let buffer = buffer(frames: 8, packets: 2, chunk: 4)
            var iterator = buffer.stream().makeAsyncIterator()
            for value in 0..<100 {
                append([Float(value)], to: buffer)
                let next = try await iterator.next()
                XCTAssertEqual(next?.samples, [Float(value)])
            }
            buffer.finish()
            let end = try await iterator.next()
            XCTAssertNil(end)
            XCTAssertEqual(buffer.report().acceptedFrames, 100)
            XCTAssertEqual(buffer.highWater.frames, 1)
        }
    }
}
