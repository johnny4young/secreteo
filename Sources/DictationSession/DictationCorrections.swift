import Foundation

/// Spoken corrections of the last insertion; off by default.
enum DictationCorrections {
    static let defaultsKey = "dictationCorrectionCommands"

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }
}

/// One-shot post-paste edit observation to suggest learning manual corrections; off by default.
enum DictationEditLearning {
    static let defaultsKey = "dictationLearnFromEdits"
    static let observationDelay: Duration = .seconds(5)

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }
}
