import AppKit
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

    @Test
    func presetsAddInstalledApplicationsCacheLookupsAndToggleCodeTokens() throws {
        let store = defaults([:])
        let model = DictationTextSettingsModel(defaults: store, temporary: false)
        let installed: Set<String> = ["com.apple.Terminal", "com.apple.mail", "com.tinyspeck.slackmacgap"]
        var lookupCount = 0
        model.isApplicationInstalled = { id in
            lookupCount += 1
            return installed.contains(id)
        }

        #expect(model.availableBundleIdentifiers(for: .code) == ["com.apple.Terminal"])
        let firstCount = lookupCount
        // Repeated body reads hit the cache instead of re-querying LaunchServices.
        #expect(model.availableBundleIdentifiers(for: .code) == ["com.apple.Terminal"])
        #expect(lookupCount == firstCount)

        #expect(model.applyPreset(.code) == 1)
        #expect(model.applyPreset(.code) == 0)
        #expect(model.applyPreset(.email) == 1)
        #expect(model.applyPreset(.chat) == 1)

        let terminal = try #require(model.profiles.first { $0.bundleIdentifier == "com.apple.Terminal" })
        #expect(terminal.mode == .clean)
        #expect(terminal.keepsCodeTokens)

        let mail = try #require(model.profiles.first { $0.bundleIdentifier == "com.apple.mail" })
        #expect(mail.mode == .polish)
        #expect(mail.polishRecipeID == "builtin.formal")

        // Changing mode on a Code profile keeps its code-token protection intact.
        model.setProfile(
            bundleIdentifier: "com.apple.Terminal",
            choice: DictationTextChoice(mode: .polish, recipeID: "builtin.code"))
        let snapshot = DictationTextPreferences.snapshot(in: store, bundleIdentifier: "com.apple.Terminal")
        #expect(snapshot.preservesCodeTokens)
        #expect(snapshot.polishRecipe?.id == "builtin.code")

        // Users can toggle code-token protection off or on for any profile.
        model.setProfile(bundleIdentifier: "com.apple.Terminal", preservesCodeTokens: false)
        #expect(!DictationTextPreferences.snapshot(in: store, bundleIdentifier: "com.apple.Terminal").preservesCodeTokens)
        model.setProfile(bundleIdentifier: "com.apple.mail", preservesCodeTokens: true)
        #expect(DictationTextPreferences.snapshot(in: store, bundleIdentifier: "com.apple.mail").preservesCodeTokens)
    }
}
