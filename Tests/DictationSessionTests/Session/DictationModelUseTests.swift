import Foundation
import Synchronization
import XCTest

@testable import DictationSession

@MainActor
final class DictationModelUseTests: XCTestCase {
    private final class Adopted: Sendable {
        let parts = Mutex<[DictationModels.Part]>([])
    }

    private func feature(enabled: Bool, adopted: Adopted = Adopted()) throws -> DictationFeature {
        let suite = "DictationModelUseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(enabled, forKey: DictationController.defaultsKey)
        var models = DictationModels.heldDownload
        models.isVerified = { _ in true }
        models.adopt = { part in
            adopted.parts.withLock { $0.append(part) }
            return true
        }
        models.key = { "\($0)" }
        return try DictationFeature(
            usesTemporaryStore: true, arguments: [], defaults: defaults,
            environment: .disposable(permissionsAreMissing: false, models: models))
    }

    func testOnlyDictationInUseClaimsAModel() async throws {
        let off = Adopted()
        try await feature(enabled: false, adopted: off).refreshReadiness()
        XCTAssertEqual(off.parts.withLock { $0 }, [], "A model removed while dictation is off stays removed")

        let on = Adopted()
        try await feature(enabled: true, adopted: on).refreshReadiness()
        XCTAssertEqual(Set(on.parts.withLock { $0 }), [.speech, .speechDetector])
    }

    func testRemoveIsOfferedOnlyForAPinnedModelDictationIsNotUsing() throws {
        let entry = { (key: String, claimed: Bool) in
            DictationModelEntry(id: key, name: key, bytes: 1, sharedWith: [], isClaimedByThisApp: claimed)
        }
        let off = try feature(enabled: false)
        XCTAssertTrue(off.canRemove(entry("speech", true)))
        XCTAssertFalse(off.canRemove(entry("speech", false)), "Not this app's claim")
        XCTAssertFalse(off.canRemove(entry("an-older-revision", true)), "Its retired claim expires on its own")

        let on = try feature(enabled: true)
        XCTAssertFalse(on.canRemove(entry("speech", true)), "Dictation would claim it again")
        XCTAssertFalse(on.canRemove(entry("speechDetector", true)))
    }

    func testRemovingAModelReleasesOnlyTheWarmModelThatMayHoldIt() throws {
        let entry = { (key: String) in
            DictationModelEntry(id: key, name: key, bytes: 1, sharedWith: [], isClaimedByThisApp: true)
        }
        let feature = try feature(enabled: true)
        let models = try XCTUnwrap(feature.environment.models)

        feature.speechEngineBinding.wrappedValue = .parakeet
        XCTAssertNil(feature.warmPart(loadedFrom: entry("speechUltra"), models: models), "v3 stays warm")
        XCTAssertEqual(feature.warmPart(loadedFrom: entry("speech"), models: models), .speech)
        XCTAssertEqual(feature.warmPart(loadedFrom: entry("speechDetector"), models: models), .speechDetector)

        feature.speechEngineBinding.wrappedValue = .parakeetUltra
        XCTAssertEqual(feature.warmPart(loadedFrom: entry("speechUltra"), models: models), .speechUltra)
        XCTAssertEqual(feature.warmPart(loadedFrom: entry("speech"), models: models), .speech, "Ultra falls back to v3")
        XCTAssertNil(feature.warmPart(loadedFrom: entry("an-older-revision"), models: models))
    }

    func testRepeatedReadinessRefreshDoesNotReadoptAlreadyClaimedModels() async throws {
        let adopted = Adopted()
        let verified = Mutex(true)
        let adoptSucceeds = Mutex(false)
        let suite = "DictationModelUseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DictationController.defaultsKey)
        var models = DictationModels.heldDownload
        models.isVerified = { _ in verified.withLock { $0 } }
        models.adopt = { part in
            adopted.parts.withLock { $0.append(part) }
            return adoptSucceeds.withLock { $0 }
        }
        models.key = { "\($0)" }
        let feature = try DictationFeature(
            usesTemporaryStore: true, arguments: [], defaults: defaults,
            environment: .disposable(permissionsAreMissing: false, models: models))

        // A failed adopt is retried on the next poll rather than cached as claimed.
        await feature.refreshReadiness()
        XCTAssertEqual(adopted.parts.withLock { $0 }.count, 2)
        adoptSucceeds.withLock { $0 = true }
        await feature.refreshReadiness()
        await feature.refreshReadiness()
        XCTAssertEqual(adopted.parts.withLock { $0 }.count, 4, "Steady-state polls must not re-adopt claimed models")

        // A model that disappears and returns is adopted again.
        verified.withLock { $0 = false }
        await feature.refreshReadiness()
        verified.withLock { $0 = true }
        await feature.refreshReadiness()
        XCTAssertEqual(adopted.parts.withLock { $0 }.count, 6)

        // Switching engines clears the cached adoption set.
        // The change starts its own refresh, whose adopt may still be on its way.
        feature.speechEngineChanged()
        await feature.refreshReadiness()
        let readopted = await TestPolling.until { adopted.parts.withLock { $0 }.count >= 8 }
        XCTAssertTrue(readopted)
        await feature.refreshReadiness()
        XCTAssertEqual(adopted.parts.withLock { $0 }.count, 8)
    }
}
