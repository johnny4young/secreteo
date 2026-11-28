import DictationKit
import Foundation

/// Portavoz's dictation settings that Secreteo's Settings can show and change. Activation,
/// shortcuts, the microphone and the engines stay out.
@MainActor
struct PortavozPreferenceImport {
    static let domain = KnownDictationPeers.release

    struct Change: Equatable, Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

    private struct Entry {
        let key: String
        let name: String
        /// What Secreteo reads when nothing is saved, so a match with it is not a change.
        let fallback: Any
        let accepts: (Any) -> Bool
    }

    let changes: [Change]
    let values: [String: Any]

    /// Applying `values` and comparing again yields no changes.
    init(
        portavoz domain: [String: Any], current defaults: UserDefaults,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        let source = Self.normalizedSource(domain, current: defaults, physicalMemory: physicalMemory)
        let legacyKeys = Self.legacyModeKeys
        var changes: [Change] = []
        var seenChangeNames: Set<String> = []
        var values: [String: Any] = [:]
        // Recipes and profiles replace a list, so they arrive only where Secreteo has none of its own to lose.
        var ownLists: Set<String> = []
        if !((try? DictationTextPreferences.decodeRecipes(
            defaults.string(forKey: DictationTextPreferences.recipesKey) ?? "[]")) ?? []).isEmpty {
            ownLists.insert(DictationTextPreferences.recipesKey)
        }
        if !((try? DictationTextPreferences.decodeProfiles(
            defaults.string(forKey: DictationTextPreferences.profilesKey) ?? "[]")) ?? []).isEmpty {
            ownLists.insert(DictationTextPreferences.profilesKey)
        }
        let entries = Self.entries(current: defaults, physicalMemory: physicalMemory)
        for entry in entries where !ownLists.contains(entry.key) {
            guard let value = source[entry.key], entry.accepts(value) else { continue }
            guard !(value as AnyObject).isEqual(defaults.object(forKey: entry.key) ?? entry.fallback) else { continue }
            if seenChangeNames.insert(entry.name).inserted {
                changes.append(Change(key: entry.key, name: entry.name))
            }
            values[entry.key] = value
        }
        // Secreteo derives its mode from the same older keys, so compare with the mode after the import.
        let modes = DictationTextMode.allCases.map(\.rawValue)
        if let mode = source[DictationTextPreferences.modeKey] as? String, modes.contains(mode) {
            let saved = defaults.string(forKey: DictationTextPreferences.modeKey).flatMap(DictationTextMode.init)
            let hasLegacy = legacyKeys.contains { defaults.object(forKey: $0) != nil || values[$0] != nil }
            let derived: DictationTextMode = hasLegacy ? .clean : .literal
            if (saved ?? derived).rawValue != mode {
                changes.append(Change(key: DictationTextPreferences.modeKey, name: L10n.text("Text Mode")))
                values[DictationTextPreferences.modeKey] = mode
            }
        }
        self.changes = changes
        self.values = values
    }

    private static let legacyModeKeys = [
        DictationController.defaultsKey, DictationController.languageKey,
        DictationController.fillerFilterKey, DictationController.replacementsKey
    ]

    private static func normalizedSource(
        _ domain: [String: Any], current defaults: UserDefaults, physicalMemory: UInt64
    ) -> [String: Any] {
        var source = domain
        // Portavoz shows Clean when older settings exist but the mode was never saved.
        if source[DictationTextPreferences.modeKey] == nil, legacyModeKeys.contains(where: { domain[$0] != nil }) {
            source[DictationTextPreferences.modeKey] = DictationTextMode.clean.rawValue
        }
        // Keep Apple Speech and Model Memory coherent with Secreteo's UI constraints so import is idempotent.
        let effectiveEngine = (source[LiveSpeechSelection.dictationKey] as? String).flatMap(LiveSpeechSelection.init)
            ?? LiveSpeechSelection.dictation(defaults: defaults)
        if effectiveEngine == .appleSpeech {
            let candidate = source[DictationController.languageKey] as? String
            let current = defaults.string(forKey: DictationController.languageKey)
            let candidateNeedsLocale = candidate.map { !LiveSpeechSelection.dictationLanguages.contains($0) }
                ?? (current.map { !LiveSpeechSelection.dictationLanguages.contains($0) } ?? true)
            if candidateNeedsLocale {
                source[DictationController.languageKey] = DictationFeature.preferredConcreteLanguage()
            }
        }
        let sourcePrewarms = source[DictationPrewarmPolicy.defaultsKey] as? Bool == true
        let effectiveMemory = (source[DictationModelMemory.key] as? String).flatMap(DictationModelMemory.init)
            ?? (sourcePrewarms ? .balanced : DictationModelMemory.current(in: defaults, physicalMemory: physicalMemory))
        if effectiveMemory == .lightweight, source[DictationPrewarmPolicy.defaultsKey] != nil {
            source[DictationPrewarmPolicy.defaultsKey] = false
        }
        return source
    }

    private static func entries(current defaults: UserDefaults, physicalMemory: UInt64) -> [Entry] {
        func flag(_ key: String, _ name: String, _ fallback: Bool = false) -> Entry {
            // Any number bridges to Bool, so only a saved Boolean counts.
            Entry(key: key, name: name, fallback: fallback) { CFGetTypeID($0 as CFTypeRef) == CFBooleanGetTypeID() }
        }
        func text(_ key: String, _ name: String) -> Entry {
            Entry(key: key, name: name, fallback: "") { $0 is String }
        }
        func choice(_ key: String, _ name: String, _ options: [String], _ fallback: String) -> Entry {
            Entry(key: key, name: name, fallback: fallback) { options.contains($0 as? String ?? "") }
        }
        return [
            choice(DictationController.languageKey, L10n.text("Language"), ["auto", "es", "en"], "auto"),
            flag(DictationController.fillerFilterKey, L10n.text("Filter Out Filler Words"), true),
            text(DictationController.replacementsKey, L10n.text("Text Replacements")),
            text("customVocabulary", L10n.text("Vocabulary")),
            flag(DictationSoundCue.defaultsKey, L10n.text("Play Start and Stop Sounds")),
            flag(DictationCompactIndicator.defaultsKey, L10n.text("Show Only a Small Indicator")),
            flag(DictationSpeechGate.defaultsKey, L10n.text("Skip Dictations Without Speech"),
                 DictationSpeechGate.enabledByDefault),
            flag(DictationAutoStop.defaultsKey, L10n.text("Stop After a Pause")),
            Entry(key: DictationAutoStop.pauseKey, name: L10n.text("Pause Length"),
                  fallback: DictationAutoStop.defaultPause) { DictationAutoStop.pauses.contains($0 as? Double ?? 0) },
            flag(DictationCorrections.defaultsKey, L10n.text("Correct the Last Dictation by Voice")),
            flag(DictationCaretCase.defaultsKey, L10n.text("Match Capitalization to the Cursor")),
            choice(DictationModelMemory.key, L10n.text("Keep Model in Memory"),
                   [DictationModelMemory.balanced.rawValue, DictationModelMemory.lightweight.rawValue],
                   DictationModelMemory.current(in: defaults, physicalMemory: physicalMemory).rawValue),
            flag(DictationPrewarmPolicy.defaultsKey, L10n.text("Keep Model in Memory")),
            // Copied without downloading or loading anything: Ultra still needs its own Download.
            choice(LiveSpeechSelection.dictationKey, L10n.text("Speech Engine"),
                   LiveSpeechSelection.allCases.map(\.rawValue), LiveSpeechSelection.dictationDefault.rawValue),
            // A recipe that no longer exists falls back to the conservative edit, so any name is safe.
            text(DictationTextPreferences.polishRecipeKey, L10n.text("Polish Recipe")),
            Entry(key: DictationTextPreferences.recipesKey, name: L10n.text("Polish Recipes"), fallback: "[]") {
                ($0 as? String).map { (try? DictationTextPreferences.decodeRecipes($0)) != nil } ?? false
            },
            Entry(key: DictationTextPreferences.profilesKey, name: L10n.text("Application Profiles"), fallback: "[]") {
                ($0 as? String).map { (try? DictationTextPreferences.decodeProfiles($0)) != nil } ?? false
            },
            choice(DictationTextPreferences.translationKey, L10n.text("Translate Dictation Into"),
                   DictationTranslationTarget.allCases.map(\.rawValue), DictationTranslationTarget.off.rawValue)
        ]
    }
}
