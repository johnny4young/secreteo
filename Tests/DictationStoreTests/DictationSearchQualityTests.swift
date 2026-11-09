import Foundation
import XCTest

final class DictationSearchQualityTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/DictationSearch/public-synthetic-v1.json")

    /// Letter counts stand in for a sentence model, so the producer runs without one.
    private static let letterCounts: DictationSearchBenchmark.Embed = { texts in
        texts.map { text in
            var counts = [Float](repeating: 0, count: 26)
            for scalar in text.lowercased().unicodeScalars where ("a"..."z").contains(scalar) {
                counts[Int(scalar.value) - 97] += 1
            }
            let norm = counts.reduce(0) { $0 + $1 * $1 }.squareRoot()
            return norm > 0 ? counts.map { $0 / norm } : counts
        }
    }

    func testObservationsCoverEveryQueryWithFixtureIdentitiesAndNoText() async throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let fixture = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dictations = try XCTUnwrap(fixture?["dictations"] as? [[String: Any]])
        let queries = try XCTUnwrap(fixture?["queries"] as? [[String: Any]])
        let ids = Set(dictations.compactMap { $0["id"] as? String }.map { $0.uppercased() })

        let observations = try await DictationSearchBenchmark.observe(
            fixtureData: data, embed: Self.letterCounts, profileFingerprint: "letter-counts",
            build: "test", commit: String(repeating: "0", count: 40), scales: [200])

        XCTAssertEqual(observations.queries.count, queries.count)
        let returned = observations.queries.flatMap { $0.lexical + $0.semantic.map(\.id) + $0.semanticCentered.map(\.id) }
        XCTAssertTrue(Set(returned).isSubset(of: ids), "only fixture dictations come back")
        XCTAssertTrue(observations.queries.contains { !$0.lexical.isEmpty }, "the history search found something")
        XCTAssertTrue(observations.queries.allSatisfy { $0.lexical.count <= DictationSearchBenchmark.resultLimit })
        XCTAssertEqual(observations.resources.scale.map(\.dictations), [200])
        let encoded = String(decoding: try JSONEncoder().encode(observations), as: UTF8.self)
        for text in (dictations + queries).compactMap({ $0["text"] as? String }) {
            XCTAssertFalse(encoded.contains(text), "observations hold identities and numbers, never text")
        }
    }

    /// Explicit local lane: the system's sentence model, never downloaded unless asked.
    func testPublicSearchObservations() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["SECRETEO_SEARCH_OBSERVATIONS"] else {
            throw XCTSkip("explicit dictation search observation not requested")
        }
        let outputURL = URL(fileURLWithPath: output)
        var isDirectory: ObjCBool = false
        guard output.hasPrefix("/"), !FileManager.default.fileExists(atPath: output),
              FileManager.default.fileExists(
                atPath: outputURL.deletingLastPathComponent().path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let commit = environment["SECRETEO_SEARCH_COMMIT"], commit.utf8.count == 40,
              commit.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else {
            XCTFail("search observation requires a new absolute output in an existing folder and a 40-character commit")
            return
        }
        // A mistyped scale must fail, or the latency gate would read a smaller corpus.
        let entries = (environment["SECRETEO_SEARCH_SCALES"] ?? "1000,10000").split(separator: ",", omittingEmptySubsequences: false)
        let scales = entries.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !scales.isEmpty, scales.count == entries.count, scales.allSatisfy({ (1...100_000).contains($0) }) else {
            XCTFail("scales are 1 to 100000")
            return
        }
        let embedder = try SentenceEmbedder()
        try await embedder.prepare(allowAssetDownload: environment["SECRETEO_SEARCH_ASSET_DOWNLOAD"] == "1")
        let observations = try await DictationSearchBenchmark.observe(
            fixtureData: try Data(contentsOf: Self.fixtureURL),
            embed: { try await embedder.embed($0) },
            profileFingerprint: await embedder.profileFingerprint,
            build: environment["SECRETEO_SEARCH_BUILD"] ?? "local",
            commit: commit,
            scales: scales)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(observations).write(to: outputURL, options: [.withoutOverwriting])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output)
    }
}
