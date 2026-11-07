import DictationKit
import Foundation
import Testing

@testable import DictationSession

/// Reads defaults, so it shares the guard of the suites that write the process-wide argument domain.
@Suite(.serialized, .exclusiveArgumentDomain)
@MainActor
struct DictationRecipePreferenceTests {
    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "dictation-recipes-\(UUID().uuidString)")!
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    private let custom = DictationRecipe(id: "custom-1", name: "Standup", instruction: "Write it as a standup note.")

    @Test
    func theDefaultAndTheProfileEachChooseARecipe() throws {
        let json = try DictationTextPreferences.encodeRecipes([custom])
        let store = defaults([
            DictationTextPreferences.modeKey: "polish",
            DictationTextPreferences.polishRecipeKey: "builtin.formal",
            DictationTextPreferences.recipesKey: json,
            DictationTextPreferences.profilesKey:
                #"[{"bundleIdentifier":"com.johnny4young.secreteo.example","mode":"polish","polishRecipeID":"custom-1"}]"#
        ])
        let global = DictationTextPreferences.snapshot(in: store, bundleIdentifier: "com.johnny4young.secreteo.other")
        #expect(global.polishRecipe?.id == "builtin.formal")
        let profile = DictationTextPreferences.snapshot(in: store, bundleIdentifier: "com.johnny4young.secreteo.example")
        #expect(profile.polishRecipe == custom)
        #expect(profile.recipes.count == DictationRecipe.builtIns.count + 1)
    }

    @Test
    func aDeletedRecipeFallsBackToTheConservativeEdit() {
        let store = defaults([
            DictationTextPreferences.modeKey: "polish", DictationTextPreferences.polishRecipeKey: "custom-gone"
        ])
        let snapshot = DictationTextPreferences.snapshot(in: store, bundleIdentifier: nil)
        #expect(snapshot.mode == .polish)
        #expect(snapshot.polishRecipe == nil)
        #expect(snapshot.choice == DictationTextChoice(mode: .polish))
    }

    @Test
    func theCatalogRejectsBuiltInsDuplicatesAndOversizedRecipes() throws {
        #expect(throws: (any Error).self) { try DictationTextPreferences.encodeRecipes([DictationRecipe.builtIns[0]]) }
        #expect(throws: (any Error).self) { try DictationTextPreferences.encodeRecipes([custom, custom]) }
        let long = DictationRecipe(id: "x", name: "Long", instruction: String(repeating: "a", count: 501))
        #expect(throws: (any Error).self) { try DictationTextPreferences.encodeRecipes([long]) }
        let many = (0...DictationRecipe.maximumCustomRecipes).map {
            DictationRecipe(id: "id-\($0)", name: "R\($0)", instruction: "Do \($0).")
        }
        #expect(throws: (any Error).self) { try DictationTextPreferences.encodeRecipes(many) }
        #expect(throws: (any Error).self) { try DictationTextPreferences.decodeRecipes("not json") }
    }

    @Test
    func settingsSaveEditAndDeleteRecipesWithinTheLimit() {
        let model = DictationTextSettingsModel(defaults: defaults([:]), temporary: false)
        #expect(model.saveRecipe(custom))
        #expect(model.recipes.last == custom)
        var edited = custom
        edited.instruction = "Write it as a short standup note."
        #expect(model.saveRecipe(edited))
        #expect(model.customRecipes == [edited])
        #expect(!model.saveRecipe(DictationRecipe.builtIns[0]))
        model.setGlobalChoice(DictationTextChoice(mode: .polish, recipeID: custom.id))
        #expect(model.globalChoice.recipeID == custom.id)
        model.deleteRecipe(id: custom.id)
        #expect(model.customRecipes.isEmpty)
        for index in 0..<DictationRecipe.maximumCustomRecipes {
            #expect(model.saveRecipe(DictationRecipe(id: "id-\(index)", name: "R\(index)", instruction: "Do it.")))
        }
        #expect(!model.canAddRecipe)
        #expect(!model.saveRecipe(DictationRecipe(id: "one-more", name: "Extra", instruction: "Do it.")))
    }

    @Test
    func aUnreadableCatalogOffersOnlyTheBuiltInsUntilReset() {
        let model = DictationTextSettingsModel(
            defaults: defaults([DictationTextPreferences.recipesKey: "not json"]), temporary: false)
        #expect(model.hasInvalidRecipes)
        #expect(model.recipes == DictationRecipe.builtIns)
        #expect(!model.saveRecipe(custom))
        model.resetRecipes()
        #expect(!model.hasInvalidRecipes)
        #expect(model.saveRecipe(custom))
    }

    @Test
    func aProfileThatTranslatesCountsAsTranslationInUse() throws {
        let profile = DictationApplicationTextProfile(
            bundleIdentifier: "com.example.mail", mode: .clean, translationTarget: .english)
        let model = DictationTextSettingsModel(
            defaults: defaults([DictationTextPreferences.profilesKey: try DictationTextPreferences.encodeProfiles([profile])]),
            temporary: false)
        #expect(model.globalTranslationTarget == .off)
        #expect(model.translationInUse)
        let quiet = DictationTextSettingsModel(defaults: defaults([:]), temporary: false)
        #expect(!quiet.translationInUse)
    }
}
