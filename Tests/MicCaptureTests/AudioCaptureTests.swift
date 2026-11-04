import AVFAudio
import Foundation
import XCTest
@testable import MicCapture

final class AudioInputFormatPolicyTests: XCTestCase {
    func testAcceptsOnlyFinitePositiveRateWithAtLeastOneChannel() {
        XCTAssertTrue(AudioInputFormatPolicy.isUsable(
            sampleRate: 48_000,
            channelCount: 1))
        XCTAssertFalse(AudioInputFormatPolicy.isUsable(
            sampleRate: 0,
            channelCount: 1))
        XCTAssertFalse(AudioInputFormatPolicy.isUsable(
            sampleRate: 48_000,
            channelCount: 0))
        XCTAssertFalse(AudioInputFormatPolicy.isUsable(
            sampleRate: -.infinity,
            channelCount: 1))
        XCTAssertFalse(AudioInputFormatPolicy.isUsable(
            sampleRate: .nan,
            channelCount: 1))
    }

    func testInputTapObservesEachDeliveredHardwareFormatWithoutRequestingOne() throws {
        let builtInFormat = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 1))
        let bluetoothFormat = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 24_000,
            channels: 1))

        XCTAssertNil(AudioInputTapPolicy.requestedFormat)
        XCTAssertEqual(
            AudioInputTapPolicy.sourceSampleRate(for: builtInFormat),
            48_000)
        XCTAssertEqual(
            AudioInputTapPolicy.sourceSampleRate(for: bluetoothFormat),
            24_000)
    }
}

final class AudioRouteTransitionGateTests: XCTestCase {
    func testOnlyNewestRequestMayMutateTheActiveGraph() throws {
        var gate = AudioRouteTransitionGate()
        gate.activate()

        let stale = try XCTUnwrap(gate.request())
        let newest = try XCTUnwrap(gate.request())

        XCTAssertFalse(gate.admits(stale))
        XCTAssertTrue(gate.admits(newest))
    }

    func testStopInvalidatesDelayedRouteWork() throws {
        var gate = AudioRouteTransitionGate()
        gate.activate()
        let ticket = try XCTUnwrap(gate.request())

        gate.deactivate()

        XCTAssertFalse(gate.admits(ticket))
        XCTAssertNil(gate.request())
    }

    func testNewCaptureGenerationRejectsPriorTickets() throws {
        var gate = AudioRouteTransitionGate()
        gate.activate()
        let priorCapture = try XCTUnwrap(gate.request())

        gate.deactivate()
        gate.activate()
        let currentCapture = try XCTUnwrap(gate.request())

        XCTAssertFalse(gate.admits(priorCapture))
        XCTAssertTrue(gate.admits(currentCapture))
    }
}


final class DownmixTests: XCTestCase {
    func testStereoBufferAveragesToMono() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<4 {
            channels[0][frame] = 1.0
            channels[1][frame] = 0.0
        }

        let mono = try Downmix.mono(from: buffer)
        XCTAssertEqual(mono.count, 4)
        for value in mono {
            XCTAssertEqual(value, 0.5, accuracy: 0.0001)
        }
    }
}
