import Foundation

/// Spoken web addresses: "x dot com" and "x punto com" become "x.com".
enum DictationSpokenDomains {
    // No "es": "el punto es que" is everyday Spanish.
    static let topLevelDomains = ["com", "org", "net", "io", "dev", "co", "ai", "app", "edu", "gov", "mx"]
    // "The dot com bubble" names an era, not an address.
    static let articles: Set<String> = ["the", "a", "an", "el", "la", "un", "una"]

    private static let separator = "[ \\t]+(?:dot|punto)[ \\t]+"
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
            guard let first = labels.first, !articles.contains(first.lowercased()),
                  !claimed(source.substring(with: match.range)) else { continue }
            let domain = (labels + [source.substring(with: match.range(at: 2))]).joined(separator: ".")
            result.replaceCharacters(in: match.range, with: domain.lowercased())
        }
        return result as String
    }
}
