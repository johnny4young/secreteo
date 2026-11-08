import CryptoKit
import FluidAudio
import Foundation
import LocalModelStore
import SpeechCore
import Testing

@testable import LiveSpeech

@Suite(.timeLimit(.minutes(1)))
struct SileroModelLeaseTests {
    enum PreparationFailure: Error { case expected }

    @Test
    func preparationAndResidentDetectorKeepTheirModelOnDisk() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        var detector: SileroVoiceActivityDetector? = try await SileroVoiceActivityDetector.loadLeased(
            from: fixture.store, manifest: Fixture.manifest, channel: .microphone
        ) { directory in
            #expect(directory == fixture.directory)
            let removal = try await fixture.peer.remove(Fixture.manifest, scope: .allConsumers)
            #expect(removal == .deferred)
            return Self.infer
        }
        weak var original = detector
        defer { original = nil }
        #expect(try await fixture.peer.collectGarbage().removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.path))

        detector = nil
        #expect(original == nil)
        #expect(try await fixture.peer.collectGarbage().removed.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test
    func failureDuringPreparationReleasesTheLease() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        await #expect(throws: PreparationFailure.expected) {
            _ = try await SileroVoiceActivityDetector.loadLeased(
                from: fixture.store, manifest: Fixture.manifest, channel: .microphone
            ) { _ in
                let removal = try await fixture.peer.remove(Fixture.manifest, scope: .allConsumers)
                #expect(removal == .deferred)
                throw PreparationFailure.expected
            }
        }
        #expect(try await fixture.peer.collectGarbage().removed.count == 1)
    }

    @Test
    func cancelledPreparationKeepsTheLeaseUntilTheLoaderReturns() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        let hold = NoncooperativeInference()
        defer { signal.finish() }
        let task = Task {
            try await SileroVoiceActivityDetector.loadLeased(
                from: fixture.store, manifest: Fixture.manifest, channel: .microphone
            ) { _ in
                signal.yield(())
                await hold.wait()
                return Self.infer
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        let removal = try await fixture.peer.remove(Fixture.manifest, scope: .allConsumers)
        await hold.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(removal == .deferred)
        #expect(try await fixture.peer.collectGarbage().removed.count == 1)
    }

    @Test
    func cancelledProcessingKeepsTheLeaseUntilInferenceActuallyReturns() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        let hold = NoncooperativeInference()
        defer { signal.finish() }
        var detector: SileroVoiceActivityDetector? = try await SileroVoiceActivityDetector.loadLeased(
            from: fixture.store, manifest: Fixture.manifest, channel: .microphone
        ) { _ in
            { frame, state in
                signal.yield(())
                await hold.wait()
                return try await Self.infer(frame, state)
            }
        }
        let task = Task { [detector = try #require(detector)] in
            try await detector.process(AudioChunk(
                channel: .microphone, samples: [Float](repeating: 0, count: 4_096),
                sampleRate: 16_000, timestamp: 0))
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        detector = nil
        task.cancel()
        let removal = try await fixture.peer.remove(Fixture.manifest, scope: .allConsumers)
        await hold.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(removal == .deferred)
        #expect(try await fixture.peer.collectGarbage().removed.count == 1)
    }

    @Test
    func corruptModelNeverReachesPreparationOrDownloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalModelStore(
            location: .directory(root),
            consumer: StoreConsumer(bundleID: "com.example.secreteo-test", displayName: "Test"))
        let directory = try await store.directory(for: Fixture.manifest)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let artifact = directory.appendingPathComponent("model.bin")
        let corrupt = Data("not the model".utf8)
        try corrupt.write(to: artifact)
        await #expect(throws: VoiceActivityDetectionError.modelNotInstalled) {
            _ = try await SileroVoiceActivityDetector.loadLeased(
                from: store, manifest: Fixture.manifest, channel: .microphone
            ) { _ in
                Issue.record("Corrupt bytes must not reach model preparation")
                return Self.infer
            }
        }
        #expect(try Data(contentsOf: artifact) == corrupt)
    }

    private static let infer: SileroVoiceActivityDetector.Inference = { frame, state in
        var next = state
        next.processedSamples += frame.count
        return VadStreamResult(state: next, event: nil, probability: 0.01)
    }

    private actor NoncooperativeInference {
        private var resume: CheckedContinuation<Void, Never>?
        private var released = false

        func wait() async {
            guard !released else { return }
            await withCheckedContinuation { resume = $0 }
        }

        func release() {
            released = true
            resume?.resume()
            resume = nil
        }
    }

    private struct Fixture: Sendable {
        let root: URL
        let directory: URL
        let store: LocalModelStore
        let peer: LocalModelStore

        static let bytes = Data("synthetic vad".utf8)
        static let manifest = ModelManifest(
            id: "test", displayName: "Test", resolveBase: URL(string: "https://example.invalid")!, revision: "a",
            artifacts: [ModelArtifact(
                path: "model.bin",
                sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                sizeBytes: bytes.count)],
            minimumRAMGB: 1, license: "MIT")

        init() async throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            store = try LocalModelStore(
                location: .directory(root),
                consumer: StoreConsumer(bundleID: "com.example.secreteo-test", displayName: "Test"))
            peer = try LocalModelStore(
                location: .directory(root),
                consumer: StoreConsumer(bundleID: "com.example.peer-test", displayName: "Peer"))
            let seed = root.appendingPathComponent("seed")
            try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
            try Self.bytes.write(to: seed.appendingPathComponent("model.bin"))
            directory = try await store.ensureAvailable(Self.manifest, seeds: [seed])
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }
}
