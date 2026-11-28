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
    /// A fix still being typed changes between two reads this far apart.
    static let settleDelay: Duration = .milliseconds(500)

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }
}
