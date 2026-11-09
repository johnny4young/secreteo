import DictationKit
import Foundation
import SpeechCore
import Observation

/// The history consent and the loaded pages. Dictation reads the consent
/// generation from here when a session starts; the store revalidates it.
@MainActor
@Observable
final class DictationHistoryModel {
    private(set) var policy = DictationHistoryPolicy.off
    private(set) var isLoaded = false
    private(set) var records: [DictationRecord] = []
    private(set) var hasMore = false
    private(set) var failure: String?
    private(set) var filter = DictationRecordFilter.all
    /// Applications with saved dictations, for the filter menu.
    private(set) var applications: [String] = []
    @ObservationIgnored let store: any DictationHistoryStore
    /// Nil when this Mac cannot rank by meaning; searches then match words only.
    @ObservationIgnored let semantic: DictationSemanticIndex?
    /// Drops a page that arrives after a newer filter was applied.
    @ObservationIgnored private var pageRequest = 0
    /// How many rows at the end match by meaning only, after every word match.
    @ObservationIgnored private var meaningCount = 0
    @ObservationIgnored private var watchesVectors = false

    init(store: any DictationHistoryStore, semantic: DictationSemanticIndex? = nil) {
        self.store = store
        self.semantic = semantic
    }

    /// Reads the consent, drops expired rows and loads the newest page.
    func load() async {
        do {
            _ = try await PurgeExpiredDictations(store: store).execute(())
            policy = try await LoadDictationHistoryPolicy(store: store).execute(())
            applications = try await ListDictationApplications(store: store).execute(())
            if let application = filter.applicationName, !applications.contains(application) {
                filter.applicationName = nil
            }
            await watchVectors()
            await semantic?.invalidate()
            try await reloadPage()
            isLoaded = true
            failure = nil
        } catch {
            failure = L10n.text("Dictation history could not be loaded.")
        }
        // Vectors for dictations saved before this model; searches match words until each is ready.
        if let semantic { Task.detached(priority: .utility) { await semantic.backfill() } }
    }

    /// Shows the newest page that matches; every filter applies before the page limit.
    func apply(_ filter: DictationRecordFilter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        do {
            try await reloadPage()
            failure = nil
        } catch {
            failure = L10n.text("Dictation history could not be loaded.")
        }
    }

    /// Searches for these words, as when a Shortcut opens Dictations; other filters
    /// are cleared. Loaded rows reload now, and a history not loaded yet searches when it loads.
    func show(search words: String) {
        let filter = DictationRecordFilter(query: words)
        guard isLoaded else {
            self.filter = filter
            return
        }
        Task { await apply(filter) }
    }

    func loadMore() async {
        guard hasMore, let last = records.last else { return }
        let request = pageRequest
        do {
            let page = try await ListDictations(store: store).execute(.init(filter: filter, after: last))
            guard request == pageRequest else { return }
            records += page
            hasMore = page.count == ListDictations.pageSize
            if !hasMore { await appendMeaning(request) }
        } catch {
            failure = L10n.text("Dictation history could not be loaded.")
        }
    }

    private func reloadPage() async throws {
        pageRequest += 1
        let request = pageRequest
        let page = try await ListDictations(store: store).execute(.init(filter: filter))
        guard request == pageRequest else { return }
        records = page
        meaningCount = 0
        hasMore = page.count == ListDictations.pageSize
        if !hasMore { await appendMeaning(request) }
    }

    /// Once every word match is listed, adds the dictations close in meaning that hold
    /// none of the words. A failure or a Mac without the model leaves the word matches alone.
    private func appendMeaning(_ request: Int) async {
        guard let semantic, !hasMore,
              let ranking = try? await semantic.ranking(for: filter.query, matching: filter),
              request == pageRequest
        else { return }
        let words = records.dropLast(meaningCount)
        let extra = DictationHybridSearch.meaningOnly(ranking, after: words.map(\.id))
        let found = extra.isEmpty ? [] : (try? await semantic.records(extra)) ?? []
        guard request == pageRequest, !hasMore else { return }
        records = Array(records.dropLast(meaningCount)) + found
        meaningCount = found.count
    }

    /// Vectors saved after a search was shown may find more; only the meaning rows change.
    private func refreshMeaning() async {
        guard isLoaded, DictationHybridSearch.isSearchable(filter.query) else { return }
        await appendMeaning(pageRequest)
    }

    private func watchVectors() async {
        guard let semantic, !watchesVectors else { return }
        watchesVectors = true
        await semantic.setChangeHandler { [weak self] in await self?.refreshMeaning() }
    }

    func update(
        isEnabled: Bool? = nil, keepsOriginal: Bool? = nil, retentionDays: Int? = nil, exposesToAgents: Bool? = nil
    ) async {
        let request = UpdateDictationHistoryPolicy.Request(
            isEnabled: isEnabled ?? policy.isEnabled,
            keepsOriginal: keepsOriginal ?? policy.keepsOriginal,
            retentionDays: retentionDays ?? policy.retentionDays,
            exposesToAgents: exposesToAgents ?? policy.exposesToAgents)
        do {
            policy = try await UpdateDictationHistoryPolicy(store: store).execute(request)
            failure = nil
            if retentionDays != nil { await load() }
        } catch {
            failure = L10n.text("The history setting could not be saved.")
        }
    }

    func delete(_ id: DictationRecordID) async {
        do {
            if try await DeleteDictation(store: store).execute(id) {
                if let index = records.firstIndex(where: { $0.id == id }) {
                    if index >= records.count - meaningCount { meaningCount -= 1 }
                    records.remove(at: index)
                }
                await semantic?.invalidate()
            }
            failure = nil
        } catch {
            failure = L10n.text("The dictation could not be deleted.")
        }
    }

    func deleteAll() async {
        do {
            _ = try await DeleteAllDictations(store: store).execute(())
            await semantic?.invalidate()
            records = []
            meaningCount = 0
            hasMore = false
            applications = []
            filter = .all
            policy = try await LoadDictationHistoryPolicy(store: store).execute(())
            failure = nil
        } catch {
            failure = L10n.text("The dictations could not be deleted.")
        }
    }

    /// Nil unless history is on now; the writer keeps this generation.
    func admit() -> DictationHistoryWriter? {
        guard isLoaded, policy.isEnabled else { return nil }
        let generation = policy.generation
        return { [weak self] record in
            guard let self else { return false }
            return await self.save(record, generation: generation)
        }
    }

    private func save(_ record: DictationRecord, generation: Int) async -> Bool {
        do {
            let outcome = try await RecordDictation(store: store).execute(
                .init(record: record, admittedGeneration: generation))
            if outcome == .saved {
                show(record)
                // The store refuses the vector if the dictation is deleted first, so a late one keeps nothing.
                if let semantic { Task.detached(priority: .utility) { await semantic.index(record) } }
            }
            return true
        } catch {
            return false
        }
    }

    private func show(_ record: DictationRecord) {
        if let application = record.applicationName, !applications.contains(application) {
            applications = (applications + [application]).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else if filter.isUnfiltered {
            records.insert(record, at: 0)
        }
    }
}
