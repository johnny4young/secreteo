import SwiftUI

/// The status item's content. UI tests mount this same view in a window, because the
/// status item itself cannot be automated reliably.
public struct MenuContentView: View {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MenuRow(title: "Settings…", identifier: "menu-settings", action: model.openSettings)
            Divider()
            MenuRow(title: "Quit Secreteo", identifier: "menu-quit", action: model.quit)
        }
        .padding(8)
        .frame(width: 220)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-content")
    }
}

private struct MenuRow: View {
    let title: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Inside the label: a plain button only responds where its label has a shape.
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
