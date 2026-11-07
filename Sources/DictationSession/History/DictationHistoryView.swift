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
        model = dictation.history
        stats = dictation.stats
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if stats.isEnabled { DictationStatsPanel(model: stats) }
                if showsFilters { filters }
                if let failure = model.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("dictation-history-error")
                }
                content
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 420)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dictations")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("dictation-history-title")
                Text(model.policy.isEnabled
                     ? L10n.format("Kept on this Mac for %d days.", model.policy.retentionDays)
                     : L10n.text("History is off. New dictations are not saved."))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("dictation-history-status")
            }
            Spacer()
            if !model.records.isEmpty {
                Button("Delete All", role: .destructive) { confirmingDeleteAll = true }
                    .accessibilityIdentifier("dictation-history-delete-all")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !model.isLoaded {
            ProgressView().controlSize(.small)
        } else if model.records.isEmpty, !model.filter.isUnfiltered {
            Text("No dictations match.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dictation-history-no-results")
        } else if model.records.isEmpty, !model.policy.isEnabled {
            Button("Turn On History") { Task { await model.update(isEnabled: true) } }
                .buttonStyle(.borderedProminent)
                .tint(SecreteoDesign.accent)
                .accessibilityIdentifier("dictation-history-enable")
        } else if model.records.isEmpty {
            Text("Your dictations will appear here.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dictation-history-empty")
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(model.records.enumerated()), id: \.element.id) { index, record in
                    DictationHistoryRow(
                        record: record, index: index,
                        onDelete: { Task { await model.delete(record.id) } })
                }
                if model.hasMore {
                    Button("Show Older Dictations") { Task { await model.loadMore() } }
                        .accessibilityIdentifier("dictation-history-more")
                }
            }
        }
    }

    private var showsFilters: Bool {
        !model.records.isEmpty || !model.applications.isEmpty || !model.filter.isUnfiltered
    }

    private var filters: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search Dictations", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("dictation-history-search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.text("Clear Search"))
                        .accessibilityIdentifier("dictation-history-search-clear")
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Picker("App", selection: filterBinding(\.applicationName)) {
                Text("All Apps").tag(String?.none)
                ForEach(model.applications, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .fixedSize()
            .accessibilityIdentifier("dictation-history-app-filter")
            Toggle("Only Not Delivered", isOn: filterBinding(\.onlyNotDelivered))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("dictation-history-undelivered-filter")
        }
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

private struct DictationHistoryRow: View {
    let record: DictationRecord
    let index: Int
    let onDelete: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.text)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .accessibilityIdentifier("dictation-history-text-\(index)")
                if let original = record.originalText {
                    DisclosureGroup("Original") {
                        Text(original).textSelection(.enabled).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .accessibilityIdentifier("dictation-history-original-\(index)")
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(record.delivery == .notDelivered ? .orange : .secondary)
                    .accessibilityIdentifier("dictation-history-details-\(index)")
            }
            Spacer(minLength: 0)
            Button {
                copied = TextInserter.copy(record.text)
            } label: {
                Label(copied ? L10n.text("Copied") : L10n.text("Copy"), systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("dictation-history-copy-\(index)")
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("dictation-history-delete-\(index)")
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var details: String {
        var parts = [record.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if let app = record.applicationName { parts.append(app) }
        let mode = switch record.mode {
        case .literal: L10n.text("Literal")
        case .clean: L10n.text("Clean")
        case .polish: L10n.text("Polish")
        }
        parts.append(mode)
        let delivery = switch record.delivery {
        case .verified: L10n.text("Inserted")
        case .dispatched: L10n.text("Sent, not verified")
        case .notDelivered: L10n.text("Not delivered")
        }
        return (parts + [delivery]).joined(separator: " · ")
    }
}
