import DictationKit
import DictationStore
import Foundation
import OSLog
import SpeechCore

extension DictationFeature {
    /// Secreteo's own database, or a scratch one for a disposable launch. A database it
    /// cannot open leaves history unavailable and dictation working.
    static func openHistoryStore(usesTemporaryStore: Bool, bundleIdentifier: String) -> any DictationHistoryStore {
        let url = usesTemporaryStore
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(DictationStore.fileName)
            : DictationStore.defaultURL(bundleIdentifier: bundleIdentifier)
        do {
            return try DictationStore(databaseURL: url)
        } catch {
            // The error names the cause, never any dictated text.
            Logger(subsystem: "com.johnny4young.secreteo", category: "dictation-history")
                .error("History store unavailable: \(String(describing: error), privacy: .public)")
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

/// Stands in when the database cannot be opened, such as one a newer Secreteo wrote.
struct UnavailableDictationStore: DictationHistoryStore {
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
    func dictationRecordsForAgents(
        matching filter: DictationRecordFilter, offset: Int, limit: Int
    ) async throws -> DictationAgentRead<DictationRecordPage> { throw error }
}
