import CryptoKit
import DictationKit
import Foundation
import GRDB
import SpeechCore

@testable import DictationStore

struct DictationSearchFixture: Decodable {
    struct Dictation: Decodable {
        let id: UUID
        let createdAt: Date
        let applicationName: String
        let text: String
    }

    struct Query: Decodable {
        let id: UUID
        let text: String
    }

    let kind: String
    let dictations: [Dictation]
    let queries: [Query]
}

enum DictationSearchBenchmarkError: Error, Equatable {
    case invalidFixture
    case invalidEmbedding
}

struct DictationSearchObservations: Encodable, Equatable {
    struct Hit: Encodable, Equatable {
        let id: String
        let similarity: Double
    }

    struct Query: Encodable, Equatable {
        let id: String
        let lexical: [String]
        let semantic: [Hit]
        /// The same scan after subtracting the corpus mean vector and renormalizing.
        let semanticCentered: [Hit]
        /// Query rewriting is not part of Secreteo, so these lanes are always absent.
        let lexicalExpandedMeeting: [String]?
        let lexicalExpandedDictation: [String]?
    }

    struct Percentiles: Encodable, Equatable {
        let p50: Double
        let p95: Double
    }

    struct Scale: Encodable, Equatable {
        let dictations: Int
        let lexicalP95Milliseconds: Double
        let semanticP95Milliseconds: Double
        let vectorBytes: Int
    }

    struct Resources: Encodable, Equatable {
        let dictationCount: Int
        let embedMilliseconds: Percentiles
        let lexicalQueryMilliseconds: Percentiles
        let semanticQueryMilliseconds: Percentiles
        let queriesWithParsedFilters: Int
        let expansionMeetingMilliseconds: Percentiles?
        let expansionDictationMilliseconds: Percentiles?
        let expansionDictationFailures: Int
        let scale: [Scale]
    }

    var schemaVersion = 1
    var kind = "dictation-search-observations"
    let fixtureSHA256: String
    let build: String
    let commit: String
    let embeddingProfileFingerprint: String
    let dimension: Int
    let queries: [Query]
    let resources: Resources
}

/// Runs the shipped history search and a cosine scan over normalized vectors in
/// a disposable store; the user's library is never opened. The observations
/// hold identities and numbers, never text.
enum DictationSearchBenchmark {
    typealias Embed = @Sendable ([String]) async throws -> [[Float]]

    static let resultLimit = 12

    static func observe(
        fixtureData: Data,
        embed: @escaping Embed,
        profileFingerprint: String,
        build: String,
        commit: String,
        scales: [Int]
    ) async throws -> DictationSearchObservations {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixture = try decoder.decode(DictationSearchFixture.self, from: fixtureData)
        guard fixture.kind == "dictation-search-fixture", !fixture.dictations.isEmpty, !fixture.queries.isEmpty
        else { throw DictationSearchBenchmarkError.invalidFixture }
        let now = (fixture.dictations.map(\.createdAt).max() ?? Date()).addingTimeInterval(3_600)
        let corpus = try await Corpus.seed(fixture.dictations, now: now)
        let embedded = try await Embedded.make(fixture.dictations, embed: embed)

        var lexicalTimes: [Double] = []
        var semanticTimes: [Double] = []
        var queries: [DictationSearchObservations.Query] = []
        for query in fixture.queries {
            var started = ContinuousClock.now
            let lexical = try await corpus.lexical(query.text)
            lexicalTimes.append(milliseconds(since: started))
            started = ContinuousClock.now
            let raw = try await vector(for: query.text, embed: embed)
            let semantic = try semanticHits(raw, vectors: embedded.vectors, ids: embedded.ids)
            semanticTimes.append(milliseconds(since: started))
            let centered = try semanticHits(
                centeredVector(raw, mean: embedded.mean), vectors: embedded.centered, ids: embedded.ids)
            queries.append(.init(
                id: query.id.uuidString, lexical: lexical, semantic: semantic, semanticCentered: centered,
                lexicalExpandedMeeting: nil, lexicalExpandedDictation: nil))
        }
        var scaleRows: [DictationSearchObservations.Scale] = []
        for size in scales {
            scaleRows.append(try await scale(size, fixture: fixture, vectors: embedded.vectors, embed: embed, now: now))
        }
        return DictationSearchObservations(
            fixtureSHA256: SHA256.hash(data: fixtureData).map { String(format: "%02x", $0) }.joined(),
            build: build,
            commit: commit,
            embeddingProfileFingerprint: profileFingerprint,
            dimension: embedded.vectors[0].count,
            queries: queries,
            resources: .init(
                dictationCount: fixture.dictations.count,
                embedMilliseconds: percentiles(embedded.times),
                lexicalQueryMilliseconds: percentiles(lexicalTimes),
                semanticQueryMilliseconds: percentiles(semanticTimes),
                queriesWithParsedFilters: 0,
                expansionMeetingMilliseconds: nil,
                expansionDictationMilliseconds: nil,
                expansionDictationFailures: 0,
                scale: scaleRows))
    }

    private struct Embedded {
        let vectors: [[Float]]
        let centered: [[Float]]
        let mean: [Float]
        let ids: [String]
        let times: [Double]

        static func make(_ dictations: [DictationSearchFixture.Dictation], embed: Embed) async throws -> Self {
            var vectors: [[Float]] = []
            var times: [Double] = []
            for dictation in dictations {
                let started = ContinuousClock.now
                vectors.append(try await vector(for: dictation.text, embed: embed))
                times.append(milliseconds(since: started))
            }
            guard vectors.allSatisfy({ $0.count == vectors[0].count }) else {
                throw DictationSearchBenchmarkError.invalidEmbedding
            }
            let mean = meanVector(vectors)
            return Self(
                vectors: vectors, centered: vectors.map { centeredVector($0, mean: mean) }, mean: mean,
                ids: dictations.map(\.id.uuidString), times: times)
        }
    }

    /// The fixture replicated to `size` dictations: lexical in a store of that
    /// size, semantic as a scan over that many copied vectors.
    private static func scale(
        _ size: Int, fixture: DictationSearchFixture, vectors: [[Float]], embed: @escaping Embed, now: Date
    ) async throws -> DictationSearchObservations.Scale {
        let replicas = (0..<size).map { index in
            let source = fixture.dictations[index % fixture.dictations.count]
            return DictationSearchFixture.Dictation(
                id: UUID(), createdAt: now.addingTimeInterval(-Double(index + 1)),
                applicationName: source.applicationName, text: source.text)
        }
        let corpus = try await Corpus.seed(replicas, now: now)
        let scaledVectors = (0..<size).map { vectors[$0 % vectors.count] }
        let scaledIDs = replicas.map(\.id.uuidString)
        var lexicalTimes: [Double] = []
        var semanticTimes: [Double] = []
        for query in fixture.queries {
            var started = ContinuousClock.now
            _ = try await corpus.lexical(query.text)
            lexicalTimes.append(milliseconds(since: started))
            started = ContinuousClock.now
            _ = try semanticHits(try await vector(for: query.text, embed: embed), vectors: scaledVectors, ids: scaledIDs)
            semanticTimes.append(milliseconds(since: started))
        }
        return .init(
            dictations: size,
            lexicalP95Milliseconds: percentiles(lexicalTimes).p95,
            semanticP95Milliseconds: percentiles(semanticTimes).p95,
            vectorBytes: size * (vectors.first?.count ?? 0) * MemoryLayout<Float>.size)
    }

    private static func semanticHits(
        _ query: [Float], vectors: [[Float]], ids: [String]
    ) throws -> [DictationSearchObservations.Hit] {
        guard query.count == vectors.first?.count else { throw DictationSearchBenchmarkError.invalidEmbedding }
        var scored: [(index: Int, similarity: Float)] = []
        scored.reserveCapacity(vectors.count)
        for (index, candidate) in vectors.enumerated() {
            var dot: Float = 0
            for position in candidate.indices { dot += candidate[position] * query[position] }
            scored.append((index, dot))
        }
        let top = scored.sorted {
            $0.similarity != $1.similarity ? $0.similarity > $1.similarity : ids[$0.index] < ids[$1.index]
        }.prefix(resultLimit)
        return top.map { .init(id: ids[$0.index], similarity: (Double($0.similarity) * 10_000).rounded() / 10_000) }
    }

    static func meanVector(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors { for index in vector.indices { sum[index] += vector[index] } }
        return sum.map { $0 / Float(vectors.count) }
    }

    /// Removes the direction every vector shares, so similarity reflects what differs.
    static func centeredVector(_ vector: [Float], mean: [Float]) -> [Float] {
        let shifted = zip(vector, mean).map { $0 - $1 }
        let norm = shifted.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? shifted.map { $0 / norm } : shifted
    }

    private static func vector(for text: String, embed: Embed) async throws -> [Float] {
        guard let vector = try await embed([text]).first, !vector.isEmpty, vector.allSatisfy(\.isFinite)
        else { throw DictationSearchBenchmarkError.invalidEmbedding }
        return vector
    }

    static func percentiles(_ values: [Double]) -> DictationSearchObservations.Percentiles {
        let sorted = values.sorted()
        func at(_ quantile: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let index = min(sorted.count - 1, max(0, Int((quantile * Double(sorted.count)).rounded(.up)) - 1))
            return (sorted[index] * 1_000).rounded() / 1_000
        }
        return .init(p50: at(0.5), p95: at(0.95))
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }

    /// One disposable store with the history on, searched as the history window searches.
    private struct Corpus {
        let store: DictationStore

        static func seed(_ dictations: [DictationSearchFixture.Dictation], now: Date) async throws -> Self {
            let store = try DictationStore.inMemory()
            _ = try await store.setDictationHistoryPolicy(
                isEnabled: true, keepsOriginal: false, retentionDays: 90, at: now)
            for dictation in dictations {
                let outcome = try await store.recordDictation(
                    DictationRecord(
                        id: DictationRecordID(rawValue: dictation.id), createdAt: dictation.createdAt,
                        duration: 2, text: dictation.text, originalText: nil, mode: .literal, language: nil,
                        engine: "benchmark", applicationName: dictation.applicationName,
                        applicationBundleID: nil, delivery: .verified),
                    admittedGeneration: 0, at: now)
                // A refused or purged row would leave the searched corpus smaller than reported.
                guard outcome == .saved else { throw DictationSearchBenchmarkError.invalidFixture }
            }
            let kept = try await store.database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM dictationRecord") }
            guard kept == dictations.count else { throw DictationSearchBenchmarkError.invalidFixture }
            return Self(store: store)
        }

        func lexical(_ question: String) async throws -> [String] {
            try await store.dictationRecords(
                matching: DictationRecordFilter(query: question), limit: DictationSearchBenchmark.resultLimit
            ).map(\.id.rawValue.uuidString)
        }
    }
}
