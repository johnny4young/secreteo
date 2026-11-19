import Foundation
import NaturalLanguage

/// Spoken web addresses: "x dot com" and "x punto com" become "x.com".
enum DictationSpokenDomains {
    // No "es": "el punto es que" is everyday Spanish.
    static let topLevelDomains = ["com", "org", "net", "io", "dev", "co", "ai", "app", "edu", "gov", "mx"]
    // "The dot com bubble" and "a polka dot app" name things, not addresses.
    static let determiners: Set<String> = [
        "the", "a", "an", "el", "la", "los", "las", "un", "una", "unos", "unas"
    ]

    private static let separator = "[ \\t]+(dot|punto)[ \\t]+"
    private static let expression = try? NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}.])((?:[\\p{L}\\p{N}][\\p{L}\\p{N}-]*" + separator + ")+)("
            + topLevelDomains.joined(separator: "|") + ")(?![\\p{L}\\p{N}])",
        options: [.caseInsensitive])

    /// `claimed` keeps a phrase holding a user's trigger literal.
    static func applying(to text: String, claimed: (String) -> Bool) -> String {
        guard let expression else { return text }
        let source = text as NSString
        let result = NSMutableString(string: text)
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let labels = source.substring(with: match.range(at: 1))
                .replacingOccurrences(of: separator, with: "\n", options: [.regularExpression, .caseInsensitive])
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = labels.first?.lowercased(), !determiners.contains(first),
                  !determiners.contains(word(before: match.range.location, in: source)),
                  !claimed(source.substring(with: match.range)),
                  !isProse(first, spanish: source.substring(with: match.range(at: 2)).lowercased() == "punto",
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
    private static func isProse(_ label: String, spanish: Bool, followedByWord: Bool) -> Bool {
        guard spanish || followedByWord else { return false }
        guard let words = NLEmbedding.wordEmbedding(for: spanish ? .spanish : .english) else { return true }
        return words.contains(label)
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
