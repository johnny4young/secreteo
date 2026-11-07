import Foundation

extension PortavozPreferenceImport {
    /// Synthetic Portavoz settings for UI tests: three to import, a mode and an engine Secreteo already uses,
    /// and a shortcut that never imports.
    static var fixture: [String: Any] {
        [
            DictationController.languageKey: "es",
            DictationSoundCue.defaultsKey: true,
            DictationCompactIndicator.defaultsKey: true,
            DictationTextPreferences.modeKey: "clean",
            "dictationHotkeyKeyCode": 2,
            "dictationLiveSpeechEngine": "parakeetUltra"
        ]
    }
}
