import DictationKit
import Foundation

/// Portavoz's dictation settings that Secreteo's Settings can show and change. Activation,
/// shortcuts, the microphone, the engines, recipes, translation and per-app profiles stay out.
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
    init(portavoz domain: [String: Any], current defaults: UserDefaults) {
        var source = domain
        // Portavoz shows Clean when older settings exist but the mode was never saved.
        let legacyKeys = [DictationController.defaultsKey, DictationController.languageKey,
                          DictationController.fillerFilterKey, DictationController.replacementsKey]
        if source[DictationTextPreferences.modeKey] == nil, legacyKeys.contains(where: { domain[$0] != nil }) {
            source[DictationTextPreferences.modeKey] = DictationTextMode.clean.rawValue
        }
        var changes: [Change] = []
        var values: [String: Any] = [:]
        for entry in Self.entries {
            guard let value = source[entry.key], entry.accepts(value) else { continue }
            guard !(value as AnyObject).isEqual(defaults.object(forKey: entry.key) ?? entry.fallback) else { continue }
            changes.append(Change(key: entry.key, name: entry.name))
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

    private static var entries: [Entry] {
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
            choice(DictationModelMemory.key, L10n.text("Free the Model Soon After Dictating"),
                   [DictationModelMemory.balanced.rawValue, DictationModelMemory.lightweight.rawValue],
                   DictationModelMemory.balanced.rawValue),
            flag(DictationPrewarmPolicy.defaultsKey, L10n.text("Load the Speech Model at Launch"))
        ]
    }
}
