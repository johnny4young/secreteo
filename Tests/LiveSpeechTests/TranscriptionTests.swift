import FluidAudio
import Foundation
import SpeechCore
import XCTest

@testable import LiveSpeech

final class ParakeetSegmentMapperTests: XCTestCase {
    private let meeting = MeetingID()

    func testLiveUpdateBecomesSegmentWithAbsoluteTimes() throws {
        var stream = ParakeetSegmentMapper.LiveStream()
        let segment = try stream.segment(
            text: " hola mundo ",
            isConfirmed: true,
            confidence: 0.93,
            tokenTimings: [
                timing("▁hola", 120.0, 120.4),
                timing("▁mundo", 120.5, 121.0),
            ],
            meetingID: meeting,
            channel: .system,
            language: "es"
        )
        XCTAssertNotNil(segment)
        XCTAssertEqual(segment?.text, "hola mundo")
        XCTAssertEqual(segment?.startTime, 120.0)
        XCTAssertEqual(segment?.endTime, 121.0)
        XCTAssertEqual(segment?.isFinal, true)
        XCTAssertEqual(segment?.channel, .system)
        XCTAssertEqual(segment?.language, "es")
        XCTAssertEqual(segment!.confidence!, 0.93, accuracy: 0.0001)
    }

    func testEmptyUpdateIsDropped() throws {
        var stream = ParakeetSegmentMapper.LiveStream()
        let segment = try stream.segment(
            text: "   ",
            isConfirmed: false,
            confidence: 0.5,
            tokenTimings: [],
            meetingID: meeting,
            channel: .microphone,
            language: nil
        )
        XCTAssertNil(segment)
    }

    /// Previously owned emission positions must not replay with a new window.
    func testOverlappingReDecodedTokensAreCut() throws {
        var stream = ParakeetSegmentMapper.LiveStream()
        _ = try stream.segment(
            text: "texto viejo", isConfirmed: false, confidence: 1,
            tokenTimings: [timing("▁texto", 10, 10.3), timing("▁viejo", 10.4, 10.8)],
            meetingID: meeting, channel: .microphone, language: nil)
        let segment = try stream.segment(
            text: "texto viejo repetido y algo nuevo",
            isConfirmed: true,
            confidence: 0.9,
            tokenTimings: [
                timing("▁texto", 10.0, 10.3),
                timing("▁viejo", 10.4, 10.8),
                timing("▁nuevo", 12.1, 12.6),
            ],
            meetingID: meeting,
            channel: .microphone,
            language: nil
        )
        XCTAssertEqual(segment?.text, "nuevo")
        XCTAssertEqual(segment?.startTime, 12.1)
        XCTAssertEqual(segment?.endTime, 12.6)
    }

    func testPureReDecodeUpdateIsDropped() throws {
        var stream = ParakeetSegmentMapper.LiveStream()
        _ = try stream.segment(
            text: "ya emitido", isConfirmed: false, confidence: 1,
            tokenTimings: [timing("▁ya", 5, 5.4), timing("▁emitido", 5.5, 6)],
            meetingID: meeting, channel: .microphone, language: nil)
        let segment = try stream.segment(
            text: "todo esto ya se había emitido",
            isConfirmed: true,
            confidence: 0.95,
            tokenTimings: [timing("▁ya", 5.0, 5.4), timing("▁emitido", 5.5, 6.0)],
            meetingID: meeting,
            channel: .microphone,
            language: nil
        )
        XCTAssertNil(segment)
    }

    func testMissingTimingsCannotClaimAudioOwnership() {
        var stream = ParakeetSegmentMapper.LiveStream()
        XCTAssertThrowsError(try stream.segment(
            text: "sin timings", isConfirmed: false, confidence: 0.7,
            tokenTimings: [], meetingID: meeting, channel: .microphone, language: nil))
    }

    func testEngineKeepsVendorHypothesisDiagnosticsOutOfConsole() {
        _ = ParakeetEngine(
            prepareLiveManager: { SlidingWindowAsrManager(config: $0) },
            prepareBatchManager: { AsrManager(config: $0) })
        XCTAssertFalse(AppLogger.mirrorsToConsole)
        XCTAssertEqual(AppLogger.minimumLevel, .warning)
    }

    @MainActor
    func testInvalidSampleRateThrowsInsteadOfBecomingSuccessfulSilence() async throws {
        for (samples, rate) in [([Float(0)], Double.nan), ([0], 0), ([0], -1)] {
            let manager = SlidingWindowAsrManager()
            let channel = ParakeetStreamChannel()
            let audio = AsyncStream<AudioChunk> { input in
                input.yield(AudioChunk(channel: .microphone, samples: samples, sampleRate: rate, timestamp: 0))
                input.finish()
            }
            do {
                try await ParakeetEngine.feed(audio, manager: manager, channelHolder: channel, probe: nil)
                XCTFail("malformed PCM cannot be skipped as silence")
            } catch ParakeetStreamChannel.Failure.invalidAudioChunk { }
            let bound = await channel.current
            XCTAssertNil(bound, "rejected PCM cannot acquire a capture channel")
            await manager.cancel()
        }
    }

    func testNonFiniteSamplesFeedAsSilenceAndBindTheChannel() async throws {
        for samples in [[Float.nan], [Float.infinity, 0.2]] {
            let manager = SlidingWindowAsrManager()
            let channel = ParakeetStreamChannel()
            let audio = AsyncStream<AudioChunk> { input in
                input.yield(AudioChunk(channel: .microphone, samples: samples, sampleRate: 16_000, timestamp: 0))
                input.finish()
            }
            try await ParakeetEngine.feed(audio, manager: manager, channelHolder: channel, probe: nil)
            let bound = await channel.current
            XCTAssertEqual(bound, .microphone, "A device glitch must not end the live session")
            await manager.cancel()
        }
    }

    @MainActor
    func testEmptyCallbackCannotBindOrFeedTheNativeJob() async throws {
        let manager = SlidingWindowAsrManager()
        let channel = ParakeetStreamChannel()
        let audio = AsyncStream<AudioChunk> { input in
            input.yield(AudioChunk(channel: .system, samples: [], sampleRate: 16_000, timestamp: 0))
            input.finish()
        }
        try await ParakeetEngine.feed(audio, manager: manager, channelHolder: channel, probe: nil)
        try await channel.set(.microphone)
        // A late subscriber would be rejected if even one buffer had been fed.
        let updates = await manager.tokenUpdates
        _ = try await manager.finish()
        var events = 0
        for try await update in updates {
            events += 1
            XCTAssertTrue(update.revision.isTerminal)
            XCTAssertTrue(update.tokens.isEmpty)
        }
        XCTAssertEqual(events, 1)
    }

    @MainActor
    func testProducerFailureCannotBeRelabeledByOutputDrivenCancellation() async throws {
        let channel = ParakeetStreamChannel()
        let cancelled = await channel.outcome(for: CancellationError(), cancelled: true)
        XCTAssertEqual(cancelled, .cancelled)
        await channel.markProducerFailure()
        let failed = await channel.outcome(for: CancellationError(), cancelled: true)
        XCTAssertEqual(failed, .failed)
    }

    @MainActor
    func testBufferedFinalDrainUsesTheSameReducerAndRetainsChannelAndConfirmation() async throws {
        let channel = ParakeetStreamChannel()
        try await channel.set(.system)
        let jobID = UUID()
        let updates = AsyncThrowingStream<SlidingWindowTokenUpdate, Error> { output in
            output.yield(.init(tokens: [timing("▁muy", 0, 0.2)], revision: .init(
                jobID: jobID, ordinal: 1, previousTokenCount: 0, retainedTokenCount: 0,
                stableTokenCount: 0, window: 0..<38400, center: 0..<32000, isTerminal: false)))
            output.yield(.init(tokens: [timing("▁muy", 0.2, 0.4), timing("▁bien", 0.4, 0.6)], revision: .init(
                jobID: jobID, ordinal: 2, previousTokenCount: 1, retainedTokenCount: 1,
                stableTokenCount: 2, window: 0..<38400, center: 0..<32000, isTerminal: false)))
            output.yield(.init(tokens: [], revision: .init(
                jobID: jobID, ordinal: 3, previousTokenCount: 3, retainedTokenCount: 3,
                stableTokenCount: 3, window: 0..<38400, center: 0..<32000, isTerminal: true)))
            output.finish()
        }
        let pair = AsyncThrowingStream<TranscriptSegment, Error>.makeStream()
        try await ParakeetEngine.consume(
            updates, hints: .init(language: "es", meetingID: meeting), channelHolder: channel,
            continuation: pair.continuation, probe: nil)
        pair.continuation.finish()
        var rows: [TranscriptSegment] = []
        var segments: [TranscriptSegment] = []
        for try await segment in pair.stream {
            segments.append(segment)
            CaptionCoalescer().apply(segment, to: &rows)
        }
        XCTAssertEqual(segments.map(\.isFinal), [false, true, false, true, false])
        XCTAssertEqual(segments.filter(\.isFinal).map(\.text), ["muy muy", "bien"])
        XCTAssertEqual(segments.filter { !$0.isFinal }.map(\.text), [" muy", " bien", ""])
        XCTAssertTrue(segments.allSatisfy { $0.channel == .system && $0.meetingID == meeting && $0.language == "es" })
        XCTAssertEqual(rows.map(\.text), ["muy muy bien"])
    }

    @MainActor
    func testCancelledConsumerDoesNotPublishBufferedUpdates() async throws {
        let channel = ParakeetStreamChannel()
        try await channel.set(.microphone)
        let updates = AsyncThrowingStream<SlidingWindowTokenUpdate, Error> { output in
            output.yield(.init(tokens: [timing("▁old", 0, 0.2)], revision: .init(
                jobID: UUID(), ordinal: 1, previousTokenCount: 0, retainedTokenCount: 0,
                stableTokenCount: 1, window: 0..<22400, center: 0..<16000, isTerminal: true)))
            output.finish()
        }
        let pair = AsyncThrowingStream<TranscriptSegment, Error>.makeStream()
        let task = Task {
            try await ParakeetEngine.consume(
                updates, hints: .init(meetingID: meeting), channelHolder: channel,
                continuation: pair.continuation, probe: nil)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("A cancelled consumer must not process buffered updates")
        } catch is CancellationError { }
        pair.continuation.finish()
        var count = 0
        for try await _ in pair.stream { count += 1 }
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testAJobCannotRelabelItsDecoderWithAnotherChannel() async throws {
        let channel = ParakeetStreamChannel()
        try await channel.set(.system)
        try await channel.set(.system)
        do {
            try await channel.set(.microphone)
            XCTFail("One native decoder cannot own two audio channels")
        } catch is ParakeetStreamChannel.Failure { }
        let current = await channel.current
        XCTAssertEqual(current, .system)
    }

    func testMalformedUpdateCannotAdvanceOwnership() throws {
        for tokens in [
            [timing("▁bad", .nan, 1)],
            [timing("▁bad", 1, 0)],
            [timing("▁later", 1, 2), timing("▁earlier", 0, 1)]
        ] {
            var stream = ParakeetSegmentMapper.LiveStream()
            XCTAssertThrowsError(try stream.segment(
                text: "bad", isConfirmed: false, confidence: 1, tokenTimings: tokens,
                meetingID: meeting, channel: .microphone, language: nil))
            let valid = try stream.segment(
                text: "valid", isConfirmed: true, confidence: 1,
                tokenTimings: [timing("▁valid", 0, 0.2)],
                meetingID: meeting, channel: .microphone, language: nil)
            XCTAssertEqual(valid?.text, "valid")
        }
    }

    func testBatchSplitsAtPauses() {
        let timings = [
            timing("▁primera", 0.0, 0.5),
            timing("▁frase", 0.6, 1.0),
            // 2.5 s pause — new segment
            timing("▁segunda", 3.5, 4.0),
            timing("▁frase", 4.1, 4.5),
        ]
        let segments = ParakeetSegmentMapper.segments(
            fromBatchText: "primera frase segunda frase",
            tokenTimings: timings,
            audioDuration: 5.0,
            confidence: 0.9,
            meetingID: meeting,
            channel: .system,
            language: nil
        )
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "primera frase")
        XCTAssertEqual(segments[1].text, "segunda frase")
        XCTAssertEqual(segments[0].endTime, 1.0)
        XCTAssertEqual(segments[1].startTime, 3.5)
        XCTAssertTrue(segments.allSatisfy(\.isFinal))
    }

    /// TDT timings carry no real gaps (token end = next token start), so
    /// sentence punctuation must cut even with zero pause between tokens.
    func testBatchSplitsAfterSentencePunctuation() {
        let timings = [
            timing("▁hola", 0.0, 0.5),
            timing("▁mundo.", 0.5, 1.0),
            timing("▁sigo", 1.0, 1.5),
            timing("▁hablando", 1.5, 2.0),
        ]
        let segments = ParakeetSegmentMapper.segments(
            fromBatchText: "hola mundo. sigo hablando",
            tokenTimings: timings,
            audioDuration: 2.0,
            confidence: 0.9,
            meetingID: meeting,
            channel: .system,
            language: nil
        )
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "hola mundo.")
        XCTAssertEqual(segments[1].text, "sigo hablando")
        XCTAssertEqual(segments[1].startTime, 1.0)
    }

    func testALateClosingMarkStaysWithItsSentence() {
        let timings = [
            timing("▁is", 18.6, 19.0),
            timing("▁there", 19.0, 19.6),
            timing("▁one", 19.6, 20.0),
            timing("▁here", 20.0, 20.24),
            timing("?", 21.12, 21.44),
            timing("▁okay", 21.44, 22.0),
        ]
        let segments = ParakeetSegmentMapper.segments(
            fromBatchText: "is there one here? okay",
            tokenTimings: timings,
            audioDuration: 23,
            confidence: 0.9,
            meetingID: meeting,
            channel: .system,
            language: nil
        )
        XCTAssertEqual(segments.map(\.text), ["is there one here?", "okay"])
        XCTAssertEqual(segments[0].endTime, 20.24)
    }

    func testPunctuationNeverBecomesARowAndOpeningMarksLeadTheirSentence() {
        let timings = [
            timing(".", 0.0, 0.2),
            timing("▁¿", 2.0, 2.1),
            timing("▁vienes", 2.8, 3.2),
            timing("?", 3.2, 3.3),
        ]
        let segments = ParakeetSegmentMapper.segments(
            fromBatchText: ". ¿vienes?",
            tokenTimings: timings,
            audioDuration: 4,
            confidence: 0.9,
            meetingID: meeting,
            channel: .system,
            language: nil
        )
        XCTAssertEqual(segments.map(\.text), ["¿ vienes?"])
        XCTAssertEqual(segments[0].startTime, 2.8)
    }

    func testBatchWithoutTimingsYieldsSingleSegment() {
        let segments = ParakeetSegmentMapper.segments(
            fromBatchText: "todo el archivo",
            tokenTimings: [],
            audioDuration: 93.0,
            confidence: 0.88,
            meetingID: meeting,
            channel: .system,
            language: "es"
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].startTime, 0)
        XCTAssertEqual(segments[0].endTime, 93.0)
        XCTAssertEqual(segments[0].text, "todo el archivo")
    }

    func testLongSegmentsSplitAtMaxDuration() {
        // 40 s of continuous tokens, one per second: must split before 30 s.
        let timings = (0..<40).map { second in
            timing("▁t\(second)", TimeInterval(second), TimeInterval(second) + 0.9)
        }
        let segments = ParakeetSegmentMapper.segments(
            fromBatchText: "x",
            tokenTimings: timings,
            audioDuration: 40,
            confidence: 0.9,
            meetingID: meeting,
            channel: .system,
            language: nil
        )
        XCTAssertGreaterThan(segments.count, 1)
        for segment in segments {
            XCTAssertLessThanOrEqual(segment.endTime - segment.startTime, 31)
        }
    }

    private func timing(_ token: String, _ start: TimeInterval, _ end: TimeInterval) -> TokenTiming {
        TokenTiming(token: token, tokenId: 0, startTime: start, endTime: end, confidence: 0.9)
    }
}

final class VocabularyPromptTests: XCTestCase {
    func testFormatsTermsAsNaturalSentence() {
        XCTAssertEqual(
            VocabularyPrompt.text(["QVTL", "Portavoz", "Ilarion"]),
            "In this meeting we discussed QVTL, Portavoz, Ilarion.")
    }

    func testFormatsSpanishTermsAsSpanishNaturalSentence() {
        XCTAssertEqual(
            VocabularyPrompt.text(["Qord2M", "Zephyr"], language: "es-CO"),
            "En esta reunión hablamos de Qord2M, Zephyr.")
    }

    func testEmptyAndBlankTermsYieldNoPrompt() {
        XCTAssertNil(VocabularyPrompt.text([]))
        XCTAssertNil(VocabularyPrompt.text(["  ", ""]))
    }

    func testParseSplitsAndTrimsCommaList() {
        XCTAssertEqual(
            VocabularyPrompt.parse(" QVTL , Portavoz,,  Ilarion "),
            ["QVTL", "Portavoz", "Ilarion"])
        XCTAssertEqual(VocabularyPrompt.parse(""), [])
    }
}

final class SpokenLanguageDetectorTests: XCTestCase {
    func testAutomaticRefineDoesNotPinOneLanguage() {
        XCTAssertNil(SpokenLanguageDetector.transcriptionLanguageHint())
    }

    func testHomogeneousSegmentLanguageTagsBecomeMeetingMetadata() {
        let segments = [
            languageSegment("This text was already refined in English.", language: "es-CO"),
            languageSegment("Another contaminated line after a refine pass.", language: "es"),
        ]

        XCTAssertEqual(SpokenLanguageDetector.homogeneousLanguage(in: segments), "es")
    }

    func testMixedSegmentLanguageTagsDoNotForceMeetingMetadata() {
        let segments = [
            languageSegment("uno dos tres", language: "es"),
            languageSegment("one two three", language: "en"),
        ]

        XCTAssertNil(SpokenLanguageDetector.homogeneousLanguage(in: segments))
    }

    func testExplicitTranscriptPolicyPinsRecoveryLanguage() {
        XCTAssertEqual(
            SpokenLanguageDetector.transcriptionLanguageHint(
                policy: .fixed(.spanish)),
            "es")
    }

    func testDetectsHomogeneousSpanishTextLocally() {
        let segments = [
            languageSegment(
                """
                La reunión se centró en la integración de mensajes y en aclarar \
                el contexto del proyecto con el equipo. También revisamos ingresos, \
                dependencias y próximos pasos para continuar el trabajo.
                """,
                language: nil),
        ]

        XCTAssertEqual(SpokenLanguageDetector.homogeneousLanguage(in: segments), "es")
    }

    func testMixedDetectedTextDoesNotForceOneMeetingLanguage() {
        let segments = [
            languageSegment(
                "Revisamos el presupuesto, los próximos pasos y la integración del proyecto.",
                language: nil),
            languageSegment(
                "We also discussed the launch plan, customer feedback, and support risks.",
                language: nil),
        ]

        XCTAssertNil(SpokenLanguageDetector.homogeneousLanguage(in: segments))
    }

    func testShortUnknownTranscriptFallsBackOnlyWhenProvided() {
        let segments = [languageSegment("ok", language: nil)]

        XCTAssertNil(SpokenLanguageDetector.homogeneousLanguage(in: segments))
        XCTAssertEqual(
            SpokenLanguageDetector.homogeneousLanguage(in: segments, fallback: "es-MX"),
            "es")
    }

    func testCanonicalLanguageCodeNormalizesBCP47Prefixes() {
        XCTAssertEqual(SpokenLanguageDetector.canonicalLanguageCode(" ES_CO "), "es")
        XCTAssertNil(SpokenLanguageDetector.canonicalLanguageCode("und"))
        XCTAssertNil(SpokenLanguageDetector.canonicalLanguageCode(""))
    }
}

private func segment(
    _ text: String,
    channel: AudioChannel,
    meeting: MeetingID,
    start: TimeInterval,
    end: TimeInterval
) -> TranscriptSegment {
    TranscriptSegment(
        meetingID: meeting,
        channel: channel,
        text: text,
        startTime: start,
        endTime: end,
        isFinal: true)
}

private func languageSegment(_ text: String, language: String?) -> TranscriptSegment {
    TranscriptSegment(
        meetingID: MeetingID(),
        channel: .system,
        text: text,
        language: language,
        startTime: 0,
        endTime: 1,
        isFinal: true)
}

// MARK: - Mic bleed filter (field evidence, Jul 10)

/// With speakers, the mic hears the room; the refined mic channel must not
/// re-attribute the room's words to "Me" (a real demo showed 52% fake talk).

final class MicBleedFilterTests: XCTestCase {
    private func segment(
        _ text: String, channel: AudioChannel, start: TimeInterval, end: TimeInterval
    ) -> TranscriptSegment {
        TranscriptSegment(
            meetingID: MeetingID(), speakerID: nil, channel: channel,
            text: text, startTime: start, endTime: end, isFinal: true)
    }

    func testRoomEchoInMicChannelIsDropped() {
        let system = [segment(
            "we updated all of the node asset IDs based on the spreadsheets",
            channel: .system, start: 100, end: 106)]
        let mic = [segment(
            "updated all the node asset IDs based on spreadsheets",
            channel: .microphone, start: 101, end: 105)]
        XCTAssertTrue(MicBleedFilter.filter(microphone: mic, system: system).isEmpty)
    }

    func testGenuineMicUtteranceSurvives() {
        let system = [segment(
            "we updated all of the node asset IDs",
            channel: .system, start: 100, end: 106)]
        let mic = [segment(
            "puedo compartir el dashboard que armamos ayer",
            channel: .microphone, start: 101, end: 105)]
        XCTAssertEqual(MicBleedFilter.filter(microphone: mic, system: system).count, 1)
    }

    func testSingleWordUtterancesRemainVisible() {
        let system = [segment("yeah exactly", channel: .system, start: 100, end: 102)]
        let mic = [segment("Yeah.", channel: .microphone, start: 100, end: 101)]
        XCTAssertEqual(MicBleedFilter.filter(microphone: mic, system: system).count, 1)
    }

    func testExactTwoWordCopyAtTheSameInstantIsDropped() {
        let system = [segment(
            "okay perfect", channel: .system, start: 100, end: 101.2)]
        let mic = [segment(
            "Okay perfect", channel: .microphone, start: 100.1, end: 101.3)]
        XCTAssertTrue(MicBleedFilter.filter(microphone: mic, system: system).isEmpty)
    }

    func testSequentialTwoWordReplySurvives() {
        let system = [segment(
            "thank you", channel: .system, start: 100, end: 101)]
        let mic = [segment(
            "Thank you", channel: .microphone, start: 101.2, end: 102)]
        XCTAssertEqual(MicBleedFilter.filter(microphone: mic, system: system).count, 1)
    }

    func testCrossTalkSharingMostOfAnEdgeSurvives() {
        // Both pairs share enough words to exceed the broad 60% containment
        // fallback, but the differing edge is real, contradictory speech.
        // Neither a shared opener nor a shared conclusion may erase it.
        let system = [
            segment(
                "we should ship the new build on friday after review",
                channel: .system, start: 100, end: 106),
            segment(
                "carla approved the release after security review",
                channel: .system, start: 110, end: 116),
        ]
        let mic = [
            segment(
                "we should ship the new build on monday after testing",
                channel: .microphone, start: 100, end: 106),
            segment(
                "diego rejected the release after security review",
                channel: .microphone, start: 110, end: 116),
        ]
        XCTAssertEqual(MicBleedFilter.filter(microphone: mic, system: system).count, 2)
    }

    func testTruncatedLeadingWindowCopyIsStillDropped() {
        // A system row that is entirely the leading window of the mic copy
        // remains bleed via the directional edges: the whole shorter row is
        // its own suffix, so suffix→prefix continuation covers containment.
        let system = [segment(
            "we updated all", channel: .system, start: 100, end: 101.5)]
        let mic = [segment(
            "we updated all of the node asset ids",
            channel: .microphone, start: 100, end: 104)]
        XCTAssertTrue(MicBleedFilter.filter(microphone: mic, system: system).isEmpty)
    }

    func testContiguousRollingSuffixAtTheSameInstantIsDropped() {
        let system = [segment(
            "it right now", channel: .system, start: 101.8, end: 103)]
        let mic = [segment(
            "we can we can do it right now",
            channel: .microphone,
            start: 100,
            end: 103)]
        XCTAssertTrue(MicBleedFilter.filter(microphone: mic, system: system).isEmpty)
    }

    func testDistantSystemTextDoesNotMatch() {
        let system = [segment(
            "we updated all of the node asset IDs based on the spreadsheets",
            channel: .system, start: 500, end: 506)]
        let mic = [segment(
            "updated all the node asset IDs based on spreadsheets",
            channel: .microphone, start: 101, end: 105)]
        XCTAssertEqual(MicBleedFilter.filter(microphone: mic, system: system).count, 1)
    }
}

final class BoundedLiveAudioFeedsTests: XCTestCase {
    func testColdAttachmentReceivesOnlyNewestBufferedContext() async throws {
        let feeds = BoundedLiveAudioFeeds(
            channels: [.microphone],
            capacityPerChannel: 2)
        for index in 0..<5 {
            feeds.yield(AudioChunk(
                channel: .microphone,
                samples: [Float(index)],
                sampleRate: 16_000,
                timestamp: TimeInterval(index)))
        }
        feeds.finish()

        let stream = try XCTUnwrap(feeds.stream(for: .microphone))
        var timestamps: [TimeInterval] = []
        for await chunk in stream {
            timestamps.append(chunk.timestamp)
        }

        XCTAssertEqual(timestamps, [3, 4])
    }

    func testChannelsStayIsolated() async throws {
        let feeds = BoundedLiveAudioFeeds(
            channels: [.microphone, .system],
            capacityPerChannel: 2)
        feeds.yield(AudioChunk(
            channel: .microphone,
            samples: [0.1],
            sampleRate: 16_000,
            timestamp: 1))
        feeds.yield(AudioChunk(
            channel: .system,
            samples: [0.2],
            sampleRate: 16_000,
            timestamp: 2))
        feeds.finish()

        let mic = try XCTUnwrap(feeds.stream(for: .microphone))
        let system = try XCTUnwrap(feeds.stream(for: .system))
        var micTimes: [TimeInterval] = []
        var systemTimes: [TimeInterval] = []
        for await chunk in mic { micTimes.append(chunk.timestamp) }
        for await chunk in system { systemTimes.append(chunk.timestamp) }

        XCTAssertEqual(micTimes, [1])
        XCTAssertEqual(systemTimes, [2])
    }
}

final class ParakeetVerifiedLoadTests: XCTestCase {
    func testRejectsUnverifiedOptionalGraphBeforeLoading() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(ModelNames.ASR.ctcHeadFile),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await ParakeetEngine.load(fromVerifiedDirectory: directory)
            XCTFail("an unverified optional graph must not load")
        } catch ParakeetEngine.VerifiedLoadFailure.unexpectedOptionalModel {
            // Rejected before native compilation or a download-capable loader.
        }
    }
}
