import FluidAudio
import Foundation
import SpeechCore

@testable import LiveSpeech

extension ParakeetSegmentMapper {
    enum LiveFailure: Error { case missingTimings, invalidTimings }

    private struct LiveToken: Hashable, Sendable {
        let id: Int
        let piece: String
    }

    /// One reducer per native job. Starts identify emission positions; ends are
    /// display durations synthesized from the next token, not ownership cursors.
    /// Everything before the frontier is already owned. At the frontier, retain
    /// occurrence counts so equal-time subwords survive while replay is consumed
    /// only once. Retained state is limited to the current emission position.
    struct LiveStream: Sendable {
        private var frontier: TimeInterval?
        private var occurrences: [LiveToken: Int] = [:]
        private(set) var endTime: TimeInterval = 0
        private(set) var replayedAtFrontier = 0
        private(set) var replayedBeforeFrontier = 0

        mutating func segment( // swiftlint:disable:this function_parameter_count
            text: String,
            isConfirmed: Bool,
            confidence: Float,
            tokenTimings: [TokenTiming],
            meetingID: MeetingID,
            channel: AudioChannel,
            language: String?
        ) throws -> TranscriptSegment? {
            guard !tokenTimings.isEmpty else {
                guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LiveFailure.missingTimings
                }
                return nil
            }
            guard tokenTimings.allSatisfy({
                $0.startTime.isFinite && $0.endTime.isFinite && $0.startTime >= 0 && $0.endTime >= $0.startTime
            }), zip(tokenTimings, tokenTimings.dropFirst()).allSatisfy({ $0.startTime <= $1.startTime }) else {
                throw LiveFailure.invalidTimings
            }

            var observed: [LiveToken: Int] = [:]
            var fresh: [TokenTiming] = []
            var nextFrontier = frontier
            var nextOccurrences = occurrences
            for timing in tokenTimings {
                if let frontier, timing.startTime < frontier {
                    replayedBeforeFrontier += 1
                    continue
                }
                let token = LiveToken(id: timing.tokenId, piece: timing.token)
                if timing.startTime == frontier {
                    observed[token, default: 0] += 1
                    if observed[token, default: 0] <= occurrences[token, default: 0] {
                        replayedAtFrontier += 1
                        continue
                    }
                }
                fresh.append(timing)
                if nextFrontier != timing.startTime {
                    nextFrontier = timing.startTime
                    nextOccurrences = [:]
                }
                nextOccurrences[token, default: 0] += 1
            }
            guard let first = fresh.first else { return nil }
            let end = fresh.reduce(first.endTime) { max($0, $1.endTime) }
            frontier = nextFrontier
            occurrences = nextOccurrences
            endTime = max(endTime, end)
            let body = joinedText(of: fresh)
            guard !body.isEmpty else { return nil }
            let startsWord = first.token.hasPrefix("▁") || first.token.first?.isWhitespace == true
            return TranscriptSegment(
                meetingID: meetingID, channel: channel, text: body, language: language,
                startTime: first.startTime, endTime: end,
                confidence: Double(confidence), isFinal: isConfirmed,
                liveUpdateMode: startsWord ? .tokenDelta : .tokenContinuation)
        }
    }
}
