import Foundation
import NaturalLanguage

/// Deterministic guard for a generative dictation rewrite: the polished text may fix
/// form, never facts. Any doubt keeps the clean text, so the checks favor refusal.
public enum DictationPolishFidelity {
    public enum Violation: Equatable, Sendable {
        case numbers
        case identifiers
        case protectedTerm
        case negation
        case length
        case language
        case preamble
        case empty
    }

    static let minimumLengthRatio = 0.6
    static let maximumLengthRatio = 1.4
    private static let languageCheckMinimumLetters = 40
    private static let languageConfidence = 0.8

    private static let negations: Set<String> = [
        "no", "not", "never", "none", "nobody", "nothing", "neither", "nor", "without", "cannot",
        "nunca", "jam\u{E1}s", "nada", "nadie", "ninguno", "ninguna", "ning\u{FA}n", "tampoco", "ni", "sin"
    ]
    private static let preambles = [
        "here is", "here's", "sure", "certainly", "rewritten", "polished", "corrected",
        "aqu\u{ED} est\u{E1}", "aqu\u{ED} tienes", "claro", "por supuesto", "texto corregido", "texto pulido"
    ]
    /// Clause-delimited self-correction cues with non-empty follow-up text, so prose
    /// ("actually no budget", "espera no pagar", "Actually no.") never matches.
    private static let selfCorrectionCuePattern =
        #"(?:^|[,;:.!?\x{2026}\x{2014}-][ \t]+)"#
        + #"(actually\s+no|wait\s+no|no\s+wait|sorry\s+no|scratch\s+that|i\s+mean"#
        + #"|mejor\s+dicho|espera\s+no|perd[\x{F3}o]n\s+no|borra\s+eso|olvida\s+eso)"#
        + #"(?=[,;:\x{2014}.][ \t]+\S)"#
    private static let noTermStopwords: Set<String> = [
        "es", "is", "us", "as", "te", "me", "se", "le", "de", "la",
        "el", "lo", "va", "he", "we", "be", "to", "do", "in", "on"
    ]

    /// Returns the first rule the candidate breaks, or nil when it is safe to paste.
    /// `protectedTerms` are the user's own spellings (dictionary replacements and vocabulary).
    /// A recipe may restructure: its length is free and list markers are not numbers.
    public static func violation(
        original: String, candidate: String, protectedTerms: [String] = [], allowsRestructuring: Bool = false
    ) -> Violation? {
        var candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return .empty }
        if allowsRestructuring { candidate = strippingListMarkers(candidate) }
        if !numbersMatch(original: original, candidate: candidate) { return .numbers }
        if identifiers(in: original) != identifiers(in: candidate) { return .identifiers }
        let proseOriginal = strippingIdentifiers(from: original)
        let proseCandidate = strippingIdentifiers(from: candidate)
        for term in protectedTerms where containsWord(term, in: proseOriginal, caseSensitive: true) {
            if !containsWord(term, in: proseCandidate, caseSensitive: true) { return .protectedTerm }
        }
        if !negationsMatch(
            proseOriginal: proseOriginal, proseCandidate: proseCandidate, protectedTerms: protectedTerms) {
            return .negation
        }
        if !allowsRestructuring, !lengthMatches(original: original, candidate: candidate) { return .length }
        if startsWithPreamble(candidate) && !startsWithPreamble(original) { return .preamble }
        if let before = dominantLanguage(of: original), let after = dominantLanguage(of: candidate),
           before != after {
            return .language
        }
        return nil
    }

    private static func numbersMatch(original: String, candidate: String) -> Bool {
        let before = numbers(in: original)
        let after = numbers(in: candidate)
        if before == after { return true }
        // When the speaker explicitly self-corrected ("at 3, actually no, at 4"),
        // Polish may drop superseded numbers inside the discarded clause right before the cue,
        // never numbers in earlier sentences or after the cue, and never invent new ones.
        let normalized = original.precomposedStringWithCanonicalMapping
        guard let cue = lastSelfCorrectionCueRange(in: normalized) else { return false }
        let discardedStart = DictationCleanCommands.startOfPrecedingClause(before: cue.lowerBound, in: normalized)
        let requiredBefore = numbers(in: String(normalized[..<discardedStart]))
        let requiredAfter = numbers(in: String(normalized[cue.upperBound...]))
        guard !requiredAfter.isEmpty else { return false }
        return multisetContains(after, sub: requiredBefore + requiredAfter)
            && multisetContains(before, sub: after)
    }

    private static func negationsMatch(
        proseOriginal: String, proseCandidate: String, protectedTerms: [String]
    ) -> Bool {
        let originalMarkers = negationMarkers(in: proseOriginal)
        let candidateMarkers = negationMarkers(in: proseCandidate)
        if originalMarkers == candidateMarkers { return true }
        let strippedOriginal = strippingSafeNegationArtifacts(
            from: proseOriginal, candidate: proseCandidate, protectedTerms: protectedTerms)
        let requiredMarkers = negationMarkers(in: strippedOriginal)
        // Candidate must keep every required negation and never invent a negation absent from original.
        return requiredMarkers.isSubset(of: candidateMarkers) && candidateMarkers.isSubset(of: originalMarkers)
    }

    private static func lengthMatches(original: String, candidate: String) -> Bool {
        let candidateCount = Double(words(in: candidate).count)
        let originalCount = Double(max(words(in: original).count, 1))
        let baseRatio = candidateCount / originalCount
        if baseRatio >= minimumLengthRatio && baseRatio <= maximumLengthRatio { return true }
        let normalized = original.precomposedStringWithCanonicalMapping
        guard let cue = lastSelfCorrectionCueRange(in: normalized) else { return false }
        let discardedStart = DictationCleanCommands.startOfPrecedingClause(before: cue.lowerBound, in: normalized)
        let surviving = String(normalized[..<discardedStart]) + " " + String(normalized[cue.upperBound...])
        let survivingCount = Double(max(words(in: surviving).count, 1))
        let lowerBound = min(originalCount, survivingCount) * minimumLengthRatio
        let upperBound = max(originalCount, survivingCount) * maximumLengthRatio
        return candidateCount >= lowerBound && candidateCount <= upperBound
    }

    private static func multisetContains(_ superset: [String], sub: [String]) -> Bool {
        var counts: [String: Int] = [:]
        for item in superset { counts[item, default: 0] += 1 }
        for item in sub {
            guard let remaining = counts[item], remaining > 0 else { return false }
            counts[item] = remaining - 1
        }
        return true
    }

    private static func lastSelfCorrectionCueRange(in normalized: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: selfCorrectionCuePattern, options: [.caseInsensitive])
        else { return nil }
        guard let last = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).last
        else { return nil }
        return Range(last.range(at: 1), in: normalized)
    }

    /// Removes negation words that belong strictly to a clause-delimited self-correction cue
    /// or to a phonetic "no <frag>" mishearing resolved into a newly introduced `No*` vocabulary term.
    private static func strippingSafeNegationArtifacts(
        from original: String, candidate: String, protectedTerms: [String]
    ) -> String {
        var cleaned = original.precomposedStringWithCanonicalMapping
        if let regex = try? NSRegularExpression(pattern: selfCorrectionCuePattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                if let cueRange = Range(match.range(at: 1), in: cleaned) {
                    cleaned.replaceSubrange(cueRange, with: " ")
                }
            }
        }
        var termBudgets: [(term: String, remaining: Int)] = []
        for term in protectedTerms {
            let folded = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard folded.hasPrefix("no"), folded.count >= 4,
                  !containsWord(term, in: original, caseSensitive: false) else { continue }
            let introducedCount = wordMatchCount(term, in: candidate, caseSensitive: true)
            if introducedCount > 0 { termBudgets.append((term, introducedCount)) }
        }
        guard !termBudgets.isEmpty,
              let regex = try? NSRegularExpression(
                pattern: #"(?<![\p{L}\p{N}])no[.,]?\s+([\p{L}\p{N}]+)(?![\p{L}\p{N}])"#,
                options: [.caseInsensitive]) else { return cleaned }
        let matches = regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
        for match in matches.reversed() {
            guard let full = Range(match.range, in: cleaned),
                  let second = Range(match.range(at: 1), in: cleaned) else { continue }
            let fragment = cleaned[second].lowercased()
            if let index = termBudgets.firstIndex(where: {
                $0.remaining > 0 && matchesNoTermTail(fragment: fragment, term: $0.term)
            }) {
                termBudgets[index].remaining -= 1
                cleaned.replaceSubrange(full, with: " ")
            }
        }
        return cleaned
    }

    private static func matchesNoTermTail(fragment: String, term: String) -> Bool {
        guard !noTermStopwords.contains(fragment) else { return false }
        let folded = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let parts = folded.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        if parts.count >= 2, let tail = parts.last, tail.count >= 2 {
            if fragment == tail || isShortPhoneticTailMatch(fragment: fragment, tail: tail) {
                return true
            }
            if tail.count >= 4,
               DictationVocabularyNormalizer.damerauLevenshteinDistance(fragment, tail, limit: 1) <= 1 {
                return true
            }
        }
        let remainder = String(folded.dropFirst(2))
        guard remainder.count >= 2 else { return false }
        if fragment == remainder { return true }
        return remainder.count >= 4
            && DictationVocabularyNormalizer.damerauLevenshteinDistance(fragment, remainder, limit: 1) <= 1
    }

    /// Allows Spanish/English phonetic j/g swap on short tails (e.g. "gs" for "js" in Node.js)
    /// without opening distance-1 matching to unrelated 2-letter words like "es" or "te".
    private static func isShortPhoneticTailMatch(fragment: String, tail: String) -> Bool {
        guard fragment.count == tail.count, fragment.count >= 2,
              let fFirst = fragment.first, let tFirst = tail.first,
              fragment.dropFirst() == tail.dropFirst() else { return false }
        return (fFirst == "g" && tFirst == "j") || (fFirst == "j" && tFirst == "g")
    }

    /// Digit runs with their grouping removed, so "1,000" and "1000" compare equal.
    static func numbers(in text: String) -> [String] {
        matches(of: #"\d(?:[\d.,:/]*\d)?"#, in: text)
            .map { $0.filter(\.isNumber) }
            .sorted()
    }

    /// URLs, emails, @mentions and #tags must survive byte for byte.
    static func identifiers(in text: String) -> [String] {
        matches(of: identifierPattern, in: text).sorted()
    }

    private static let identifierPattern = #"(?:https?://|www\.)[^\s]+[^\s.,;:!?)\]]"#
        + #"|[\w.+-]+@[\w-]+(?:\.[\w-]+)+"#
        + #"|(?<![\w@])[@#][\p{L}\p{N}_]+"#

    private static let pathPattern = #"(?:~|\.\.?|[\p{L}\p{N}_-]+)?(?:/[\p{L}\p{N}_.-]+){2,}"#
        + #"|(?:~|\.\.?)/[\p{L}\p{N}_.-]+"#
        + #"|/[\p{L}\p{N}_.-]+"#

    /// Masks identifiers and file paths before checking protected spellings so
    /// a lowercase token inside a URL or path never conflicts with exact-case terms.
    private static func strippingIdentifiers(from text: String) -> String {
        let pattern = identifierPattern + "|" + pathPattern
        return text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }

    /// "1. ", "2) " or "- " at a line start: list structure a recipe may add.
    static func strippingListMarkers(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?m)^[ \t]*(?:\d{1,2}[.)]|[-*\x{2022}])[ \t]+"#, with: "", options: .regularExpression)
    }

    static func negationMarkers(in text: String) -> Set<String> {
        var markers = Set<String>()
        for word in words(in: text) {
            if word.hasSuffix("n't") || word == "cannot" {
                markers.insert("not")
            } else if negations.contains(word) {
                markers.insert(word)
            }
        }
        return markers
    }

    public static func words(in text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map(String.init)
    }

    private static func containsWord(_ term: String, in text: String, caseSensitive: Bool) -> Bool {
        wordMatchCount(term, in: text, caseSensitive: caseSensitive) > 0
    }

    private static func wordMatchCount(_ term: String, in text: String, caseSensitive: Bool) -> Int {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: trimmed) + "(?![\\p{L}\\p{N}])"
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func startsWithPreamble(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return preambles.contains { lowered.hasPrefix($0) }
    }

    /// Only a long, clearly single-language text has a language to keep; code-switched
    /// dictation stays below the confidence bar and is never refused for it.
    private static func dominantLanguage(of text: String) -> NLLanguage? {
        guard text.filter(\.isLetter).count >= languageCheckMinimumLetters else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= languageConfidence else { return nil }
        return language
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
}
