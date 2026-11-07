import Foundation
import Synchronization
import XCTest

@testable import DictationSession

final class DictationModelsProgressTests: XCTestCase {
    private func models(
        verified: Set<DictationModels.Part>, sizes: [DictationModels.Part: Int], reports: [Int]
    ) -> DictationModels {
        DictationModels(
            isVerified: { verified.contains($0) },
            wasVerified: { _ in false },
            remember: { _, _ in },
            install: { _, placedBytes in reports.forEach(placedBytes) },
            size: { sizes[$0] ?? 0 },
            collectUnused: {})
    }

    func testProgressWeighsEachPartByItsSize() async throws {
        let seen = Mutex<[Double]>([])
        let models = models(verified: [], sizes: [.speech: 300, .speechDetector: 100], reports: [0, 100])

        try await models.installMissing { fraction in seen.withLock { $0.append(fraction) } }

        XCTAssertEqual(seen.withLock { $0 }, [0, 100.0 / 400, 300.0 / 400, 400.0 / 400])
    }

    func testReportsWithinOnePercentAreDropped() async throws {
        let seen = Mutex<[Double]>([])
        let models = models(verified: [.speechDetector], sizes: [.speech: 1_000], reports: [1, 5, 9, 10, 11, 1_000])

        try await models.installMissing { fraction in seen.withLock { $0.append(fraction) } }

        XCTAssertEqual(seen.withLock { $0 }, [0.001, 0.01, 1])
    }

    func testUltraIsNotPartOfTheRequiredInstall() async throws {
        let installed = Mutex<[DictationModels.Part]>([])
        let models = DictationModels(
            isVerified: { _ in false }, wasVerified: { _ in false }, remember: { _, _ in },
            install: { part, _ in installed.withLock { $0.append(part) } },
            size: { _ in 100 }, collectUnused: {})

        try await models.installMissing()

        XCTAssertEqual(installed.withLock { $0 }, DictationModels.Part.required)
        XCTAssertFalse(DictationModels.Part.required.contains(.speechUltra))
    }

    func testAVerifiedPartIsLeftOutOfTheTotal() async throws {
        let seen = Mutex<[Double]>([])
        let models = models(verified: [.speech], sizes: [.speech: 300, .speechDetector: 100], reports: [50])

        try await models.installMissing { fraction in seen.withLock { $0.append(fraction) } }

        XCTAssertEqual(seen.withLock { $0 }, [0.5])
    }
}
