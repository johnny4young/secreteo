import DictationKit
import DictationStore
import Foundation
import OSLog
import SpeechCore

extension DictationFeature {
    /// Secreteo's own database, or a scratch one for a disposable launch. A database it
    /// cannot open leaves history unavailable and dictation working.
    static func openDictationStore(
        usesTemporaryStore: Bool, bundleIdentifier: String
    ) -> any DictationHistoryStore & DictationStatsStore & DictationEmbeddingStore {
        let url = usesTemporaryStore
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(DictationStore.fileName)
            : DictationStore.defaultURL(bundleIdentifier: bundleIdentifier)
        do {
            return try DictationStore(databaseURL: url)
        } catch {
            // Redacted like every logged value: a database error can quote what it was writing.
            Logger(subsystem: "com.johnny4young.secreteo", category: "dictation-history")
                .error("History store unavailable: \(String(describing: error))")
            return UnavailableDictationStore(error: error)
        }
    }

    /// Disposable launches can start with history on, optionally with two saved rows.
    func loadDictationHistory() async {
        await history.load()
        guard usesTemporaryMeetingStore, launchArguments.contains("-seed-dictation-history") else { return }
        let seedsRecords = launchArguments.contains("-seed-dictation-history-records")
        await history.update(isEnabled: true, keepsOriginal: seedsRecords)
        guard seedsRecords, let write = history.admit() else { return }
        let now = Date()
        for (offset, sample) in [
            ("Send the report on Friday.", nil, "Slack", DictationRecordDelivery.notDelivered),
            ("No borres estas notas.", "eh no borres estas notas", "Notes", .verified)
        ].enumerated() {
            _ = await write(DictationRecord(
                id: DictationRecordID(), createdAt: now.addingTimeInterval(Double(offset - 2) * 60), duration: 3,
                text: sample.0, originalText: sample.1, mode: sample.1 == nil ? .literal : .clean, language: nil,
                engine: "parakeet", applicationName: sample.2, applicationBundleID: nil, delivery: sample.3))
        }
    }
}

extension DictationFeature {
    /// Disposable launches can start with statistics on and a week of sample days.
    func loadDictationStats() async {
        if usesTemporaryMeetingStore, launchArguments.contains("-seed-dictation-stats") {
            try? await dictationStore.setDictationStatsEnabled(true)
            let calendar = Calendar.current
            let samples = [(0, "Slack", 42), (0, "Mail", 120), (1, "Slack", 18), (3, "Notes", 64)]
            for (offset, sample) in samples.enumerated() {
                let date = calendar.date(byAdding: .day, value: -sample.0, to: Date()) ?? Date()
                _ = try? await dictationStore.recordDictationStats(DictationStatsSample(
                    id: DictationRecordID(), day: DictationStatsCalendar.day(of: date, calendar: calendar),
                    words: sample.2, spokenDuration: Double(sample.2) / 2.5, applicationName: sample.1,
                    delivered: offset != 3), at: Date(), calendar: calendar)
            }
        }
        await stats.load()
    }
}

/// Stands in when the database cannot be opened, such as one a newer Secreteo wrote.
struct UnavailableDictationStore: DictationHistoryStore, DictationStatsStore, DictationEmbeddingStore {
    let error: any Error

    func dictationHistoryPolicy() async throws -> DictationHistoryPolicy { throw error }
    func setDictationHistoryPolicy(
        isEnabled: Bool, keepsOriginal: Bool, retentionDays: Int, exposesToAgents: Bool, at now: Date
    ) async throws -> DictationHistoryPolicy { throw error }
    func recordDictation(
        _ record: DictationRecord, admittedGeneration: Int, at now: Date
    ) async throws -> DictationRecordOutcome { throw error }
    func dictationRecords(
        matching filter: DictationRecordFilter, before cursor: DictationRecord?, limit: Int
    ) async throws -> [DictationRecord] { throw error }
    func dictationApplications() async throws -> [String] { throw error }
    func deleteDictationRecord(_ id: DictationRecordID) async throws -> Bool { throw error }
    func deleteAllDictationRecords() async throws -> Int { throw error }
    func purgeExpiredDictationRecords(at now: Date) async throws -> Int { throw error }
    func dictationStatsEnabled() async throws -> Bool { throw error }
    func setDictationStatsEnabled(_ isEnabled: Bool) async throws { throw error }
    func recordDictationStats(_ sample: DictationStatsSample, at now: Date, calendar: Calendar) async throws -> Bool {
        throw error
    }
    func dictationStatsSummary(days: [String]) async throws -> DictationStatsSummary { throw error }
    func deleteDictationStats() async throws { throw error }
    func dictationRecordsForAgents(
        matching filter: DictationRecordFilter, offset: Int, limit: Int
    ) async throws -> DictationAgentRead<DictationRecordPage> { throw error }
    func saveDictationEmbedding(_ embedding: DictationEmbedding, profile: String) async throws -> Bool { throw error }
    func dictationEmbeddings(
        profile: String, matching filter: DictationRecordFilter
    ) async throws -> [DictationEmbedding] { throw error }
    func dictationEmbeddingIDs(
        profile: String, matching filter: DictationRecordFilter
    ) async throws -> Set<DictationRecordID> { throw error }
    func dictationRecordsMissingEmbedding(
        profile: String, before cursor: DictationRecord?, limit: Int
    ) async throws -> [DictationRecord] { throw error }
    func dictationRecords(ids: [DictationRecordID]) async throws -> [DictationRecord] { throw error }
}
