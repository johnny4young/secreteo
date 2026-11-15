import DictationKit
import SwiftUI

/// A day's heading, or the line before the rows found by meaning.
struct DictationHistoryDivider: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased(with: AppLanguage.current.locale))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(SecreteoDesign.tertiaryText)
            Rectangle().fill(SecreteoDesign.text.opacity(0.1)).frame(height: 1).accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

enum DictationHistoryFormat {
    static func title(of section: DictationDayLog.Section, now: Date, calendar: Calendar = .current) -> String {
        let date = date(section.start, now: now, calendar: calendar)
        let title = switch section.day {
        case .today: L10n.text("Today") + " · " + date
        case .yesterday: L10n.text("Yesterday")
        case .earlier: date
        }
        return title.uppercased(with: AppLanguage.current.locale)
    }

    /// The weekday, day and month, with the year once it is not this one.
    static func date(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let locale = AppLanguage.current.locale
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
        return date.formatted(style)
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: AppLanguage.current.locale).hour().minute())
    }

    static func words(_ count: Int) -> String {
        count == 1 ? L10n.text("1 word") : L10n.format("%d words", count)
    }
}

struct DictationHistoryRow: View {
    let record: DictationRecord
    let index: Int
    /// Rows found by meaning are ranked, so each says its own day.
    let datesRow: Bool
    let onDelete: () -> Void
    @State private var copied = false
    @State private var showsOriginal = false

    private var isNotDelivered: Bool { record.delivery == .notDelivered }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(DictationHistoryFormat.time(record.createdAt))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(SecreteoDesign.tertiaryText)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 72, alignment: .trailing)
                .padding(.top, 3)
            SecreteoGlyph(face, ink: SecreteoDesign.accent)
                .frame(width: 18, height: 18)
                .padding(.top, 3)
                .accessibilityElement()
                .accessibilityLabel(face.accessibilityName)
                .accessibilityIdentifier("dictation-history-state-\(index)")
            VStack(alignment: .leading, spacing: 6) {
                Text(record.text)
                    .font(.system(size: 16.5))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .accessibilityIdentifier("dictation-history-text-\(index)")
                if showsOriginal, let original = record.originalText {
                    Text(original)
                        .font(.secreteoSerif(18.5, italic: true))
                        .foregroundStyle(SecreteoDesign.tertiaryText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("dictation-history-heard-\(index)")
                }
                HStack(spacing: 8) {
                    Text(details).accessibilityIdentifier("dictation-history-details-\(index)")
                    if record.originalText != nil { originalToggle }
                }
                .font(.system(size: 12))
                .foregroundStyle(SecreteoDesign.tertiaryText)
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            if isNotDelivered {
                RoundedRectangle(cornerRadius: 14)
                    .fill(SecreteoDesign.card)
                    .strokeBorder(SecreteoDesign.notSent.opacity(0.45), lineWidth: 1.5)
            }
        }
        .padding(.top, isNotDelivered ? 4 : 0)
    }

    private var originalToggle: some View {
        Button { showsOriginal.toggle() } label: {
            HStack(spacing: 4) {
                Text(verbatim: "·").accessibilityHidden(true)
                Text("Original")
                Image(systemName: showsOriginal ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsOriginal ? L10n.text("Expanded") : L10n.text("Collapsed"))
        .accessibilityIdentifier("dictation-history-original-\(index)")
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button { copied = TextInserter.copy(record.text) } label: {
                Label(copied ? L10n.text("Copied") : L10n.text("Copy"), systemImage: "doc.on.doc")
                    .labelStyle(DictationHistoryCopyStyle(showsTitle: isNotDelivered))
            }
            .help(L10n.text("Copy"))
            .accessibilityLabel(copied ? L10n.text("Copied") : L10n.text("Copy"))
            .accessibilityIdentifier("dictation-history-copy-\(index)")
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash").labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .help(L10n.text("Delete"))
            .accessibilityIdentifier("dictation-history-delete-\(index)")
        }
        .buttonStyle(.plain)
        .foregroundStyle(SecreteoDesign.secondaryText)
    }

    private var face: SecreteoGlyphFace {
        switch record.delivery {
        case .notDelivered: .notSent
        case .dispatched: .sent
        case .verified: record.mode == .polish ? .polishing : .inserted
        }
    }

    private var details: AttributedString {
        var parts: [AttributedString] = []
        if datesRow {
            parts.append(AttributedString(DictationHistoryFormat.date(record.createdAt, now: Date())))
        }
        if let app = record.applicationName {
            var name = AttributedString(app)
            name.font = .system(size: 12, weight: .semibold)
            name.foregroundColor = SecreteoDesign.secondaryText
            parts.append(name)
        }
        if record.delivery != .verified {
            var delivery = AttributedString(
                isNotDelivered ? L10n.text("Not delivered") : L10n.text("Sent, not verified"))
            delivery.font = .system(size: 12, weight: .semibold)
            delivery.foregroundColor = isNotDelivered ? SecreteoDesign.notSent : SecreteoDesign.secondaryText
            parts.append(delivery)
        }
        let mode = switch record.mode {
        case .literal: L10n.text("Literal")
        case .clean: L10n.text("Clean")
        case .polish: L10n.text("Polish")
        }
        parts.append(AttributedString(mode))
        parts.append(AttributedString(
            DictationHistoryFormat.words(DictationStatsCalendar.wordCount(record.text))))
        let seconds = Int(record.duration.rounded())
        if seconds > 0 { parts.append(AttributedString("\(seconds) s")) }
        return parts.dropFirst().reduce(parts[0]) { $0 + AttributedString(" · ") + $1 }
    }
}

/// An icon on a quiet row; the board's labelled copper pill on a row that was not delivered.
private struct DictationHistoryCopyStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            configuration.title
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(SecreteoDesign.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(SecreteoDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 28)
                .contentShape(Rectangle())
        } else {
            configuration.icon.frame(width: 28, height: 28).contentShape(Rectangle())
        }
    }
}
