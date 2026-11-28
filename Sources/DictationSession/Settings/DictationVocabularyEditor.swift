import DictationKit
import SwiftUI

/// Names and terms that guide recognition and post-ASR vocabulary normalization.
struct DictationVocabularyEditor: View {
    @Binding var stored: String
    @State private var newTerm = ""

    private var terms: [String] {
        var seen = Set<String>()
        return DictationVocabularyNormalizer.parse(stored).filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        Group {
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
        let updated = Self.merging(newTerm, into: stored)
        if updated != stored { stored = updated }
        newTerm = ""
    }

    /// Parses comma/newline-separated terms, updating casing of existing entries in place.
    static func merging(_ input: String, into stored: String) -> String {
        var result: [String] = []
        var indexByFolded: [String: Int] = [:]
        for term in DictationVocabularyNormalizer.parse(stored) {
            let key = term.lowercased()
            if indexByFolded[key] == nil {
                indexByFolded[key] = result.count
                result.append(term)
            }
        }
        for candidate in DictationVocabularyNormalizer.parse(input) {
            let key = candidate.lowercased()
            if let existingIndex = indexByFolded[key] {
                result[existingIndex] = candidate
            } else {
                indexByFolded[key] = result.count
                result.append(candidate)
            }
        }
        return result.joined(separator: ", ")
    }
}
