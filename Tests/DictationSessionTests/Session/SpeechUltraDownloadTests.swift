import Foundation
import Synchronization
import XCTest

@testable import DictationSession

@MainActor
final class SpeechUltraDownloadTests: XCTestCase {
    private struct InstallFailed: Error {}

    private final class Record: Sendable {
        let installed = Mutex<[DictationModels.Part]>([])
        let told = Mutex(0)
    }

    private func models(
        verified: Bool = false, remembered: Bool = false, fails: Bool = false, record: Record = Record()
    ) -> DictationModels {
        DictationModels(
            isVerified: { _ in verified },
            wasVerified: { _ in remembered },
            remember: { _, _ in },
            install: { part, placedBytes in
                placedBytes(50)
                if fails { throw InstallFailed() }
                record.installed.withLock { $0.append(part) }
            },
            size: { _ in 100 },
            collectUnused: {})
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }

    func testADownloadInstallsOnlyUltraAndTellsTheFeature() async {
        let record = Record()
        let download = SpeechUltraDownload()

        download.download(models(record: record)) { record.told.withLock { $0 += 1 } }

        await waitUntil { download.state == .ready }
        XCTAssertEqual(record.installed.withLock { $0 }, [.speechUltra])
        XCTAssertEqual(record.told.withLock { $0 }, 1)
        XCTAssertNil(download.fraction)
    }

    func testAFailedDownloadSaysSo() async {
        let record = Record()
        let download = SpeechUltraDownload()

        download.download(models(fails: true)) { record.told.withLock { $0 += 1 } }

        await waitUntil { download.state == .failed }
        XCTAssertEqual(record.told.withLock { $0 }, 0)
    }

    func testAReportFromAnEarlierDownloadIsDropped() async {
        let download = SpeechUltraDownload()
        download.download(models(fails: true)) {}
        await waitUntil { download.state == .failed }
        let earlier = download.generation
        download.download(models(fails: true)) {}

        download.progressed(0.9, generation: earlier)

        XCTAssertNotEqual(download.fraction, 0.9)
    }

    func testARememberedUltraThatNoLongerHashesReadsMissing() async {
        let download = SpeechUltraDownload()

        await download.refresh(models(verified: false, remembered: true))

        XCTAssertEqual(download.state, .missing)
    }
}
