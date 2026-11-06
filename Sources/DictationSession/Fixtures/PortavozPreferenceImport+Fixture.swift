import Foundation

extension PortavozPreferenceImport {
    /// Synthetic Portavoz settings for UI tests: four to import, and two that never are.
    static var fixture: [String: Any] {
        [
            DictationController.languageKey: "es",
            DictationSoundCue.defaultsKey: true,
            DictationCompactIndicator.defaultsKey: true,
            DictationTextPreferences.modeKey: "clean",
            "dictationHotkeyKeyCode": 2,
            "dictationTranslationTarget": "en"
        ]
    }
}
