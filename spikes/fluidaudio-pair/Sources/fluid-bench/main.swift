import AVFoundation
import Foundation
import LiveSpeech
import LocalModelStore
import SpeechCore

func store(_ root: String) throws -> LocalModelStore {
    try LocalModelStore(location: .directory(URL(fileURLWithPath: root)),
                        consumer: StoreConsumer(bundleID: "com.example.secreteo-bench", displayName: "Bench"))
}

func samples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    precondition(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

func peakMB() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576
}

struct ClipResult: Codable {
    let name: String
    let seconds: Double
    let firstTextSeconds: Double?
    let segments: Int
    let finals: String
    let trace: String
    let outcome: String
    let rejected: Int
}

struct RunResult: Codable {
    let checkpoint: String
    let paced: Bool
    let loadSeconds: Double
    let peakMB: Double
    let clips: [ClipResult]
}

let arguments = CommandLine.arguments
switch arguments[1] {
case "install":
    let target = try store(arguments[2])
    for manifest in [ModelCatalog.parakeetTdtV3, ModelCatalog.parakeetUltra, ModelCatalog.sileroVAD] {
        let directory = try await target.ensureAvailable(manifest)
        print(manifest.id, directory.lastPathComponent)
    }
case "run":
    let target = try store(arguments[2])
    let checkpoint = ParakeetCheckpoint(rawValue: arguments[3])!
    let clips = URL(fileURLWithPath: arguments[4])
    let out = URL(fileURLWithPath: arguments[5])
    let paced = arguments[6] == "paced"
    let prefix = arguments.count > 7 ? arguments[7] : ""
    let manifest = checkpoint == .ultra ? ModelCatalog.parakeetUltra : ModelCatalog.parakeetTdtV3
    guard await target.verifiedInstallation(manifest) != nil else { fatalError("not installed") }
    let directory = try await target.directory(for: manifest)
    let clock = ContinuousClock()
    var engine: ParakeetEngine!
    let load = await clock.measure { engine = try! await ParakeetEngine.load(fromVerifiedDirectory: directory, checkpoint: checkpoint) }
    var results: [ClipResult] = []
    let names = try FileManager.default.contentsOfDirectory(atPath: clips.path)
        .filter { $0.hasSuffix(".wav") && $0.hasPrefix(prefix) }.sorted()
    for name in names {
        let pcm = try samples(clips.appendingPathComponent(name))
        let box = Box()
        let observed = engine.observingLiveWork { box.set($0) }
        let (stream, input) = AsyncStream.makeStream(of: AudioChunk.self)
        let chunk = 1_600
        let producer = Task {
            var offset = 0.0
            for start in stride(from: 0, to: pcm.count, by: chunk) {
                let end = min(start + chunk, pcm.count)
                input.yield(AudioChunk(channel: .microphone, samples: Array(pcm[start..<end]), sampleRate: 16_000, timestamp: offset))
                offset += Double(end - start) / 16_000
                if paced { try? await Task.sleep(for: .milliseconds(100)) }
            }
            input.finish()
        }
        let language = name.hasPrefix("es") ? "es" : "en"
        let began = clock.now
        var first: Double?
        var segments: [TranscriptSegment] = []
        var failure: String?
        do {
            for try await segment in observed.transcribe(stream, hints: TranscriptionHints(language: language, filtersLiveScript: true)) {
                if first == nil, !segment.text.isEmpty { first = (clock.now - began) / .seconds(1) }
                segments.append(segment)
            }
        } catch { failure = String(describing: type(of: error)) }
        await producer.value
        let elapsed = (clock.now - began) / .seconds(1)
        let sample = box.get()
        results.append(ClipResult(
            name: name, seconds: elapsed, firstTextSeconds: first, segments: segments.count,
            finals: segments.filter(\.isFinal).map(\.text).joined(separator: " "),
            trace: segments.map { "\($0.isFinal ? "F" : "P")|\($0.text)|\(String(format: "%.2f", $0.startTime))|\(String(format: "%.2f", $0.endTime))" }.joined(separator: "\n"),
            outcome: failure ?? sample?.outcome.rawValue ?? "none", rejected: sample?.rejectedBuffers ?? -1))
    }
    let run = RunResult(checkpoint: checkpoint.rawValue, paced: paced, loadSeconds: load / .seconds(1), peakMB: peakMB(), clips: results)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(run).write(to: out)
case "silero":
    let target = try store(arguments[2])
    let clips = URL(fileURLWithPath: arguments[3])
    var lines: [String] = []
    let names = try FileManager.default.contentsOfDirectory(atPath: clips.path).filter { $0.hasSuffix(".wav") }.sorted()
    for name in names {
        let detector = try await SileroVoiceActivityDetector.load(from: target, channel: .microphone)
        let pcm = try samples(clips.appendingPathComponent(name))
        var active = 0
        var total = 0
        for start in stride(from: 0, to: pcm.count, by: 4_096) {
            let end = min(start + 4_096, pcm.count)
            let batch = try await detector.process(AudioChunk(channel: .microphone, samples: Array(pcm[start..<end]), sampleRate: 16_000, timestamp: Double(start) / 16_000))
            total += batch.observations.count
            active += batch.observations.filter(\.isSpeechActive).count
        }
        lines.append("\(name) active=\(active) total=\(total)")
    }
    let detector = try await SileroVoiceActivityDetector.load(from: target, channel: .microphone)
    let silent = try await detector.process(AudioChunk(channel: .microphone, samples: [Float](repeating: 0, count: 16_384), sampleRate: 16_000, timestamp: 0))
    lines.append("silence active=\(silent.observations.filter(\.isSpeechActive).count) total=\(silent.observations.count)")
    print(lines.joined(separator: "\n"))
default:
    fatalError("usage")
}

final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var sample: ParakeetLiveWorkSample?
    func set(_ value: ParakeetLiveWorkSample) { lock.lock(); sample = value; lock.unlock() }
    func get() -> ParakeetLiveWorkSample? { lock.lock(); defer { lock.unlock() }; return sample }
}
