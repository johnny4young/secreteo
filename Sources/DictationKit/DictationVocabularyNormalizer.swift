import Foundation

/// Deterministic post-ASR normalization for the user's personal vocabulary.
/// Runs in Clean/Polish mode so names and technical terms work with Parakeet
/// (which does not accept a vocabulary prompt), while protecting URLs, emails,
/// paths, explicit replacement triggers, and real English/Spanish dictionary words.
public enum DictationVocabularyNormalizer {
    private static let maximumTerms = 100
    private static let minimumCompoundLength = 5
    private static let minimumFuzzyLength = 6
    private static let minimumJoinedPunctuatedLength = 4
    private static let minimumPluralStemLength = 4
    private static let apostrophes: Set<Character> = ["'", "\u{2019}"]
    private static let contractionStems: Set<String> = [
        "it", "he", "she", "that", "what", "who", "there", "here", "let", "where", "when", "why", "how"
    ]

    private struct Entry {
        let spelling: String
        let parts: [String]
        let foldedJoined: String
        let hasInternalDot: Bool
        let hasInternalApostrophe: Bool
        let isSpaceFree: Bool
        let camelSplitOffsets: Set<Int>
    }

    private struct Token {
        let range: Range<String.Index>
        let text: String
        let folded: String
        let precededByApostrophe: Bool
        let followedByApostrophe: Bool
        let followedByPossessiveS: Bool
        let precededByHyphen: Bool
        let followedByHyphen: Bool
    }

    private static let protectedExpression: NSRegularExpression? = {
        let tlds = DictationSpokenDomains.topLevelDomains.joined(separator: "|")
        let pattern =
            #"(?:https?://|www\.)[^\s]+[^\s.,;:!?)\]]"#
            + #"|[\w.+-]+@[\w-]+(?:\.[\w-]+)+"#
            + #"|(?<![\w@])[@#][\p{L}\p{N}_]+"#
            + #"|(?<![\p{L}\p{N}])(?:[\p{L}\p{N}_-]+\.)+(?:"# + tlds + #")(?![\p{L}\p{N}])"#
            + #"|(?:~|\.\.?|[\p{L}\p{N}_-]+)?(?:/[\p{L}\p{N}_.-]+){2,}"#
            + #"|(?:~|\.\.?)/[\p{L}\p{N}_.-]+"#
            + #"|(?<!\S)/[\p{L}\p{N}_.-]+"#
            + #"|[\p{L}\p{N}_-]+/[\p{L}\p{N}_-]+\.[\p{L}\p{N}_-]+"#
            + #"|[^\s]*\\[^\s]+"#
            + #"|[\p{L}\p{N}]*_[\p{L}\p{N}_]+"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static let tokenExpression = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)

    private static let codeTokenExpression = try? NSRegularExpression(
        pattern: #"`[^`]+`|(?<![\p{L}\p{N}_-])--?[a-zA-Z0-9][a-zA-Z0-9-]*(?:=[a-zA-Z0-9._/-]+)?"#
            + #"|\b[a-z][a-z0-9]*[A-Z][a-zA-Z0-9]*\b"#)

    /// Parses the comma- or newline-separated vocabulary string stored in preferences.
    public static func parse(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func applying(
        _ vocabulary: [String],
        to rawText: String,
        claimed: (String) -> Bool = { _ in false },
        excludedRanges: [Range<String.Index>] = [],
        preservesCodeTokens: Bool = false,
        lexicon: DictationLexicon = .system
    ) -> String {
        let entries = prepareEntries(vocabulary)
        guard !entries.isEmpty, !rawText.isEmpty else { return rawText }
        // Precompose decomposed accents (e.g. e + U+0301) so regex tokens cover full characters.
        let text = rawText.precomposedStringWithCanonicalMapping
        let mappedExclusions = mapExcludedRanges(excludedRanges, from: rawText, to: text)
        let dotEntries = Set(entries.filter(\.hasInternalDot).map { fold($0.spelling) })
        var protected = protectedRanges(in: text, exemptDotTerms: dotEntries) + mappedExclusions
        if preservesCodeTokens {
            protected += codeTokenRanges(in: text)
        }
        let tokens = extractTokens(in: text, excluding: protected)
        guard !tokens.isEmpty else { return rawText }

        let edits = collectEdits(tokens: tokens, in: text, entries: entries, claimed: claimed, lexicon: lexicon)
        guard !edits.isEmpty else { return rawText }
        var output = text
        for (range, replacement) in edits.reversed() {
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }

    private static func collectEdits(
        tokens: [Token], in text: String, entries: [Entry],
        claimed: (String) -> Bool, lexicon: DictationLexicon
    ) -> [(Range<String.Index>, String)] {
        let multiWord = entries.filter { $0.parts.count > 1 }
            .sorted { ($0.parts.count, $0.spelling.count) > ($1.parts.count, $1.spelling.count) }
        let singleWord = entries.filter { $0.parts.count == 1 }
        var exactSingle = Dictionary(singleWord.map { ($0.foldedJoined, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in multiWord where entry.isSpaceFree && entry.foldedJoined.count >= minimumJoinedPunctuatedLength {
            exactSingle[entry.foldedJoined] = exactSingle[entry.foldedJoined] ?? entry
        }
        let compounds = Dictionary(
            singleWord.filter { $0.foldedJoined.count >= minimumCompoundLength }.map { ($0.foldedJoined, $0) },
            uniquingKeysWith: { first, _ in first })
        let fuzzyPool = singleWord.filter { $0.foldedJoined.count >= minimumFuzzyLength }

        var edits: [(Range<String.Index>, String)] = []
        var index = 0
        while index < tokens.count {
            if let (endIndex, replacement) = matchMultiWord(
                at: index, tokens: tokens, in: text, entries: multiWord, claimed: claimed) {
                let span = tokens[index].range.lowerBound..<tokens[endIndex].range.upperBound
                if text[span] != replacement { edits.append((span, replacement)) }
                index = endIndex + 1
                continue
            }
            if let replacement = matchSplitCompound(
                at: index, tokens: tokens, in: text, compounds: compounds, claimed: claimed) {
                let span = tokens[index].range.lowerBound..<tokens[index + 1].range.upperBound
                if text[span] != replacement { edits.append((span, replacement)) }
                index += 2
                continue
            }
            if let replacement = matchSingle(
                token: tokens[index], exactSingle: exactSingle, fuzzyPool: fuzzyPool,
                claimed: claimed, lexicon: lexicon) {
                edits.append((tokens[index].range, replacement))
            }
            index += 1
        }
        return edits
    }

    private static func matchSingle(
        token: Token, exactSingle: [String: Entry], fuzzyPool: [Entry],
        claimed: (String) -> Bool, lexicon: DictationLexicon
    ) -> String? {
        guard !token.precededByApostrophe else { return nil }
        guard !token.followedByApostrophe || token.followedByPossessiveS else { return nil }
        guard !claimed(token.text) else { return nil }
        if let entry = exactSingle[token.folded] {
            return token.text != entry.spelling ? entry.spelling : nil
        }
        if let plural = matchPlural(token: token, exactSingle: exactSingle, lexicon: lexicon) {
            return plural
        }
        return matchFuzzy(token: token, pool: fuzzyPool, lexicon: lexicon)?.spelling
    }

    private static func matchPlural(
        token: Token, exactSingle: [String: Entry], lexicon: DictationLexicon
    ) -> String? {
        guard token.folded.hasSuffix("s") else { return nil }
        let stem = String(token.folded.dropLast())
        guard stem.count >= minimumPluralStemLength,
              let entry = exactSingle[stem],
              !entry.foldedJoined.hasSuffix("s"),
              isUnknownToBothDictionaries(token.text.lowercased(), lexicon: lexicon) else { return nil }
        let pluralSpelling = entry.spelling + "s"
        return token.text != pluralSpelling ? pluralSpelling : nil
    }

    private static func prepareEntries(_ raw: [String]) -> [Entry] {
        var seen = Set<String>()
        var result: [Entry] = []
        for term in raw {
            let trimmed = term.precomposedStringWithCanonicalMapping
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { continue }
            let parts = splitAlphanumeric(trimmed).map(fold)
            let joined = parts.joined()
            guard joined.count >= 2 else { continue }
            // Keep only terms whose characters are letters, digits, marks, spaces, hyphens, dots or apostrophes.
            guard trimmed.unicodeScalars.allSatisfy({ scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || CharacterSet.nonBaseCharacters.contains(scalar)
                    || scalar == " " || scalar == "-" || scalar == "." || scalar == "'" || scalar == "\u{2019}"
            }) else { continue }
            guard seen.insert(fold(trimmed)).inserted else { continue }
            result.append(Entry(
                spelling: trimmed, parts: parts, foldedJoined: joined,
                hasInternalDot: trimmed.contains("."),
                hasInternalApostrophe: trimmed.contains("'") || trimmed.contains("\u{2019}"),
                isSpaceFree: !trimmed.contains(" "),
                camelSplitOffsets: parts.count == 1 ? camelSplitOffsets(for: trimmed) : []))
            if result.count >= maximumTerms { break }
        }
        return result
    }

    private static func camelSplitOffsets(for spelling: String) -> Set<Int> {
        var offsets = Set<Int>()
        var previous: Character?
        var foldedCount = 0
        for character in spelling {
            if let prev = previous, prev.isLowercase || prev.isNumber, character.isUppercase {
                offsets.insert(foldedCount)
            }
            foldedCount += fold(String(character)).count
            previous = character
        }
        return offsets
    }

    private static func matchMultiWord(
        at start: Int, tokens: [Token], in text: String, entries: [Entry], claimed: (String) -> Bool
    ) -> (Int, String)? {
        for entry in entries {
            let count = entry.parts.count
            guard start + count <= tokens.count else { continue }
            var matched = true
            for offset in 0..<count {
                if tokens[start + offset].folded != entry.parts[offset] {
                    matched = false
                    break
                }
                if offset > 0 {
                    let prevEnd = tokens[start + offset - 1].range.upperBound
                    let sep = text[prevEnd..<tokens[start + offset].range.lowerBound]
                    if !isAllowedPhraseSeparator(sep, entry: entry) {
                        matched = false
                        break
                    }
                }
            }
            guard matched else { continue }
            let span = tokens[start].range.lowerBound..<tokens[start + count - 1].range.upperBound
            guard !claimed(String(text[span])) else { continue }
            return (start + count - 1, entry.spelling)
        }
        return nil
    }

    private static func matchSplitCompound(
        at start: Int, tokens: [Token], in text: String,
        compounds: [String: Entry], claimed: (String) -> Bool
    ) -> String? {
        guard start + 1 < tokens.count else { return nil }
        let first = tokens[start]
        let second = tokens[start + 1]
        guard !first.precededByApostrophe, !first.followedByApostrophe,
              !second.precededByApostrophe, !second.followedByApostrophe,
              !first.precededByHyphen, !second.followedByHyphen else { return nil }
        let sep = text[first.range.upperBound..<second.range.lowerBound]
        guard sep == " " || sep == "-" else { return nil }
        let joined = first.folded + second.folded
        guard let entry = compounds[joined] else { return nil }
        // Space-separated pairs only join at an internal camelCase boundary (Fast|API, mac|OS)
        // so normal phrases like "María no" or "just in" never collapse into flat names.
        if sep == " ", !entry.camelSplitOffsets.contains(first.folded.count) { return nil }
        let span = first.range.lowerBound..<second.range.upperBound
        guard !claimed(String(text[span])) else { return nil }
        return entry.spelling
    }

    private static func matchFuzzy(token: Token, pool: [Entry], lexicon: DictationLexicon) -> Entry? {
        guard token.folded.count >= minimumFuzzyLength, !pool.isEmpty else { return nil }
        let candidates = pool.filter { entry in
            abs(entry.foldedJoined.count - token.folded.count) <= 1
                && token.folded != entry.foldedJoined + "s"
                && entry.foldedJoined != token.folded + "s"
                && initialsCompatible(token.folded, entry.foldedJoined)
                && damerauLevenshteinDistance(token.folded, entry.foldedJoined, limit: 1) == 1
        }
        // Only apply when a single unambiguous vocabulary term is at edit distance 1.
        guard candidates.count == 1, let winner = candidates.first else { return nil }
        guard isUnknownToBothDictionaries(token.text.lowercased(), lexicon: lexicon) else { return nil }
        return winner
    }

    /// Requires both English and Spanish dictionaries to be available and confirm the word is unknown.
    private static func isUnknownToBothDictionaries(_ word: String, lexicon: DictationLexicon) -> Bool {
        lexicon.contains(word, false) == false && lexicon.contains(word, true) == false
    }

    private static func isAllowedPhraseSeparator(_ separator: Substring, entry: Entry) -> Bool {
        if separator == " " || separator == "-" { return true }
        if entry.hasInternalDot, separator == "." { return true }
        if entry.hasInternalApostrophe, separator == "'" || separator == "\u{2019}" { return true }
        return false
    }

    private static func initialsCompatible(_ lhs: String, _ rhs: String) -> Bool {
        guard let a = lhs.first, let b = rhs.first else { return false }
        if a == b { return true }
        let groups: [Set<Character>] = [["c", "k", "q"], ["f", "p"], ["g", "j"], ["s", "z", "c"], ["b", "v"]]
        return groups.contains { $0.contains(a) && $0.contains(b) }
    }

    /// Optimal string alignment distance capped at `limit` (handles substitutions,
    /// insertions, deletions, and adjacent transpositions).
    static func damerauLevenshteinDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        for i in 1...a.count {
            var rowMin = limit + 1
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var best = min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    best = min(best, matrix[i - 2][j - 2] + 1)
                }
                matrix[i][j] = best
                if best < rowMin { rowMin = best }
            }
            if rowMin > limit { return limit + 1 }
        }
        return matrix[a.count][b.count]
    }

    private static func mapExcludedRanges(
        _ ranges: [Range<String.Index>], from rawText: String, to normalized: String
    ) -> [Range<String.Index>] {
        guard !ranges.isEmpty else { return [] }
        if rawText == normalized { return ranges }
        return ranges.compactMap { range in
            let prefixLen = rawText[..<range.lowerBound].precomposedStringWithCanonicalMapping.count
            let spanLen = rawText[range].precomposedStringWithCanonicalMapping.count
            guard let start = normalized.index(
                normalized.startIndex, offsetBy: prefixLen, limitedBy: normalized.endIndex),
                  let end = normalized.index(start, offsetBy: spanLen, limitedBy: normalized.endIndex)
            else { return nil }
            return start..<end
        }
    }

    private static func protectedRanges(
        in text: String, exemptDotTerms: Set<String>
    ) -> [Range<String.Index>] {
        guard let protectedExpression else { return [] }
        return protectedExpression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { match in
                guard let range = Range(match.range, in: text) else { return nil }
                if !exemptDotTerms.isEmpty, exemptDotTerms.contains(fold(String(text[range]))) {
                    return nil
                }
                return range
            }
    }

    private static func codeTokenRanges(in text: String) -> [Range<String.Index>] {
        guard let codeTokenExpression else { return [] }
        return codeTokenExpression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
    }

    private static func extractTokens(in text: String, excluding protected: [Range<String.Index>]) -> [Token] {
        guard let tokenExpression else { return [] }
        return tokenExpression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text),
                  !protected.contains(where: { $0.overlaps(range) }) else { return nil }
            return makeToken(range: range, in: text)
        }
    }

    private static func makeToken(range: Range<String.Index>, in text: String) -> Token {
        let word = String(text[range])
        let folded = fold(word)
        var precededByApostrophe = false
        var precededByHyphen = false
        if range.lowerBound > text.startIndex {
            let before = text.index(before: range.lowerBound)
            precededByHyphen = text[before] == "-"
            if apostrophes.contains(text[before]), before > text.startIndex {
                precededByApostrophe = text[text.index(before: before)].isLetter
            }
        }
        var followedByApostrophe = false
        var followedByPossessiveS = false
        var followedByHyphen = false
        if range.upperBound < text.endIndex {
            let afterChar = text[range.upperBound]
            followedByHyphen = afterChar == "-"
            if apostrophes.contains(afterChar) {
                let cliticStart = text.index(after: range.upperBound)
                if cliticStart < text.endIndex, text[cliticStart].isLetter {
                    followedByApostrophe = true
                    let afterClitic = text.index(after: cliticStart)
                    let isTrailingS = (text[cliticStart] == "s" || text[cliticStart] == "S")
                        && (afterClitic == text.endIndex || !(text[afterClitic].isLetter || text[afterClitic].isNumber))
                    followedByPossessiveS = isTrailingS && !contractionStems.contains(folded)
                }
            }
        }
        return Token(
            range: range, text: word, folded: folded,
            precededByApostrophe: precededByApostrophe,
            followedByApostrophe: followedByApostrophe,
            followedByPossessiveS: followedByPossessiveS,
            precededByHyphen: precededByHyphen,
            followedByHyphen: followedByHyphen)
    }

    private static func splitAlphanumeric(_ text: String) -> [String] {
        guard let tokenExpression else { return [] }
        return tokenExpression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
