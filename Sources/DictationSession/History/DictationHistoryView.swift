import DictationKit
import SwiftUI

/// The private dictation history, newest first. Nothing is listed until the
/// user turns history on; rows can be copied or deleted one by one or all.
public struct DictationHistoryView: View {
    private let model: DictationHistoryModel
    private let stats: DictationStatsModel
    @State private var confirmingDeleteAll = false
    @State private var query = ""

    public init(dictation: DictationFeature) {
        self.init(history: dictation.history, stats: dictation.stats)
    }

    init(history: DictationHistoryModel, stats: DictationStatsModel) {
        model = history
        self.stats = stats
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if stats.isEnabled { DictationStatsPanel(model: stats).padding(.top, 10) }
                if showsFilters { filters }
                if let failure = model.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(SecreteoDesign.notSent)
                        .padding(.top, 12)
                        .accessibilityIdentifier("dictation-history-error")
                }
                content.padding(.top, 10)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 1_100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(SecreteoDesign.text)
        .background(SecreteoDesign.windowBackground)
        .frame(minWidth: 620, minHeight: 420)
        .accessibilityIdentifier("dictation-history")
        .task {
            await model.load()
            await stats.load()
        }
        // A search set from outside, such as a Shortcut, fills the field.
        .onChange(of: model.filter.query, initial: true) { _, words in
            if query != words { query = words }
        }
        .task(id: query) {
            // Typing settles before the query runs; each keystroke cancels the last wait.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            var filter = model.filter
            if filter.query != query { filter.recordID = nil }
            filter.query = query
            await model.apply(filter)
        }
        .confirmationDialog(
            Text("Delete every saved dictation?"), isPresented: $confirmingDeleteAll, titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                query = ""
                Task { await model.deleteAll() }
            }
                .accessibilityIdentifier("dictation-history-delete-all-confirm")
        }
        .secreteoLocalized()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsFilters {
                search.frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Dictations")
                    .font(.secreteoSerif(46))
                    .accessibilityIdentifier("dictation-history-title")
                Text(model.policy.isEnabled
                     ? L10n.format("Kept on this Mac for %d days", model.policy.retentionDays)
                     : L10n.text("History is off. New dictations are not saved."))
                    .font(.system(size: 13))
                    .foregroundStyle(SecreteoDesign.tertiaryText)
                    .accessibilityIdentifier("dictation-history-status")
                Spacer(minLength: 0)
                if stats.isEnabled { DictationStatsRangePicker(model: stats) }
            }
            .padding(.horizontal, 6)
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField("Search Dictations", text: $query)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("dictation-history-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("Clear Search"))
                    .accessibilityIdentifier("dictation-history-search-clear")
            }
        }
        .font(.system(size: 13.5))
        .foregroundStyle(SecreteoDesign.tertiaryText)
        .padding(.horizontal, 10)
        .frame(width: 230, height: 30)
        .background(SecreteoDesign.field, in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private var content: some View {
        if !model.isLoaded {
            ProgressView().controlSize(.small).padding(.horizontal, 6)
        } else if model.records.isEmpty, !model.filter.isUnfiltered {
            Text("No dictations match.")
                .foregroundStyle(SecreteoDesign.secondaryText)
                .padding(.horizontal, 6)
                .accessibilityIdentifier("dictation-history-no-results")
        } else if model.records.isEmpty, !model.policy.isEnabled {
            Button("Turn On History") { Task { await model.update(isEnabled: true) } }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 6)
                .accessibilityIdentifier("dictation-history-enable")
        } else if model.records.isEmpty {
            Text("Your dictations will appear here.")
                .foregroundStyle(SecreteoDesign.secondaryText)
                .padding(.horizontal, 6)
                .accessibilityIdentifier("dictation-history-empty")
        } else {
            log
        }
    }

    private var log: some View {
        let now = Date()
        let log = DictationDayLog(
            records: model.records, meaningCount: model.meaningCount, now: now, calendar: .current)
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(log.sections.enumerated()), id: \.element.id) { index, section in
                DictationHistoryDivider(title: DictationHistoryFormat.title(of: section, now: now))
                    .accessibilityIdentifier("dictation-history-day-\(index)")
                ForEach(section.entries) { row($0, datesRow: false) }
            }
            if !log.meaning.isEmpty {
                DictationHistoryDivider(title: L10n.text("Close in meaning"))
                    .accessibilityIdentifier("dictation-history-meaning-divider")
                ForEach(log.meaning) { row($0, datesRow: true) }
            }
            if model.hasMore {
                Button("Show Older Dictations") { Task { await model.loadMore() } }
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
                    .accessibilityIdentifier("dictation-history-more")
            }
        }
    }

    private func row(_ entry: DictationDayLog.Entry, datesRow: Bool) -> some View {
        DictationHistoryRow(
            record: entry.record, index: entry.index, datesRow: datesRow,
            onDelete: { Task { await model.delete(entry.record.id) } })
    }

    private var showsFilters: Bool {
        !model.records.isEmpty || !model.applications.isEmpty || !model.filter.isUnfiltered
    }

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("App", selection: filterBinding(\.applicationName)) {
                Text("All Apps").tag(String?.none)
                ForEach(model.applications, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("dictation-history-app-filter")
            Toggle("Only Not Delivered", isOn: filterBinding(\.onlyNotDelivered))
                .toggleStyle(.button)
                .accessibilityIdentifier("dictation-history-undelivered-filter")
            Spacer(minLength: 0)
            if !model.records.isEmpty {
                Button("Delete All", role: .destructive) { confirmingDeleteAll = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SecreteoDesign.notSent)
                    .accessibilityIdentifier("dictation-history-delete-all")
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 16)
    }

    private func filterBinding<Value>(_ keyPath: WritableKeyPath<DictationRecordFilter, Value>) -> Binding<Value> {
        Binding(
            get: { model.filter[keyPath: keyPath] },
            set: { value in
                var filter = model.filter
                filter[keyPath: keyPath] = value
                filter.recordID = nil
                Task { await model.apply(filter) }
            })
    }
}
