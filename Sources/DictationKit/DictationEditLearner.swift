import Foundation

/// Extracts a single learnable text-replacement candidate when the user manually
/// corrects one misheard word or short phrase right after Secreteo pasted it.
public enum DictationEditLearner {
    private static let maximumChangedWords = 3
    private static let maximumReplacementLength = 60

    private static let trivialFunctionWords: Set<String> = [
        "a", "an", "the", "to", "in", "on", "of", "at", "by", "is", "it", "or", "and", "for",
        "as", "be", "we", "he", "me", "my", "no", "so", "up", "if",
        "el", "la", "de", "en", "un", "una", "es", "si", "y", "o", "lo", "le", "se", "te", "su",
        "al", "tu", "mi", "del", "con", "por", "que", "los", "las", "nos"
    ]

    private struct SpanToken {
        let range: Range<String.Index>
        let raw: String
        let trimmed: String
    }

    /// Returns a replacement rule when `edited` differs from `pasted` by exactly one
    /// short substitution (1–3 words) and is not already known or trivial; nil otherwise.
    public static func extract(
        pasted: String,
        edited: String,
        existing: [DictationReplacement] = []
    ) -> DictationReplacement? {
        let pastedNFC = pasted.precomposedStringWithCanonicalMapping
        let editedNFC = edited.precomposedStringWithCanonicalMapping
        guard !pastedNFC.isEmpty, !editedNFC.isEmpty, pastedNFC != editedNFC else { return nil }

        let oldTokens = tokenize(pastedNFC)
        let newTokens = tokenize(editedNFC)
        guard !oldTokens.isEmpty, !newTokens.isEmpty else { return nil }

        var prefix = 0
        let minCount = min(oldTokens.count, newTokens.count)
        while prefix < minCount, oldTokens[prefix].trimmed == newTokens[prefix].trimmed {
            prefix += 1
        }
        var suffix = 0
        while suffix < minCount - prefix,
              oldTokens[oldTokens.count - 1 - suffix].trimmed == newTokens[newTokens.count - 1 - suffix].trimmed {
            suffix += 1
        }

        let oldEnd = oldTokens.count - suffix
        let newEnd = newTokens.count - suffix
        guard prefix < oldEnd, prefix < newEnd else { return nil }

        let oldCount = oldEnd - prefix
        let newCount = newEnd - prefix
        guard oldCount <= maximumChangedWords, newCount <= maximumChangedWords else { return nil }
        // Longer sentences need at least one unchanged anchor word so unrelated text is never paired.
        if oldTokens.count > 4, prefix + suffix == 0 { return nil }
        // Reject trailing multi-word expansions at the end of a pasted sentence (user kept typing).
        if suffix == 0, newCount > oldCount, oldTokens.count >= 2 { return nil }

        let heardRange = oldTokens[prefix].range.lowerBound..<oldTokens[oldEnd - 1].range.upperBound
        let replacementRange = newTokens[prefix].range.lowerBound..<newTokens[newEnd - 1].range.upperBound
        let heard = collapseWhitespace(outerTrimmed(String(pastedNFC[heardRange])))
        let replacement = outerTrimmed(String(editedNFC[replacementRange]))
        guard !heard.isEmpty, !replacement.isEmpty,
              heard != replacement,
              replacement.count <= maximumReplacementLength,
              !isPurelyNumeric(heard), !isPurelyNumeric(replacement) else { return nil }

        if isSentenceSplitRecapitalization(
            heard: heard, replacement: replacement, prefix: prefix,
            oldTokens: oldTokens, newTokens: newTokens, edited: editedNFC) {
            return nil
        }

        let foldedHeard = heard.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if oldCount == 1, trivialFunctionWords.contains(foldedHeard) { return nil }
        guard DictationTextRules.learning(heard, as: replacement, into: existing) != nil else { return nil }
        return DictationReplacement(trigger: heard, replacement: replacement)
    }

    private static func isSentenceSplitRecapitalization(
        heard: String, replacement: String, prefix: Int,
        oldTokens: [SpanToken], newTokens: [SpanToken], edited: String
    ) -> Bool {
        guard heard.caseInsensitiveCompare(replacement) == .orderedSame else { return false }
        // The text before the paste is unknown, so a first-letter flip there is sentence case, not spelling.
        guard prefix > 0 else { return heard.dropFirst() == replacement.dropFirst() }
        let oldPrev = oldTokens[prefix - 1].raw
        let newPrev = newTokens[prefix - 1].raw
        let gap = edited[newTokens[prefix - 1].range.upperBound..<newTokens[prefix].range.lowerBound]
        if gap.contains(where: \.isNewline) { return true }
        let sentenceBreakers: Set<Character> = [".", "!", "?", ":", ";", ","]
        let oldEnded = oldPrev.last.map { sentenceBreakers.contains($0) } ?? false
        let newEnded = newPrev.last.map { sentenceBreakers.contains($0) } ?? false
        return !oldEnded && newEnded
    }

    private static func collapseWhitespace(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func tokenize(_ text: String) -> [SpanToken] {
        var result: [SpanToken] = []
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }
            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }
            let raw = String(text[start..<index])
            let trimmed = outerTrimmed(raw)
            if !trimmed.isEmpty {
                result.append(SpanToken(range: start..<index, raw: raw, trimmed: trimmed))
            }
        }
        return result
    }

    private static let leadingTrimChars: Set<Character> = [
        ",", ";", ":", "!", "?", "\"", "\u{201C}", "\u{2018}", "'", "(", "[", "{", "\u{BF}", "\u{A1}", "\u{AB}"
    ]
    private static let trailingTrimChars: Set<Character> = [
        ",", ";", ":", "!", "?", ".", "\"", "\u{201D}", "\u{2019}", "'", ")", "]", "}", "\u{BB}", "\u{2026}"
    ]
    private static let matchingOpeners: [Character: Character] = [
        ")": "(", "]": "[", "}": "{", "\u{201D}": "\u{201C}", "\u{2019}": "\u{2018}", "\u{BB}": "\u{AB}"
    ]

    /// Strips outer sentence punctuation while keeping internal punctuation (Node.js, O'Brien, print()).
    private static func outerTrimmed(_ value: String) -> String {
        var sub = Substring(value.trimmingCharacters(in: .whitespacesAndNewlines))
        while let first = sub.first, leadingTrimChars.contains(first) {
            sub = sub.dropFirst()
        }
        while let last = sub.last, trailingTrimChars.contains(last) {
            let body = sub.dropLast()
            if let opener = matchingOpeners[last], body.contains(opener) { break }
            if body.contains(last), last == "\"" || last == "'" { break }
            sub = body
        }
        return String(sub).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPurelyNumeric(_ value: String) -> Bool {
        let nonSpace = value.filter { !$0.isWhitespace }
        return !nonSpace.isEmpty && nonSpace.allSatisfy { $0.isNumber || ".,:/+-".contains($0) }
    }
}
