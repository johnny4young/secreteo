import LiveSpeech
import SwiftUI

/// Names and terms that guide recognition. Kept comma-separated, as `VocabularyPrompt` reads them.
struct DictationVocabularyEditor: View {
    @Binding var stored: String
    @State private var newTerm = ""

    private var terms: [String] {
        var seen = Set<String>()
        return VocabularyPrompt.parse(stored).filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        Section("Vocabulary") {
            ForEach(terms, id: \.self) { term in
                HStack {
                    Text(term)
                    Spacer()
                    Button {
                        stored = terms.filter { $0 != term }.joined(separator: ", ")
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.format("Remove “%@”", term))
                    .accessibilityIdentifier("settings-dictation-vocabulary-remove")
                }
            }
            HStack {
                TextField("Add Term", text: $newTerm)
                    .onSubmit(add)
                    .accessibilityIdentifier("settings-dictation-vocabulary-field")
                Button("Add", action: add)
                    .disabled(trimmedTerm.isEmpty)
                    .accessibilityIdentifier("settings-dictation-vocabulary-add")
            }
        }
    }

    private var trimmedTerm: String {
        newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        guard !trimmedTerm.isEmpty else { return }
        stored = (terms + [trimmedTerm]).joined(separator: ", ")
        newTerm = ""
    }
}
