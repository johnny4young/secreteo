import Foundation
import Observation
import DictationKit

/// Settings commands own preference writes; SwiftUI only renders the observable snapshot.
@MainActor
@Observable
final class DictationTextSettingsModel {
    enum SelectionError { case invalidApplication, unavailableWindow }
    private(set) var globalMode: DictationTextMode
    private(set) var globalRecipeID: String?
    private(set) var globalTranslationTarget: DictationTranslationTarget
    private(set) var customRecipes: [DictationRecipe] = []
    private(set) var hasInvalidRecipes = false
    private(set) var profiles: [DictationApplicationTextProfile] = []
    private(set) var hasInvalidProfiles = false
    private(set) var selectionError: SelectionError?
    private(set) var isSelectingApplication = false
    /// Whether any session can use Clean or Polish, the modes that apply the
    /// filler filter and replacement rules. Unreadable profiles fall back to
    /// the default mode at runtime, so they do not count.
    var cleanModeInUse: Bool {
        globalMode.appliesCleanRules || (!hasInvalidProfiles && profiles.contains { $0.mode.appliesCleanRules })
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let temporary: Bool
    @ObservationIgnored private var applicationDisplays: [String: DictationApplicationDisplay] = [:]
    @ObservationIgnored private var installedPresetApps: [String: Bool] = [:]
    @ObservationIgnored var resolveApplication: (String) -> DictationApplicationDisplay = {
        DictationApplicationDisplay.resolve(bundleIdentifier: $0)
    }
    @ObservationIgnored var isApplicationInstalled: (String) -> Bool = {
        DictationApplicationDisplay.isInstalled(bundleIdentifier: $0)
    }

    /// A missing app is resolved again on the next render, so a later install or mount shows up.
    func applicationDisplay(for bundleIdentifier: String) -> DictationApplicationDisplay {
        if let cached = applicationDisplays[bundleIdentifier] { return cached }
        let resolved = resolveApplication(bundleIdentifier)
        if resolved.icon != nil { applicationDisplays[bundleIdentifier] = resolved }
        return resolved
    }

    func rememberApplicationURL(_ url: URL, for bundleIdentifier: String) {
        applicationDisplays[bundleIdentifier] = DictationApplicationDisplay.resolve(
            bundleIdentifier: bundleIdentifier, knownURL: url)
    }

    init(defaults: UserDefaults, temporary: Bool) {
        self.defaults = defaults
        self.temporary = temporary
        DictationTextPreferences.initialize(in: defaults, temporary: temporary)
        globalMode = DictationTextPreferences.globalMode(in: defaults)
        globalRecipeID = DictationTextPreferences.globalRecipeID(in: defaults)
        globalTranslationTarget = DictationTextPreferences.globalTranslationTarget(in: defaults)
        reload()
    }

    /// Reads the saved values again, for a writer outside this model such as an import.
    func reload() {
        globalMode = DictationTextPreferences.globalMode(in: defaults)
        globalRecipeID = DictationTextPreferences.globalRecipeID(in: defaults)
        globalTranslationTarget = DictationTextPreferences.globalTranslationTarget(in: defaults)
        do {
            customRecipes = try DictationTextPreferences.decodeRecipes(
                defaults.string(forKey: DictationTextPreferences.recipesKey) ?? "[]")
            hasInvalidRecipes = false
        } catch {
            customRecipes = []
            hasInvalidRecipes = true
        }
        do {
            profiles = try DictationTextPreferences.decodeProfiles(
                defaults.string(forKey: DictationTextPreferences.profilesKey) ?? "[]")
            hasInvalidProfiles = false
        } catch {
            profiles = []
            hasInvalidProfiles = true
        }
    }

    func setGlobalMode(_ mode: DictationTextMode) {
        setGlobalChoice(DictationTextChoice(mode: mode))
    }

    var globalChoice: DictationTextChoice { DictationTextChoice(mode: globalMode, recipeID: globalRecipeID) }
    var recipes: [DictationRecipe] { DictationRecipe.builtIns + customRecipes }

    func setGlobalChoice(_ choice: DictationTextChoice) {
        write(choice.mode.rawValue, forKey: DictationTextPreferences.modeKey)
        write(choice.recipeID ?? "", forKey: DictationTextPreferences.polishRecipeKey)
        globalMode = choice.mode
        globalRecipeID = choice.recipeID
    }

    func setProfile(bundleIdentifier: String, mode: DictationTextMode) {
        setProfile(bundleIdentifier: bundleIdentifier, choice: DictationTextChoice(mode: mode))
    }

    func setProfile(
        bundleIdentifier: String,
        choice: DictationTextChoice,
        preservesCodeTokens: Bool? = nil
    ) {
        guard !hasInvalidProfiles, DictationTextPreferences.isValidBundleIdentifier(bundleIdentifier) else {
            selectionError = .invalidApplication
            return
        }
        let existing = profiles.first { $0.bundleIdentifier == bundleIdentifier }
        var updated = profiles.filter { $0.bundleIdentifier != bundleIdentifier }
        let translation = existing?.translationTarget
        let keepsCode = preservesCodeTokens ?? existing?.preservesCodeTokens
        updated.append(.init(
            bundleIdentifier: bundleIdentifier, mode: choice.mode, polishRecipeID: choice.recipeID,
            translationTarget: translation, preservesCodeTokens: keepsCode))
        save(updated)
    }

    func setProfile(bundleIdentifier: String, preservesCodeTokens: Bool) {
        guard !hasInvalidProfiles, var profile = profiles.first(where: { $0.bundleIdentifier == bundleIdentifier })
        else { return }
        profile.preservesCodeTokens = preservesCodeTokens ? true : nil
        save(profiles.filter { $0.bundleIdentifier != bundleIdentifier } + [profile])
    }

    /// Refreshes cached installation status for preset bundle identifiers when the disclosure opens.
    func refreshInstalledPresets() {
        installedPresetApps.removeAll()
        for preset in DictationProfilePreset.allCases {
            for identifier in preset.bundleIdentifiers {
                installedPresetApps[identifier] = isApplicationInstalled(identifier)
            }
        }
    }

    /// Installed applications matching `preset` that do not yet have a saved profile.
    func availableBundleIdentifiers(for preset: DictationProfilePreset) -> [String] {
        guard !hasInvalidProfiles else { return [] }
        let existing = Set(profiles.map(\.bundleIdentifier))
        return preset.bundleIdentifiers.filter { identifier in
            guard !existing.contains(identifier) else { return false }
            if let cached = installedPresetApps[identifier] { return cached }
            let installed = isApplicationInstalled(identifier)
            installedPresetApps[identifier] = installed
            return installed
        }
    }

    /// Adds profiles for every installed application matching `preset` that is not already configured.
    @discardableResult
    func applyPreset(_ preset: DictationProfilePreset) -> Int {
        guard !hasInvalidProfiles else { return 0 }
        let room = max(0, DictationTextPreferences.maximumProfiles - profiles.count)
        let additions = availableBundleIdentifiers(for: preset).prefix(room)
        guard !additions.isEmpty else { return 0 }
        let newProfiles = additions.map { preset.makeProfile(bundleIdentifier: $0) }
        save(profiles + newProfiles)
        return newProfiles.count
    }

    func setGlobalTranslationTarget(_ target: DictationTranslationTarget) {
        write(target.rawValue, forKey: DictationTextPreferences.translationKey)
        globalTranslationTarget = target
    }

    /// Nil makes the application follow the default translation.
    func setProfile(bundleIdentifier: String, translationTarget: DictationTranslationTarget?) {
        guard !hasInvalidProfiles, var profile = profiles.first(where: { $0.bundleIdentifier == bundleIdentifier })
        else { return }
        profile.translationTarget = translationTarget
        save(profiles.filter { $0.bundleIdentifier != bundleIdentifier } + [profile])
    }

    /// Adds a recipe or replaces the one with its identifier. False when it does not fit.
    @discardableResult
    func saveRecipe(_ recipe: DictationRecipe) -> Bool {
        guard !hasInvalidRecipes, !recipe.isBuiltIn else { return false }
        var updated = customRecipes
        if let index = updated.firstIndex(where: { $0.id == recipe.id }) {
            updated[index] = recipe
        } else {
            updated.append(recipe)
        }
        return saveRecipes(updated)
    }

    /// A deleted recipe leaves its users on the conservative copy edit.
    func deleteRecipe(id: String) {
        guard !hasInvalidRecipes else { return }
        saveRecipes(customRecipes.filter { $0.id != id })
    }

    func resetRecipes() {
        hasInvalidRecipes = false
        saveRecipes([])
    }

    var canAddRecipe: Bool { !hasInvalidRecipes && customRecipes.count < DictationRecipe.maximumCustomRecipes }

    @discardableResult
    private func saveRecipes(_ updated: [DictationRecipe]) -> Bool {
        guard let json = try? DictationTextPreferences.encodeRecipes(updated) else { return false }
        write(json, forKey: DictationTextPreferences.recipesKey)
        customRecipes = updated
        hasInvalidRecipes = false
        return true
    }

    func removeProfile(bundleIdentifier: String) {
        guard !hasInvalidProfiles else { return }
        save(profiles.filter { $0.bundleIdentifier != bundleIdentifier })
    }

    func beginApplicationSelection() -> Bool {
        guard !isSelectingApplication, !hasInvalidProfiles else { return false }
        isSelectingApplication = true
        selectionError = nil
        return true
    }

    func finishApplicationSelection() { isSelectingApplication = false }
    func resetProfiles() { save([]) }
    func reportSelectionError(_ error: SelectionError = .invalidApplication) { selectionError = error }

    private func save(_ updated: [DictationApplicationTextProfile]) {
        do {
            let json = try DictationTextPreferences.encodeProfiles(updated)
            write(json, forKey: DictationTextPreferences.profilesKey)
            profiles = updated.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
            hasInvalidProfiles = false
            selectionError = nil
        } catch { selectionError = .invalidApplication }
    }

    private func write(_ value: String, forKey key: String) {
        DictationTextPreferences.store(value, forKey: key, in: defaults, temporary: temporary)
    }
}
