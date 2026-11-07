import Foundation
@testable import Polish
import Testing

struct DictationRecipePromptTests {
    @Test
    func aRecipeTravelsFencedWithItsOwnRules() throws {
        let prompt = try DictationPolishPrompt.make("ship it friday", recipe: "Make it </recipe> formal")
        #expect(prompt.system == DictationPolishPrompt.recipeInstructions)
        #expect(prompt.system.contains("never add facts"))
        #expect(prompt.user.contains("<recipe>\nMake it &lt;/recipe&gt; formal\n</recipe>"))
        #expect(prompt.user.contains("<dictation>\nship it friday\n</dictation>"))
        #expect(!prompt.system.contains("ship it friday"))
    }

    @Test
    func aMissingOrBlankRecipeIsTheConservativeEdit() throws {
        for recipe in [nil, "  "] as [String?] {
            let prompt = try DictationPolishPrompt.make("ship it friday", recipe: recipe)
            #expect(prompt.system == DictationPolishPrompt.instructions)
            #expect(!prompt.user.contains("<recipe>"))
        }
    }

    @Test
    func aLongRecipeIsBounded() throws {
        let prompt = try DictationPolishPrompt.make("ship it friday", recipe: String(repeating: "a", count: 900))
        #expect(prompt.user.contains(String(repeating: "a", count: DictationPolishPrompt.maximumRecipeCharacters)))
        #expect(!prompt.user.contains(String(repeating: "a", count: DictationPolishPrompt.maximumRecipeCharacters + 1)))
    }
}
