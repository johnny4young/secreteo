import CryptoKit
import Foundation
import LocalModelStore
import Synchronization
import XCTest

@testable import DictationSession

@MainActor
final class DictationModelListTests: XCTestCase {
    private let secreteo = StoreConsumer(bundleID: "com.example.secreteo-tests", displayName: "Secreteo")
    private let other = StoreConsumer(bundleID: "com.example.other-tests", displayName: "Other")
    private let bytes = Data(repeating: 5, count: 4_096)

    private func makeScratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DictationModelListTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func scratchDefaults() throws -> UserDefaults {
        let name = "DictationModelListTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    private var manifest: ModelManifest {
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return ModelManifest(
            id: "sample", displayName: "Sample", resolveBase: URL(string: "https://example.invalid")!,
            revision: "a", artifacts: [ModelArtifact(path: "model.bin", sha256: digest, sizeBytes: bytes.count)],
            minimumRAMGB: 1, license: "MIT")
    }

    private func store(_ root: URL, _ consumer: StoreConsumer) throws -> LocalModelStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingURLProtocol.self]
        return try LocalModelStore(
            location: .directory(root), consumer: consumer, session: URLSession(configuration: configuration))
    }

    /// Installs from a local folder, so the store never needs the network.
    private func install(_ store: LocalModelStore) async throws {
        let seed = try makeScratch()
        try bytes.write(to: seed.appendingPathComponent("model.bin"))
        try await store.ensureAvailable(manifest, seeds: [seed])
    }

    private func models(_ store: LocalModelStore, defaults: UserDefaults? = nil) throws -> DictationModels {
        let manifest = manifest
        return DictationModels.live(
            store: store, defaults: try defaults ?? scratchDefaults(), seedRoot: try makeScratch(),
            manifests: { _ in manifest })
    }

    private func first(_ models: DictationModels) async throws -> DictationModelEntry {
        let entries = await models.inventory()
        return try XCTUnwrap(entries.first)
    }

    override func setUp() {
        super.setUp()
        CountingURLProtocol.requests.withLock { $0 = 0 }
    }

    func testAdoptingAnotherAppsModelWritesThisAppsClaimWithoutARequest() async throws {
        let root = try makeScratch()
        try await install(try store(root, other))
        let models = try models(try store(root, secreteo))
        let before = try await first(models)
        XCTAssertFalse(before.isClaimedByThisApp)

        await models.adopt(.speech)

        let after = try await first(models)
        XCTAssertTrue(after.isClaimedByThisApp)
        XCTAssertEqual(after.sharedWith, ["Other"])
        XCTAssertEqual(CountingURLProtocol.requests.withLock { $0 }, 0)
    }

    func testAdoptingAMissingModelNeitherClaimsNorDownloads() async throws {
        let models = try models(try store(try makeScratch(), secreteo))
        await models.adopt(.speech)
        let entries = await models.inventory()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(CountingURLProtocol.requests.withLock { $0 }, 0)
    }

    /// The path adoption takes when files vanish under the install lock.
    func testTheDownloadVetoStopsAnInstallBeforeItsFirstRequest() async throws {
        let store = try store(try makeScratch(), secreteo)
        let manifest = manifest
        let result = await Task { try await store.ensureAvailableWithoutDownloading(manifest) }.result
        XCTAssertThrowsError(try result.get())
        XCTAssertEqual(CountingURLProtocol.requests.withLock { $0 }, 0)
        let inventory = await store.inventory()
        XCTAssertTrue(inventory.isEmpty)
    }

    func testRemovingASharedModelKeepsItForTheOtherApp() async throws {
        let root = try makeScratch()
        try await install(try store(root, other))
        let mine = try store(root, secreteo)
        try await install(mine)
        let defaults = try scratchDefaults()
        let models = try models(mine, defaults: defaults)
        await models.remember(.speech, true)
        let entry = try await first(models)

        let outcome = try await models.release(entry.id)

        XCTAssertEqual(outcome, .keptForOthers)
        let left = try await first(models)
        XCTAssertFalse(left.isClaimedByThisApp)
        XCTAssertEqual(left.sharedWith, ["Other"])
        let remembered = await models.wasVerified(.speech)
        XCTAssertFalse(remembered, "A removed model must not read as ready on the next launch")
    }

    func testRemovingAModelOnlyThisAppKeepsDeletesIt() async throws {
        let mine = try store(try makeScratch(), secreteo)
        try await install(mine)
        let models = try models(mine)
        let entry = try await first(models)
        XCTAssertEqual(entry.id, manifest.shelfKey, "The key format matches the store's")
        XCTAssertEqual(entry.bytes, bytes.count)

        let outcome = try await models.release(entry.id)

        XCTAssertEqual(outcome, .removed)
        let entries = await models.inventory()
        XCTAssertTrue(entries.isEmpty)
    }

    func testOnlyAModelThisAppPinsCanBeRemoved() async throws {
        let models = try models(try store(try makeScratch(), secreteo))
        do {
            _ = try await models.release("someone-else@a-b")
            XCTFail("Removed a model this app does not pin")
        } catch {
            XCTAssertEqual(error as? DictationModelRemoval.Failure, .notThisAppsModel)
        }
    }

    func testAnotherBuildWithTheSameNameStillShowsAsSharing() async throws {
        let root = try makeScratch()
        let dev = StoreConsumer(bundleID: "com.example.secreteo-dev-tests", displayName: secreteo.displayName)
        try await install(try store(root, dev))
        let mine = try store(root, secreteo)
        try await install(mine)
        let entry = try await first(models(mine))
        XCTAssertEqual(entry.sharedWith, ["Secreteo"], "Claims list names, and only one of them is this app's")
    }

    func testAFailedRemovalSaysSoAndKeepsTheRow() async {
        let entry = DictationModelEntry(id: "k", name: "K", bytes: 1, sharedWith: [], isClaimedByThisApp: true)
        var models = DictationModels.heldDownload
        models.inventory = { [entry] }
        models.release = { _ in throw DictationModelRemoval.Failure.notThisAppsModel }
        let list = DictationModelList()

        await list.remove(entry, models: models)

        XCTAssertTrue(list.removalFailed)
        XCTAssertEqual(list.entries, [entry])
    }
}

/// Counts every request, and fails it, so a test can prove nothing was downloaded.
private final class CountingURLProtocol: URLProtocol {
    static let requests = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0 += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
