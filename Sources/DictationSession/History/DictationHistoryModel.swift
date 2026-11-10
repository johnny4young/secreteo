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
    /// Invalidates reads after history writes, vector updates or visible page changes.
    @ObservationIgnored private var mutationRevision = 0
    /// The filter that produced the rows currently on screen.
    @ObservationIgnored private var loadedFilter: DictationRecordFilter?
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
        } catch {
            failure = L10n.text("Dictation history could not be loaded.")
        }
        // Vectors for dictations saved before this model; searches match words until each is ready.
        if let semantic { Task.detached(priority: .utility) { await semantic.backfill() } }
    }

    /// Shows the newest page that matches; every filter applies before the page limit.
    func apply(_ filter: DictationRecordFilter) async {
        guard filter != self.filter || (isLoaded && loadedFilter != filter) else { return }
        self.filter = filter
        pageRequest += 1
        let request = pageRequest
        do {
            try await reloadPage(request: request)
        } catch is CancellationError where Task.isCancelled {
            return
        } catch {
            guard request == pageRequest else { return }
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
        let request = pageRequest
        do {
            while !Task.isCancelled, request == pageRequest, loadedFilter == filter, hasMore, let last = records.last {
                let revision = mutationRevision
                let page = try await ListDictations(store: store).execute(.init(filter: filter, after: last))
                guard request == pageRequest else { return }
                if revision != mutationRevision { continue }
                mutationRevision += 1
                records += page
                hasMore = page.count == ListDictations.pageSize
                if !hasMore { await appendMeaning(request) }
                return
            }
        } catch {
            failure = L10n.text("Dictation history could not be loaded.")
        }
    }

    private func reloadPage(request suppliedRequest: Int? = nil) async throws {
        if suppliedRequest == nil { pageRequest += 1 }
        let request = suppliedRequest ?? pageRequest
        guard request == pageRequest else { return }
        let requestedFilter = filter
        while !Task.isCancelled {
            let revision = mutationRevision
            let page = try await ListDictations(store: store).execute(.init(filter: requestedFilter))
            guard request == pageRequest else { return }
            if revision != mutationRevision { continue }
            mutationRevision += 1
            records = page
            loadedFilter = requestedFilter
            meaningCount = 0
            hasMore = page.count == ListDictations.pageSize
            if !hasMore { await appendMeaning(request) }
            guard request == pageRequest, !Task.isCancelled else { return }
            failure = nil
            return
        }
    }

    /// Once every word match is listed, adds the dictations close in meaning that hold
    /// none of the words. A failure or a Mac without the model leaves the word matches alone.
    private func appendMeaning(_ request: Int) async {
        guard let semantic else { return }
        while !Task.isCancelled, request == pageRequest, !hasMore, loadedFilter == filter {
            let revision = mutationRevision
            guard let ranking = try? await semantic.ranking(for: filter.query, matching: filter) else { return }
            guard request == pageRequest else { return }
            if revision != mutationRevision { continue }
            let words = records.dropLast(meaningCount)
            let extra = DictationHybridSearch.meaningOnly(ranking, after: words.map(\.id))
            let found = extra.isEmpty ? [] : (try? await semantic.records(extra)) ?? []
            guard request == pageRequest, !hasMore else { return }
            if revision != mutationRevision { continue }
            mutationRevision += 1
            records = Array(records.dropLast(meaningCount)) + found
            meaningCount = found.count
            return
        }
    }

    /// Vectors saved after a search was shown may find more; only the meaning rows change.
    private func refreshMeaning() async {
        mutationRevision += 1
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
                mutationRevision += 1
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
            pageRequest += 1
            mutationRevision += 1
            records = []
            meaningCount = 0
            hasMore = false
            applications = []
            filter = .all
            loadedFilter = .all
            await semantic?.invalidate()
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
                mutationRevision += 1
                await show(record)
                // The store refuses the vector if the dictation is deleted first, so a late one keeps nothing.
                if let semantic { Task.detached(priority: .utility) { await semantic.index(record) } }
            }
            return true
        } catch {
            return false
        }
    }

    private func show(_ record: DictationRecord) async {
        while !Task.isCancelled {
            let revision = mutationRevision
            let savedRows = try? await store.dictationRecords(
                matching: .init(recordID: record.id), before: nil, limit: 1)
            if revision != mutationRevision { continue }
            guard let saved = savedRows?.first else { return }
            if let application = saved.applicationName, !applications.contains(application) {
                applications = (applications + [application]).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
            }
            guard loadedFilter == filter else { return }
            guard filter.recordID == nil || filter.recordID == saved.id else { return }
            let request = pageRequest
            var matching = filter
            matching.recordID = saved.id
            let matches = try? await store.dictationRecords(matching: matching, before: nil, limit: 1)
            if revision != mutationRevision || request != pageRequest { continue }
            guard loadedFilter == filter else { return }
            guard let matches else { return }
            guard let found = matches.first else {
                if await reconcileNonWordMatch(saved, matching: matching, revision: revision, request: request) {
                    continue
                }
                return
            }
            insertWordMatch(found)
            return
        }
    }

    /// Returns true when a concurrent change requires the caller to read again.
    private func reconcileNonWordMatch(
        _ saved: DictationRecord, matching: DictationRecordFilter, revision: Int, request: Int
    ) async -> Bool {
        guard let index = records.firstIndex(where: { $0.id == saved.id }) else { return false }
        if index >= records.count - meaningCount {
            var wordless = matching
            wordless.query = ""
            let allowed = try? await store.dictationRecords(matching: wordless, before: nil, limit: 1)
            if revision != mutationRevision || request != pageRequest { return true }
            guard loadedFilter == filter, let allowed else { return false }
            if let retained = allowed.first {
                if let current = records.firstIndex(where: { $0.id == saved.id }),
                   current >= records.count - meaningCount {
                    mutationRevision += 1
                    records[current] = retained
                }
                return false
            }
        }
        guard let current = records.firstIndex(where: { $0.id == saved.id }) else { return false }
        mutationRevision += 1
        if current >= records.count - meaningCount { meaningCount -= 1 }
        records.remove(at: current)
        return false
    }

    private func insertWordMatch(_ record: DictationRecord) {
        let wordCount = records.count - meaningCount
        if let existing = records.firstIndex(where: { $0.id == record.id }) {
            if existing < wordCount {
                mutationRevision += 1
                records[existing] = record
                return
            }
            records.remove(at: existing)
            meaningCount -= 1
        }
        let insertion = records.prefix(wordCount).firstIndex {
            $0.createdAt < record.createdAt ||
                ($0.createdAt == record.createdAt && $0.id.rawValue.uuidString < record.id.rawValue.uuidString)
        } ?? wordCount
        guard !hasMore || insertion < wordCount else { return }
        mutationRevision += 1
        records.insert(record, at: insertion)
        if hasMore { records.remove(at: wordCount) }
    }
}
