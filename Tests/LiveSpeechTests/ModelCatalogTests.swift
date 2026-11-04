import Foundation
import LocalModelStore
import XCTest

@testable import LiveSpeech

final class ModelCatalogTests: XCTestCase {
    func testParakeetDescriptorIsWellFormed() {
        let model = ModelCatalog.parakeetTdtV3
        XCTAssertEqual(model.artifacts.count, 21)
        for artifact in model.artifacts {
            XCTAssertEqual(artifact.sha256.count, 64, "sha256 must be 64 hex chars: \(artifact.path)")
            XCTAssertTrue(
                artifact.sha256.allSatisfy { $0.isHexDigit && (!$0.isLetter || $0.isLowercase) },
                "sha256 must be lowercase hex: \(artifact.path)")
            XCTAssertGreaterThan(artifact.sizeBytes, 0)
            XCTAssertFalse(artifact.path.hasPrefix("/"), "artifact paths are relative")
        }

        // The exact file set FluidAudio's v3 int8 loader requires.
        let bundles = Set(model.artifacts.map { $0.path.components(separatedBy: "/").first! })
        XCTAssertEqual(
            bundles,
            [
                "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
                "JointDecisionv3.mlmodelc", "parakeet_vocab.json",
            ])

        // int8 subset only: ~483 MB, not the full 3 GB repo.
        XCTAssertGreaterThan(model.totalSizeBytes, 450_000_000)
        XCTAssertLessThan(model.totalSizeBytes, 550_000_000)
    }

    func testDownloadURLsArePinnedToARevision() {
        let model = ModelCatalog.parakeetTdtV3
        XCTAssertFalse(model.revision.isEmpty)
        XCTAssertFalse(model.resolveBase.absoluteString.contains("/main"))
        XCTAssertTrue(model.resolveBase.absoluteString.contains(model.revision))

        let url = model.downloadURL(for: model.artifacts[0]).absoluteString
        XCTAssertTrue(url.hasPrefix(model.resolveBase.absoluteString))
        XCTAssertTrue(url.hasSuffix(model.artifacts[0].path))
    }

    func testSileroDescriptorPinsOnlyTheUnifiedStreamingModel() {
        let model = ModelCatalog.sileroVAD
        XCTAssertEqual(model.license, "MIT")
        XCTAssertEqual(model.artifacts.count, 5)
        XCTAssertTrue(model.resolveBase.absoluteString.contains(model.revision))
        XCTAssertFalse(model.resolveBase.absoluteString.contains("/main"))
        XCTAssertEqual(
            Set(model.artifacts.map(\.path)),
            Set([
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/analytics/coremldata.bin",
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/coremldata.bin",
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/metadata.json",
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/model.mil",
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/weights/weight.bin",
            ]))
        XCTAssertTrue(
            model.artifacts.allSatisfy { $0.path.hasPrefix(ModelCatalog.sileroVADBundleDirectory + "/") },
            "the loader opens the same bundle directory the catalog verifies")
        XCTAssertLessThan(model.totalSizeBytes, 1_100_000)
        XCTAssertTrue(model.artifacts.allSatisfy { $0.sha256.count == 64 })
    }
}
