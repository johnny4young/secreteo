import SwiftUI

/// Lists what an import would change before anything is written.
struct PortavozImportSheet: View {
    let changes: [PortavozPreferenceImport.Change]
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from Portavoz")
                .font(.headline)
            ForEach(changes) { change in
                Text(change.name)
                    .accessibilityIdentifier("settings-portavoz-import-item")
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("settings-portavoz-import-cancel")
                Button("Import") {
                    onImport()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("settings-portavoz-import-confirm")
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
