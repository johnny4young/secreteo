import DictationKit
import SwiftUI

/// The 7 or 30 days the statistics card covers, beside the page title.
struct DictationStatsRangePicker: View {
    let model: DictationStatsModel

    var body: some View {
        Picker("Period", selection: Binding(
            get: { model.range },
            set: { value in Task { await model.show(range: value) } })) {
            Text("7 days").tag(7)
            Text("30 days").tag(30)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("dictation-stats-range")
    }
}

/// The top of the Dictations page while statistics are on: the words of the
/// range, four figures, where they went by app and the words of each day.
struct DictationStatsPanel: View {
    let model: DictationStatsModel

    var body: some View {
        let totals = model.summary.totals
        Group {
            if totals.dictations == 0 {
                Text("No dictations counted in this period yet.")
                    .foregroundStyle(SecreteoDesign.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("dictation-stats-empty")
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 26) {
                        figures(totals).frame(maxWidth: .infinity, alignment: .leading)
                        DictationStatsDays(days: model.summary.days).frame(width: 300, height: 190)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        figures(totals)
                        DictationStatsDays(days: model.summary.days).frame(height: 150)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(SecreteoDesign.card)
                .strokeBorder(SecreteoDesign.text.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dictation-stats")
    }

    private func figures(_ totals: DictationStatsTotals) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(totals.words.formatted(.number.locale(AppLanguage.current.locale)))
                    .font(.secreteoSerif(84))
                    .monospacedDigit()
                Text(DictationHistoryFormat.wordsNoun(totals.words))
                    .font(.secreteoSerif(34, italic: true))
                    .foregroundStyle(SecreteoDesign.accent)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dictation-stats-words")
            HStack(alignment: .top, spacing: 34) {
                figure(L10n.text("Dictations"), "\(totals.dictations)", identifier: "dictation-stats-dictations")
                figure(L10n.text("Speaking"), duration(totals.spokenDuration), identifier: "dictation-stats-speaking")
                figure(
                    L10n.text("Time saved"), "~" + duration(totals.estimatedTimeSaved),
                    identifier: "dictation-stats-saved")
                if totals.notDelivered > 0 {
                    figure(L10n.text("Not delivered"), "\(totals.notDelivered)", identifier: "dictation-stats-not-delivered")
                        .foregroundStyle(SecreteoDesign.notSent)
                }
            }
            DictationStatsShares(shares: model.summary.applicationShares()).padding(.top, 14)
        }
    }

    private func figure(_ title: String, _ value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.secreteoSerif(25)).monospacedDigit()
            Text(title).font(.system(size: 12)).foregroundStyle(SecreteoDesign.tertiaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func duration(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        let text = L10n.format("%d min", minutes % 60)
        return minutes < 60 ? text : "\(minutes / 60) h " + text
    }
}

/// Each app's share of the range's dictations as one stacked bar and its legend.
private struct DictationStatsShares: View {
    let shares: [DictationApplicationShare]

    var body: some View {
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    let width = max(0, proxy.size.width - 2 * CGFloat(shares.count - 1))
                    HStack(spacing: 2) {
                        ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                            Rectangle().fill(color(index, share)).frame(width: width * CGFloat(share.percent) / 100)
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .accessibilityHidden(true)
                HStack(spacing: 14) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(color(index, share)).frame(width: 8, height: 8)
                            Text(share.name ?? L10n.text("Other")).foregroundStyle(SecreteoDesign.secondaryText)
                            Text((Double(share.percent) / 100).formatted(.percent.locale(AppLanguage.current.locale)))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("dictation-stats-app-\(index)")
                    }
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dictation-stats-app-share")
        }
    }

    private func color(_ index: Int, _ share: DictationApplicationShare) -> Color {
        let ramp = SecreteoPalette.shareRamp
        return ramp[share.name == nil ? ramp.count - 1 : min(index, ramp.count - 1)].color
    }
}

/// Words per day, oldest first; the last bar is today, in amber with its value.
private struct DictationStatsDays: View {
    let days: [DictationStatsDay]

    var body: some View {
        let peak = max(days.map(\.totals.words).max() ?? 0, 1)
        let dense = days.count > 10
        GeometryReader { proxy in
            let height = max(0, proxy.size.height - 40)
            HStack(alignment: .bottom, spacing: dense ? 3 : 10) {
                ForEach(Array(days.enumerated()), id: \.element.day) { index, day in
                    let isToday = index == days.count - 1
                    let words = day.totals.words
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        caption(isToday && words > 0 ? words.formatted(.number.locale(AppLanguage.current.locale)) : "")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        RoundedRectangle(cornerRadius: dense ? 3 : 10)
                            .fill(fill(words: words, isToday: isToday))
                            .frame(height: max(4, height * CGFloat(words) / CGFloat(peak)))
                        caption(label(day.day, back: days.count - 1 - index, dense: dense))
                            .fontWeight(isToday ? .semibold : .medium)
                            .foregroundStyle(isToday ? SecreteoDesign.text : SecreteoDesign.tertiaryText)
                    }
                    .frame(maxWidth: 34)
                    .help(L10n.format("%@: %d words", day.day, words))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dayName(day.day))
                    .accessibilityValue(DictationHistoryFormat.words(words))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dictation-stats-days")
    }

    /// Fixed height and no width, so a wide caption never moves a thin bar.
    private func caption(_ text: String) -> some View {
        Color.clear.frame(height: 11).overlay { Text(text).font(.system(size: 10.5)).fixedSize() }
    }

    private func fill(words: Int, isToday: Bool) -> Color {
        if words == 0 { return SecreteoPalette.emptyBar.color }
        return isToday ? SecreteoPalette.todayBar.color : SecreteoPalette.dayBar.color
    }

    /// A week names each weekday; a month numbers every seventh day back from today.
    private func label(_ day: String, back: Int, dense: Bool) -> String {
        guard !dense || back.isMultiple(of: 7), let date = date(day) else { return "" }
        let style = Date.FormatStyle(locale: AppLanguage.current.locale)
        return date.formatted(dense ? style.day() : style.weekday(.narrow))
    }

    private func dayName(_ day: String) -> String {
        guard let date = date(day) else { return day }
        return date.formatted(Date.FormatStyle(locale: AppLanguage.current.locale).weekday(.wide).day().month(.wide))
    }

    private func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
