import AppKit
import NaturalLanguage
import DictationKit

/// Matches the first dictated word's case to the sentence before the caret. Opt-in:
/// lowering a capital is done only for a word the system dictionary knows in lowercase
/// and that is not a name, an acronym, "I" or one of the user's own spellings.
@MainActor
struct DictationCaretCase {
    nonisolated static let defaultsKey = "dictationCaretCase"
    /// UTF-16 units read before the caret, only while the field is revalidated; never kept.
    nonisolated static let contextLength = 80

    enum Position: Equatable { case sentenceStart, midSentence, unknown }

    // Escaped so the English-source guard does not read them as Spanish prose.
    private static let openers: Set<Character> = ["(", "[", "{", "\u{BF}", "\u{A1}", "“", "‘", "«", "\"", "'"]
    private static let closers: Set<Character> = [")", "]", "}", "»", "”", "’", "\"", "'"]
    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]
    private static let continues: Set<Character> = [",", ";"]
    private static let abbreviations: Set<String> = [
        "e.g.", "i.e.", "etc.", "vs.", "dr.", "dra.", "mr.", "mrs.", "ms.", "sr.", "sra.", "srta.",
        "st.", "no.", "p.ej.", "ej.", "ud.", "uds.", "approx.", "aprox."
    ]

    /// Single-word spellings the user chose; never recased.
    var protectedWords: Set<String> = []
    /// Full replacement and vocabulary phrases matched at the start of the text.
    var protectedPhrases: [String] = []
    var isCommonWord: @MainActor (String) -> Bool = Self.systemDictionaryKnows
    var isName: @MainActor (_ word: String, _ sentence: String) -> Bool = Self.taggedAsName

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    /// Nil while the setting is off, so only the two characters of D560 are read.
    @MainActor
    static func live(_ defaults: UserDefaults = .standard) -> Self? {
        guard isEnabled(in: defaults) else { return nil }
        let rules = DictationTextRules.decode(
            replacements: defaults.string(forKey: DictationController.replacementsKey) ?? "")
        let vocabulary = DictationVocabularyNormalizer.parse(
            defaults.string(forKey: DictationController.vocabularyKey) ?? "")
        let allTerms = (rules.map(\.replacement) + vocabulary)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var words = Set<String>()
        var phrases: [String] = []
        for term in allTerms {
            if term.contains(where: \.isWhitespace) {
                phrases.append(term)
            } else {
                let cleaned = term.trimmingCharacters(in: .punctuationCharacters)
                if !cleaned.isEmpty { words.insert(cleaned) }
            }
        }
        return Self(
            protectedWords: words,
            protectedPhrases: phrases.sorted { $0.count > $1.count })
    }

    /// - Parameter atFieldStart: true when `preceding` reaches the start of the field.
    static func position(after preceding: String, atFieldStart: Bool) -> Position {
        var text = Substring(preceding)
        let blank = text.reversed().prefix { $0.isWhitespace }
        if blank.contains(where: \.isNewline) { return .sentenceStart }
        text = text.dropLast(blank.count)
        while let last = text.last, openers.contains(last) { text = text.dropLast() }
        text = Substring(text.reversed().drop(while: \.isWhitespace).reversed())
        guard let last = text.last else { return atFieldStart ? .sentenceStart : .unknown }
        if sentenceEnds.contains(last) {
            let token = text.split(whereSeparator: \.isWhitespace).last.map { $0.lowercased() } ?? ""
            let bare = token.drop { openers.contains($0) }
            return abbreviations.contains(String(bare)) || isInitial(bare) ? .unknown : .sentenceStart
        }
        if closers.contains(last) { return .unknown }
        return last.isLetter || last.isNumber || continues.contains(last) ? .midSentence : .unknown
    }

    func adapt(_ text: String, after preceding: String, atFieldStart: Bool) -> String {
        guard let start = text.firstIndex(where: { !Self.openers.contains($0) && !$0.isWhitespace }),
              text[start].isLetter else { return text }
        let word = String(text[start...].prefix { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" })
        switch Self.position(after: preceding, atFieldStart: atFieldStart) {
        case .sentenceStart:
            guard text[start].isLowercase, !keepsSpelling(word, in: text[start...]) else { return text }
            return text.replacingCharacters(in: start...start, with: text[start].uppercased())
        case .midSentence:
            guard keepsCapital(word, in: text[start...], sentence: preceding + " " + text) == false else { return text }
            return text.replacingCharacters(in: start...start, with: text[start].lowercased())
        case .unknown:
            return text
        }
    }

    /// Spellings a capital would break: the user's own, `iPhone`, `macOS`, and addresses.
    private func keepsSpelling(_ word: String, in text: Substring) -> Bool {
        if startsWithProtectedPhrase(text) { return true }
        let token = text.prefix { !$0.isWhitespace }
        let trimmedToken = token.trimmingCharacters(in: .punctuationCharacters)
        if protectedWords.contains(word) || protectedWords.contains(trimmedToken)
            || word.contains(where: \.isUppercase) { return true }
        return token.contains { "/@_".contains($0) } || trimmedToken.contains(".")
    }

    private func keepsCapital(_ word: String, in text: Substring, sentence: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return true }
        let rest = word.dropFirst()
        if word == "I" || word.hasPrefix("I'") || word.hasPrefix("I’") { return true }
        if rest.contains(where: \.isUppercase) { return true }
        if startsWithProtectedPhrase(text) { return true }
        let token = text.prefix { !$0.isWhitespace }
        let trimmedToken = token.trimmingCharacters(in: .punctuationCharacters)
        if protectedWords.contains(word) || protectedWords.contains(trimmedToken) { return true }
        if trimmedToken.contains(".") || trimmedToken.contains(where: \.isNumber)
            || token.contains(where: { "/@_".contains($0) }) {
            return true
        }
        return !isCommonWord(word.lowercased()) || isName(word, sentence)
    }

    private func startsWithProtectedPhrase(_ text: Substring) -> Bool {
        for phrase in protectedPhrases where text.hasPrefix(phrase) {
            let after = text.index(text.startIndex, offsetBy: phrase.count)
            if after == text.endIndex || !(text[after].isLetter || text[after].isNumber) {
                return true
            }
        }
        return false
    }

    /// "J." in "J. Smith" ends no sentence.
    private static func isInitial(_ token: Substring) -> Bool {
        token.count == 2 && token.first?.isLetter == true
    }

    @MainActor
    static func systemDictionaryKnows(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        return ["en", "es"].contains { language in
            checker.availableLanguages.contains(language)
                && checker.checkSpelling(
                    of: word, startingAt: 0, language: language, wrap: false,
                    inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
    }

    static func taggedAsName(_ word: String, in sentence: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = sentence
        var named = false
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag),
               sentence[range].split(separator: " ").contains(where: { $0 == word }) {
                named = true
                return false
            }
            return true
        }
        return named
    }
}
