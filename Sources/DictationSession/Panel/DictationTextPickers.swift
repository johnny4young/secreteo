import DictationKit
import SwiftUI

struct DictationTextModePicker: View {
    let identifier: String
    let label: Text
    @Binding var selection: DictationTextChoice
    var recipes: [DictationRecipe] = []

    var body: some View {
        LabeledContent {
            // A Picker propagates the selected Text's identifier to its native
            // popup. Explicit menu actions keep the trigger's identity stable.
            Menu {
                Button("Literal") { selection = .init(mode: .literal) }
                    .accessibilityIdentifier(identifier + "-literal")
                Button("Clean") { selection = .init(mode: .clean) }
                    .accessibilityIdentifier(identifier + "-clean")
                Button("Polish") { selection = .init(mode: .polish) }
                    .accessibilityIdentifier(identifier + "-polish")
                if !recipes.isEmpty {
                    Divider()
                    ForEach(recipes) { recipe in
                        Button(L10n.format("Polish: %@", Self.name(of: recipe))) {
                            selection = .init(mode: .polish, recipeID: recipe.id)
                        }
                        .accessibilityIdentifier(identifier + "-recipe-" + recipe.id)
                    }
                }
            } label: {
                modeTitle
            }
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
            .accessibilityValue(modeTitle)
        } label: { label }
    }

    private var modeTitle: Text {
        guard selection.mode == .polish, let recipe = recipes.first(where: { $0.id == selection.recipeID })
        else { return Self.title(for: selection.mode) }
        return Text(verbatim: L10n.format("Polish: %@", Self.name(of: recipe)))
    }

    /// Built-in names are catalog keys, spelled out so the catalog sees them; a custom name is the user's own text.
    static func name(of recipe: DictationRecipe) -> String {
        guard recipe.isBuiltIn else { return recipe.name }
        switch recipe.id {
        case "builtin.formal": return L10n.text("Formal")
        case "builtin.friendly": return L10n.text("Friendly")
        case "builtin.bullets": return L10n.text("Bullet list")
        case "builtin.concise": return L10n.text("Concise")
        default: return L10n.text(recipe.name)
        }
    }

    static func title(for mode: DictationTextMode) -> Text {
        switch mode {
        case .literal: Text("Literal")
        case .clean: Text("Clean")
        case .polish: Text("Polish")
        }
    }

}

/// Off, English or Spanish, with stable menu identifiers like the text mode picker.
struct DictationTranslationPicker: View {
    let identifier: String
    let label: Text
    @Binding var selection: DictationTranslationTarget
    /// Profiles may follow the default instead of choosing a target.
    var followsDefault: Bool = false
    var onFollowDefault: (() -> Void)?

    var body: some View {
        LabeledContent {
            Menu {
                if let onFollowDefault {
                    Button("Default") { onFollowDefault() }
                        .accessibilityIdentifier(identifier + "-default")
                }
                Button("Off") { selection = .off }
                    .accessibilityIdentifier(identifier + "-off")
                Button("English") { selection = .english }
                    .accessibilityIdentifier(identifier + "-en")
                Button("Spanish") { selection = .spanish }
                    .accessibilityIdentifier(identifier + "-es")
            } label: {
                title
            }
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
            .accessibilityValue(title)
        } label: { label }
    }

    private var title: Text {
        if followsDefault { return Text("Default") }
        switch selection {
        case .off: return Text("Off")
        case .english: return Text(verbatim: "→ EN")
        case .spanish: return Text(verbatim: "→ ES")
        }
    }
}
