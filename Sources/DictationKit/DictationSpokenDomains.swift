import Foundation
import NaturalLanguage

/// Answers whether a word is in a language's dictionary, or nil when that dictionary is missing.
public struct DictationLexicon: Sendable {
    let contains: @Sendable (_ word: String, _ spanish: Bool) -> Bool?

    public init(contains: @escaping @Sendable (_ word: String, _ spanish: Bool) -> Bool?) {
        self.contains = contains
    }

    /// Apple's on-device word embeddings, which some Macs do not have for every language.
    public static let system = Self { word, spanish in
        NLEmbedding.wordEmbedding(for: spanish ? .spanish : .english)?.contains(word)
    }
}

/// Spoken web addresses: "x dot com" and "x punto com" become "x.com".
enum DictationSpokenDomains {
    // No "es": "el punto es que" is everyday Spanish.
    static let topLevelDomains = ["com", "org", "net", "io", "dev", "co", "ai", "app", "edu", "gov", "mx"]
    // "The dot com bubble" and "a polka dot app" name things, not addresses.
    // Per language: Spanish "a" is "to" ("entra a amazon punto com").
    static let englishDeterminers: Set<String> = ["the", "a", "an"]
    static let spanishDeterminers: Set<String> = ["el", "la", "los", "las", "un", "una", "unos", "unas"]

    private static let separator = "[ \\t]+(dot|punto)[ \\t]+"
    // The recognizer spells "www" as letters: "W W W", "w. w. w.", "W.W.W.".
    private static let spelledWeb = "w(?:[.,]?[ \\t]+|\\.)w(?:[.,]?[ \\t]+|\\.)w\\.?"
    private static let expression = try? NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}.])((?:" + spelledWeb + "[ \\t]+(?:dot|punto)[ \\t]+)?"
            + "(?:[\\p{L}\\p{N}][\\p{L}\\p{N}-]*" + separator + ")+)("
            + topLevelDomains.joined(separator: "|") + ")(?![\\p{L}\\p{N}])",
        options: [.caseInsensitive])
    private static let spelledLabel = try? NSRegularExpression(
        pattern: "^" + spelledWeb + "$", options: [.caseInsensitive])
    // It may also write the address after the letters: "W W www.apple.com".
    private static let lettersBeforeWeb = try? NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}.])((?:w[.,]?[ \\t]+){1,3})www(?:\\.[\\p{L}\\p{N}-]+)+", options: [.caseInsensitive])

    /// `claimed` keeps a phrase holding a user's trigger literal.
    static func applying(to text: String, claimed: (String) -> Bool, lexicon: DictationLexicon) -> String {
        guard let expression else { return text }
        let text = droppingLettersBeforeWeb(text, claimed: claimed)
        let source = text as NSString
        let result = NSMutableString(string: text)
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let labels = source.substring(with: match.range(at: 1))
                .replacingOccurrences(of: separator, with: "\n", options: [.regularExpression, .caseInsensitive])
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .map { isSpelledWeb($0) ? "www" : $0 }
            let spanish = source.substring(with: match.range(at: 2)).lowercased() == "punto"
            let determiners = spanish ? spanishDeterminers : englishDeterminers
            guard let first = labels.first?.lowercased(), !determiners.contains(first),
                  !determiners.contains(word(before: match.range.location, in: source)),
                  !claimed(source.substring(with: match.range)),
                  !isProse(first, spanish: spanish, lexicon: lexicon,
                           followedByWord: startsWithWord(after: NSMaxRange(match.range), in: source))
            else { continue }
            let domain = (labels + [source.substring(with: match.range(at: 3))]).joined(separator: ".")
            result.replaceCharacters(in: match.range, with: domain.lowercased())
        }
        return result as String
    }

    /// A dictionary word before "punto com" is Spanish prose ("las empresas punto com"); before
    /// "dot com" it is prose only when a word follows ("many dot com companies"), since English
    /// knows brands such as "apple". Without the dictionary the words stay as spoken.
    private static func isProse(
        _ label: String, spanish: Bool, lexicon: DictationLexicon, followedByWord: Bool
    ) -> Bool {
        guard label != "www", spanish || followedByWord else { return false }
        return lexicon.contains(label, spanish) ?? true
    }

    private static func isSpelledWeb(_ label: String) -> Bool {
        spelledLabel?.firstMatch(in: label, range: NSRange(location: 0, length: (label as NSString).length)) != nil
    }

    private static func droppingLettersBeforeWeb(_ text: String, claimed: (String) -> Bool) -> String {
        guard let lettersBeforeWeb else { return text }
        let source = text as NSString
        let result = NSMutableString(string: text)
        for match in lettersBeforeWeb.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed()
        where !claimed(source.substring(with: match.range)) {
            result.replaceCharacters(in: match.range(at: 1), with: "")
        }
        return result as String
    }

    private static func word(before location: Int, in source: NSString) -> String {
        let prefix = source.substring(to: location) as NSString
        let range = prefix.range(of: "\\p{L}+[ \\t]+$", options: .regularExpression)
        guard range.location != NSNotFound else { return "" }
        return prefix.substring(with: range).trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func startsWithWord(after location: Int, in source: NSString) -> Bool {
        let rest = source.substring(from: location) as NSString
        return rest.range(of: "^[ \\t]+\\p{L}", options: .regularExpression).location != NSNotFound
    }
}
