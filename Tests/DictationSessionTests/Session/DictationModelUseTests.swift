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
        models.adopt = { part in adopted.parts.withLock { $0.append(part) } }
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
}
