import Foundation

/// Deterministic Clean v2 passes: explicit spoken punctuation commands and
/// unambiguous clause-discard self-corrections in English and Spanish.
/// Runs only in Clean/Polish mode and yields to any explicit user replacement trigger.
public enum DictationCleanCommands {
    // Escaped non-ASCII so the English-source guard never misreads Spanish phrases as prose.
    private static let selfCorrectionCues = [
        "scratch that",
        "borra eso",
        "olvida eso"
    ]

    private static let literalProseBeforeCue: Set<String> = [
        "don't", "dont", "not", "never", "cannot", "can't", "cant", "won't", "wont", "to",
        "no", "nunca", "jam\u{E1}s", "jamas"
    ]

    /// Articles and possessives that turn a punctuation name into prose ("a question mark").
    /// Clause-final pronouns/numerals ("that", "this", "one") are excluded.
    private static let punctuationDeterminers: Set<String> = [
        "a", "an", "the", "my", "your",
        "un", "el", "mi", "tu"
    ]

    private static let abbreviations: Set<String> = [
        "e.g.", "i.e.", "etc.", "vs.", "dr.", "dra.", "mr.", "mrs.", "ms.",
        "sr.", "sra.", "srta.", "st.", "no.", "p.ej.", "ej.", "approx.", "aprox."
    ]

    private static let terminalPunctuation: [(phrases: [String], symbol: String)] = [
        (["question mark", "signo de interrogaci\u{F3}n", "signo de interrogacion", "signo de pregunta"], "?"),
        (["exclamation mark", "exclamation point", "signo de exclamaci\u{F3}n", "signo de exclamacion"], "!"),
        (["semicolon", "punto y coma"], ";")
    ]

    private static let closeParenPhrases = [
        "close parenthesis", "cerrar par\u{E9}ntesis", "cerrar parentesis",
        "cierra par\u{E9}ntesis", "cierra parentesis"
    ]

    private static let openParenPhrases = [
        "open parenthesis", "abrir par\u{E9}ntesis", "abrir parentesis",
        "abre par\u{E9}ntesis", "abre parentesis"
    ]

    private static let sentenceEnders: Set<Character> = [".", "!", "?", "\u{2026}", "\n"]
    private static let openingQuotes: Set<Character> = ["\"", "\u{201C}", "'", "\u{2018}", "\u{AB}"]
    private static let prosodicDelimiters = ",;:.!?\u{2026}\u{2014}-"

    /// Removes clauses discarded by explicit cues ("scratch that", "borra eso", "olvida eso").
    public static func applyingSelfCorrections(
        to rawText: String,
        claimed: (String) -> Bool = { _ in false },
        excludedRanges: [Range<String.Index>] = []
    ) -> String {
        let activeCues = selfCorrectionCues.filter { !claimed($0) }
        guard !activeCues.isEmpty, !rawText.isEmpty else { return rawText }
        var text = rawText.precomposedStringWithCanonicalMapping
        var exclusions = mapRanges(excludedRanges, from: rawText, to: text)
        let alternatives = activeCues.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return rawText }

        var searchStart = text.startIndex
        var repeatedAfterCollapseAt: (index: String.Index, capital: Bool, inverter: Character?)?
        while searchStart < text.endIndex {
            let searchRange = NSRange(searchStart..<text.endIndex, in: text)
            guard let match = expression.firstMatch(in: text, range: searchRange),
                  let range = Range(match.range, in: text) else { break }
            if exclusions.contains(where: { $0.overlaps(range) })
                || isLiteralCueUse(range: range, in: text)
                || !isAtProsodicBoundary(range: range, in: text) {
                repeatedAfterCollapseAt = nil
                searchStart = range.upperBound
                continue
            }
            let clauseStart = startOfPrecedingClause(before: range.lowerBound, in: text)
            let precedingClause = text[clauseStart..<range.lowerBound]
            let isRepeatedCue = repeatedAfterCollapseAt?.index == range.lowerBound
            guard isRepeatedCue || precedingClause.contains(where: \.isLetter) else {
                repeatedAfterCollapseAt = nil
                searchStart = range.upperBound
                continue
            }
            let hadCapitalStart = isRepeatedCue
                ? (repeatedAfterCollapseAt?.capital == true)
                : (precedingClause.first(where: \.isLetter)?.isUppercase == true)
            let leadingInverter = isRepeatedCue
                ? repeatedAfterCollapseAt?.inverter
                : leadingSpanishInverter(in: precedingClause)
            var afterEnd = range.upperBound
            while afterEnd < text.endIndex, ",;:.!?\u{2026} \t".contains(text[afterEnd]) {
                afterEnd = text.index(after: afterEnd)
            }
            if afterEnd == text.endIndex {
                let trimStart = trimmingTrailingSpaces(before: clauseStart, in: text)
                text.replaceSubrange(trimStart..<afterEnd, with: "")
                break
            }
            let prefix = buildReplacementPrefix(
                afterEnd: &afterEnd, in: text, hadCapitalStart: hadCapitalStart, leadingInverter: leadingInverter)
            text.replaceSubrange(clauseStart..<afterEnd, with: prefix)
            // Re-scan from clauseStart so chained "scratch that, scratch that" fires cleanly.
            exclusions = []
            repeatedAfterCollapseAt = (clauseStart, hadCapitalStart, leadingInverter)
            searchStart = clauseStart
        }
        return text
    }

    /// Replaces unambiguous spoken punctuation commands in English and Spanish while
    /// preserving prose mentions preceded by articles/possessives ("a question mark").
    public static func applyingSpokenPunctuation(
        to rawText: String,
        claimed: (String) -> Bool = { _ in false },
        excludedRanges: [Range<String.Index>] = []
    ) -> String {
        guard !rawText.isEmpty else { return rawText }
        var text = rawText.precomposedStringWithCanonicalMapping
        var exclusions = mapRanges(excludedRanges, from: rawText, to: text)
        for (phrases, symbol) in terminalPunctuation {
            text = replacingPunctuation(
                phrases: phrases, symbol: symbol, kind: .terminal,
                in: text, claimed: claimed, exclusions: &exclusions)
        }
        text = replacingPunctuation(
            phrases: closeParenPhrases, symbol: ")", kind: .closeParen,
            in: text, claimed: claimed, exclusions: &exclusions)
        text = replacingPunctuation(
            phrases: openParenPhrases, symbol: "(", kind: .openParen,
            in: text, claimed: claimed, exclusions: &exclusions)
        return text
    }

    private enum PunctuationKind { case terminal, openParen, closeParen }

    private static func replacingPunctuation(
        phrases: [String], symbol: String, kind: PunctuationKind,
        in text: String, claimed: (String) -> Bool, exclusions: inout [Range<String.Index>]
    ) -> String {
        let active = phrases.filter { !claimed($0) }.sorted { $0.count > $1.count }
        guard !active.isEmpty else { return text }
        let alternatives = active.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return text }

        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }
        var output = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            if exclusions.contains(where: { $0.overlaps(range) }) { continue }
            if hasDeterminerBefore(range.lowerBound, in: output) { continue }
            let replacementRange = punctuationSpan(for: range, kind: kind, in: output)
            let oldLen = output.distance(from: replacementRange.lowerBound, to: replacementRange.upperBound)
            output.replaceSubrange(replacementRange, with: symbol)
            exclusions = shiftRanges(exclusions, after: replacementRange, delta: symbol.count - oldLen, in: output)
        }
        return output
    }

    private static func punctuationSpan(
        for range: Range<String.Index>, kind: PunctuationKind, in text: String
    ) -> Range<String.Index> {
        switch kind {
        case .openParen:
            var end = range.upperBound
            while end < text.endIndex, text[end] == " " || text[end] == "\t" {
                end = text.index(after: end)
            }
            if end < text.endIndex, text[end] == "," {
                end = text.index(after: end)
                while end < text.endIndex, text[end] == " " || text[end] == "\t" {
                    end = text.index(after: end)
                }
            }
            return range.lowerBound..<end
        case .closeParen:
            var start = range.lowerBound
            while start > text.startIndex {
                let prev = text.index(before: start)
                if " \t,;".contains(text[prev]) {
                    start = prev
                } else {
                    break
                }
            }
            return start..<range.upperBound
        case .terminal:
            var start = range.lowerBound
            while start > text.startIndex {
                let prev = text.index(before: start)
                if " \t,;".contains(text[prev]) {
                    start = prev
                } else if text[prev] == ".", !isNonSentencePeriod(at: prev, in: text) {
                    start = prev
                } else {
                    break
                }
            }
            var end = range.upperBound
            // Absorb a recognizer-inserted trailing punctuation mark right after the spoken mark.
            if end < text.endIndex, ".,?!;".contains(text[end]) {
                end = text.index(after: end)
            }
            return start..<end
        }
    }

    private static func isLiteralCueUse(range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex, openingQuotes.contains(text[text.index(before: range.lowerBound)]) {
            return true
        }
        guard let word = previousWord(before: range.lowerBound, in: text) else { return false }
        return literalProseBeforeCue.contains(word)
    }

    /// Requires the cue to sit at a prosodic boundary (preceded or followed by punctuation,
    /// or ending the utterance) so mid-clause verbs ("I will scratch that off") stay literal.
    private static func isAtProsodicBoundary(range: Range<String.Index>, in text: String) -> Bool {
        var before = range.lowerBound
        while before > text.startIndex {
            let prev = text.index(before: before)
            if text[prev] == " " || text[prev] == "\t" {
                before = prev
            } else {
                if prosodicDelimiters.contains(text[prev]) || text[prev] == "\n" { return true }
                break
            }
        }
        var after = range.upperBound
        while after < text.endIndex, text[after] == " " || text[after] == "\t" {
            after = text.index(after: after)
        }
        if after == text.endIndex { return true }
        return prosodicDelimiters.contains(text[after]) || text[after] == "\n"
    }

    private static func hasDeterminerBefore(_ index: String.Index, in text: String) -> Bool {
        guard let word = previousWord(before: index, in: text) else { return false }
        return punctuationDeterminers.contains(word)
    }

    private static func previousWord(before index: String.Index, in text: String) -> String? {
        var cursor = index
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            if text[prev] == " " || text[prev] == "\t" { cursor = prev } else { break }
        }
        let end = cursor
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            let char = text[prev]
            if char.isLetter || char.isNumber || char == "'" || char == "\u{2019}" {
                cursor = prev
            } else {
                break
            }
        }
        guard cursor < end else { return nil }
        return text[cursor..<end].lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    }

    private static func leadingSpanishInverter(in clause: Substring) -> Character? {
        guard let first = clause.first(where: { !$0.isWhitespace }) else { return nil }
        return (first == "\u{BF}" || first == "\u{A1}") ? first : nil
    }

    private static func buildReplacementPrefix(
        afterEnd: inout String.Index, in text: String,
        hadCapitalStart: Bool, leadingInverter: Character?
    ) -> String {
        var prefix = ""
        if let inverter = leadingInverter, text[afterEnd] != inverter {
            let tail = text[afterEnd...]
            let matchingCloser: Character = inverter == "\u{BF}" ? "?" : "!"
            if tail.contains(matchingCloser) {
                prefix.append(inverter)
            }
        }
        if hadCapitalStart, text[afterEnd].isLowercase {
            prefix.append(contentsOf: String(text[afterEnd]).uppercased())
            afterEnd = text.index(after: afterEnd)
        }
        return prefix
    }

    private static func trimmingTrailingSpaces(before index: String.Index, in text: String) -> String.Index {
        var cursor = index
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            if text[prev] == " " || text[prev] == "\t" { cursor = prev } else { break }
        }
        return cursor
    }

    /// Scans backward from a self-correction cue to the start of the preceding clause,
    /// skipping abbreviations (Dr., e.g., etc.) and version decimals (v1.2).
    static func startOfPrecedingClause(before cueStart: String.Index, in text: String) -> String.Index {
        var cursor = cueStart
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            if " \t,;:\u{2014}-".contains(text[prev]) { cursor = prev } else { break }
        }
        // Skip terminal punctuation immediately before the cue (". Scratch that" / "? Scratch that").
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            if ".!?\u{2026}".contains(text[prev]),
               !(text[prev] == "." && isNonSentencePeriod(at: prev, in: text)) {
                cursor = prev
            } else {
                break
            }
        }
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            if sentenceEnders.contains(text[prev]),
               !(text[prev] == "." && isNonSentencePeriod(at: prev, in: text)) {
                var afterBoundary = cursor
                while afterBoundary < cueStart, text[afterBoundary] == " " || text[afterBoundary] == "\t" {
                    afterBoundary = text.index(after: afterBoundary)
                }
                return afterBoundary
            }
            cursor = prev
        }
        return text.startIndex
    }

    /// True when `.` is inside a version/decimal (`v1.2`), domain (`a.com`),
    /// initial (`J.`), or known abbreviation (`Dr.`, `e.g.`, `etc.`).
    private static func isNonSentencePeriod(at dot: String.Index, in text: String) -> Bool {
        let after = text.index(after: dot)
        if after < text.endIndex, text[after].isLetter || text[after].isNumber {
            return true
        }
        var wordStart = dot
        while wordStart > text.startIndex {
            let prev = text.index(before: wordStart)
            let ch = text[prev]
            if ch.isLetter || ch.isNumber || ch == "." {
                wordStart = prev
            } else {
                break
            }
        }
        let token = text[wordStart...dot].lowercased()
        if abbreviations.contains(token) { return true }
        // Single-letter initial like "J."
        return token.count == 2 && token.first?.isLetter == true
    }

    private static func mapRanges(
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

    private static func shiftRanges(
        _ ranges: [Range<String.Index>], after edited: Range<String.Index>, delta: Int, in text: String
    ) -> [Range<String.Index>] {
        guard delta != 0, !ranges.isEmpty else { return ranges }
        return ranges.compactMap { range in
            if range.upperBound <= edited.lowerBound { return range }
            guard range.lowerBound >= edited.upperBound else { return nil }
            guard let start = text.index(range.lowerBound, offsetBy: delta, limitedBy: text.endIndex),
                  let end = text.index(range.upperBound, offsetBy: delta, limitedBy: text.endIndex)
            else { return nil }
            return start..<end
        }
    }
}
