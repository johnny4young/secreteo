import SwiftUI

public enum SettingsTab: String, CaseIterable, Sendable {
    case dictation, text, polish, history, general

    var symbol: String {
        switch self {
        case .dictation: "mic"
        case .text: "textformat"
        case .polish: "sparkles"
        case .history: "clock.arrow.circlepath"
        case .general: "gearshape"
        }
    }

    var title: Text {
        switch self {
        case .dictation: Text("Dictation")
        case .text: Text("Text")
        case .polish: Text("Polish")
        case .history: Text("History")
        case .general: Text("General")
        }
    }
}

public enum SettingsMetrics {
    public static let width: CGFloat = 560
    /// Room for the title bar above the tabs, so no tab sits under it.
    public static let barHeight: CGFloat = 84
    static let rowHeight: CGFloat = 40
    static let cardRadius: CGFloat = 11
}

/// Icon over label; the selected tab gets a copper wash.
public struct SettingsTabBar: View {
    let tabs: [SettingsTab]
    @Binding var selection: SettingsTab

    public init(tabs: [SettingsTab], selection: Binding<SettingsTab>) {
        self.tabs = tabs
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(tabs, id: \.self) { tab in
                button(tab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 5)
        .frame(height: SettingsMetrics.barHeight)
        .background(SecreteoDesign.settingsBar)
        .overlay(alignment: .bottom) { SecreteoDesign.hairline.frame(height: 1) }
    }

    private func button(_ tab: SettingsTab) -> some View {
        let selected = tab == selection
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 16))
                    .frame(height: 18)
                tab.title
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? SecreteoDesign.accent : SecreteoDesign.secondaryText)
            .frame(width: 72, height: 48)
            .background(
                selected ? SecreteoDesign.accentWash : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings-tab-" + tab.rawValue)
    }
}

/// A section title in small tracked capitals.
public struct SettingsEyebrow: View {
    let title: Text

    public init(_ title: Text) {
        self.title = title
    }

    public var body: some View {
        title
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(SecreteoDesign.tertiaryText)
            .padding(.horizontal, 5)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A grouped card: each child is a row, and a hairline separates rows.
public struct SettingsCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    row
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowHeight, alignment: .leading)
                    if row.id != rows.last?.id {
                        SecreteoDesign.hairline.frame(height: 1)
                    }
                }
            }
        }
        .background(SecreteoDesign.card, in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius).strokeBorder(SecreteoDesign.hairline))
        .toggleStyle(.switch)
        .controlSize(.small)
        .textFieldStyle(.roundedBorder)
    }
}

/// A label on the leading edge and its control on the trailing one.
public struct SettingsRow<Trailing: View>: View {
    private let title: Text
    private let trailing: Trailing

    public init(_ title: Text, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 10) {
            title
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// A switch on the trailing edge. Only the switch is an element, so the identifier names one control.
public struct SettingsSwitch<Accessory: View>: View {
    private let title: Text
    private let identifier: String
    @Binding private var isOn: Bool
    private let accessory: Accessory

    public init(
        _ title: Text, identifier: String, isOn: Binding<Bool>, @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.identifier = identifier
        _isOn = isOn
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: 10) {
            title
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            accessory
            Toggle(isOn: $isOn) { title }
                .labelsHidden()
                .accessibilityIdentifier(identifier)
        }
    }
}

extension SettingsSwitch where Accessory == EmptyView {
    public init(_ title: Text, identifier: String, isOn: Binding<Bool>) {
        self.init(title, identifier: identifier, isOn: isOn) { EmptyView() }
    }
}

/// A few choices side by side. Each segment is `identifier-suffix` and reads 1 when chosen.
struct SettingsSegments<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: Text
        let suffix: String
    }

    let identifier: String
    let label: Text
    @Binding var selection: Value
    let options: [Option]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    option.title
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? SecreteoDesign.segmentText : SecreteoDesign.secondaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(selected ? SecreteoDesign.segment : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityValue(Text(verbatim: selected ? "1" : "0"))
                .accessibilityIdentifier(identifier + "-" + option.suffix)
            }
        }
        .padding(2)
        .background(SecreteoDesign.control, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// A shortcut drawn as its keys. Decoration: the control beside it carries the words.
struct SettingsKeyCaps: View {
    let keys: [String]
    var highlighted: Int?
    var small = false

    /// Modifier symbols are one key each; what is left is the key itself.
    init(shortcut label: String) {
        let modifiers = label.prefix { "⌃⌥⇧⌘".contains($0) }
        let key = String(label.dropFirst(modifiers.count))
        keys = modifiers.map(String.init) + (key.isEmpty ? [] : [key])
    }

    init(keys: [String], highlighted: Int?) {
        self.keys = keys
        self.highlighted = highlighted
        small = true
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                let lit = index == highlighted
                let shape = RoundedRectangle(cornerRadius: 5)
                Text(verbatim: key)
                    .font(.system(size: small ? 9.5 : 11, weight: .medium))
                    .foregroundStyle(lit ? SecreteoDesign.onAmber : small ? SecreteoDesign.tertiaryText : .primary)
                    .padding(.horizontal, 4)
                    .frame(minWidth: key == " " ? 44 : small ? 19 : 21, minHeight: small ? 19 : 21)
                    .background(lit ? SecreteoDesign.amber : SecreteoDesign.keyCap, in: shape)
                    .overlay(shape.strokeBorder(SecreteoDesign.keyEdge))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lays children out in a line and wraps to the next when they do not fit.
struct SettingsFlow: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, point) in zip(subviews, place(subviews, width: bounds.width).points) {
            subview.place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func place(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + lineHeight))
    }
}

/// A text action in the accent colour, for a fix or an edit inside a row.
struct SettingsLinkStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(SecreteoDesign.accent)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// The label leads and the control trails, as a grouped form lays them out.
struct SettingsLabeledStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
                .fixedSize()
        }
    }
}
