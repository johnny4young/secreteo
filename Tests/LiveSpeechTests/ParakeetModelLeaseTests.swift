import CryptoKit
import Foundation
import LocalModelStore
import SpeechCore
import Testing

@testable import LiveSpeech

@Suite(.timeLimit(.minutes(1)))
struct ParakeetModelLeaseTests {
    enum PreparationFailure: Error { case expected }

    @Test
    func leaseProtectsLoadingAndObserverUntilTheLastEngineIsReleased() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        var engine: ParakeetEngine? = try await ParakeetEngine.loadLeased(
            from: fixture.store, manifest: fixture.manifest, checkpoint: .ultra
        ) { directory, checkpoint in
            #expect(directory == fixture.directory)
            #expect(checkpoint == .ultra)
            let removal = try await fixture.peer.remove(fixture.manifest, scope: .allConsumers)
            #expect(removal == .deferred)
            return Self.engine(checkpoint: checkpoint)
        }
        var observed = engine?.observingLiveWork { _ in }
        weak var original = engine
        defer { original = nil }
        engine = nil
        #expect(original == nil)
        #expect(observed?.checkpoint == .ultra)
        #expect(try await fixture.peer.collectGarbage().removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.path))

        observed = nil
        #expect(try await fixture.peer.collectGarbage().removed.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test
    func failedPreparationReleasesTheLease() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        await #expect(throws: PreparationFailure.expected) {
            _ = try await ParakeetEngine.loadLeased(
                from: fixture.store, manifest: fixture.manifest, checkpoint: .v3
            ) { _, _ in
                let removal = try await fixture.peer.remove(fixture.manifest, scope: .allConsumers)
                #expect(removal == .deferred)
                throw PreparationFailure.expected
            }
        }
        #expect(try await fixture.peer.collectGarbage().removed.count == 1)
    }

    @Test(arguments: [ParakeetCheckpoint.v3, .ultra])
    func missingModelNeverDownloads(_ checkpoint: ParakeetCheckpoint) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalModelStore(
            location: .directory(root),
            consumer: StoreConsumer(bundleID: "com.example.secreteo-test", displayName: "Test"))
        await #expect(throws: (any Error).self) {
            _ = try await ParakeetEngine.load(from: store, checkpoint: checkpoint)
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test
    func cancelledPreparationReleasesTheLease() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        let (hold, release) = AsyncStream.makeStream(of: Void.self)
        defer { signal.finish(); release.finish() }
        let task = Task {
            try await ParakeetEngine.loadLeased(
                from: fixture.store, manifest: fixture.manifest, checkpoint: .v3
            ) { _, _ in
                signal.yield(())
                for await _ in hold { break }
                return Self.engine()
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        release.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await fixture.peer.remove(fixture.manifest, scope: .allConsumers) == .removed)
    }

    @Test
    func liveJobKeepsTheLeaseAfterItsEngineIsReleased() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        let (hold, release) = AsyncStream.makeStream(of: Void.self)
        defer { signal.finish(); release.finish() }
        var engine: ParakeetEngine? = try await ParakeetEngine.loadLeased(
            from: fixture.store, manifest: fixture.manifest, checkpoint: .v3
        ) { _, _ in
            ParakeetEngine(
                prepareLiveManager: { _ in
                    signal.yield(())
                    for await _ in hold { break }
                    throw PreparationFailure.expected
                },
                prepareBatchManager: { _ in throw PreparationFailure.expected })
        }
        let output = try #require(engine).transcribe(AsyncStream<AudioChunk> { $0.finish() }, hints: .init())
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        engine = nil
        #expect(try await fixture.peer.remove(fixture.manifest, scope: .allConsumers) == .deferred)
        release.finish()
        await #expect(throws: PreparationFailure.expected) {
            for try await _ in output { Issue.record("Preparation failure cannot emit words") }
        }
    }

    private static func engine(checkpoint: ParakeetCheckpoint = .v3) -> ParakeetEngine {
        ParakeetEngine(
            prepareLiveManager: { _ in throw PreparationFailure.expected },
            prepareBatchManager: { _ in throw PreparationFailure.expected }, checkpoint: checkpoint)
    }

    private struct Fixture: Sendable {
        let root: URL
        let directory: URL
        let store: LocalModelStore
        let peer: LocalModelStore
        var manifest: ModelManifest { Self.manifest }

        static let bytes = Data("synthetic model".utf8)
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
