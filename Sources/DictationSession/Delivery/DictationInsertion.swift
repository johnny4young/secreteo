import ApplicationServices
import Foundation
import DictationKit

/// Secreteo's own verified insertion: where it is, what it says, and the one way to edit it.
/// A spoken correction may change only this span, and only while it is unchanged.
@MainActor
struct DictationInsertion {
    static let lifetime: TimeInterval = 15 * 60

    let text: String
    let insertedAt: Date
    /// True while the same field still holds exactly this text where it was inserted.
    let isIntact: () -> Bool
    /// Replaces `range` (relative to the insertion) and confirms it; nil when the field refused.
    let edit: (_ range: NSRange, _ replacement: String) async -> DictationInsertion?
    /// Reads back ONLY the pinned span if the user edited strictly inside it; nil otherwise.
    var readEditedSpan: () -> String? = { nil }

    func isFresh(at now: Date) -> Bool { now.timeIntervalSince(insertedAt) < Self.lifetime }

    private static let anchorUTF16Length = 12
    private static let maximumLengthDelta = 48

    /// Edits through Accessibility's selected text, never the clipboard or synthesized keys.
    static func accessibility(
        element: AXUIElement, readback: DictationTextReadback,
        validate: @escaping () -> DictationDeliveryOutcome.Refusal?,
        range: NSRange, text: String, capturesEditAnchors: Bool = false, now: Date = Date()
    ) -> DictationInsertion {
        let holds = { (span: NSRange, expected: String) in
            readback.string(span).map { $0.utf16.elementsEqual(expected.utf16) } ?? false
        }
        let anchors = capturesEditAnchors
            ? SpanAnchors.capture(range: range, readback: readback, validate: validate)
            : nil
        return DictationInsertion(
            text: text, insertedAt: now,
            isIntact: { validate() == nil && holds(range, text) },
            edit: { subrange, replacement in
                guard validate() == nil, holds(range, text),
                      let edited = editedText(text, replacing: subrange, with: replacement) else { return nil }
                var selection = CFRange(location: range.location + subrange.location, length: subrange.length)
                guard let value = AXValueCreate(.cfRange, &selection),
                      AXUIElementSetAttributeValue(
                          element, kAXSelectedTextRangeAttribute as CFString, value) == .success,
                      AXUIElementSetAttributeValue(
                          element, kAXSelectedTextAttribute as CFString, replacement as CFString) == .success
                else { return nil }
                let span = NSRange(location: range.location, length: edited.utf16.count)
                // An editor may apply the change a moment later; never read past that window.
                for _ in 0..<20 {
                    if edited.isEmpty || holds(span, edited) {
                        return accessibility(
                            element: element, readback: readback, validate: validate,
                            range: span, text: edited, capturesEditAnchors: false)
                    }
                    do { try await Task.sleep(for: .milliseconds(25)) } catch { return nil }
                }
                return nil
            },
            readEditedSpan: {
                anchors?.readEditedSpan(
                    range: range, originalText: text, readback: readback, validate: validate, holds: holds)
            })
    }
}

extension DictationInsertion {
    /// Pinned character count and surrounding boundary slices captured only when edit learning
    /// is opted in, failing closed on any security-boundary breach or outside-span shift.
    struct SpanAnchors {
        let initialCount: Int
        let prefixLength: Int
        let prefix: String
        let suffixLength: Int
        let suffix: String

        @MainActor
        static func capture(
            range: NSRange, readback: DictationTextReadback,
            validate: () -> DictationDeliveryOutcome.Refusal?
        ) -> SpanAnchors? {
            guard validate() == nil, let baseline = readback.position(), baseline.isValid,
                  validate() == nil else { return nil }
            let initialCount = baseline.characterCount
            guard let (prefixLength, prefix) = capturePrefix(
                before: range.location, readback: readback, validate: validate),
                  let (suffixLength, suffix) = captureSuffix(
                    after: range.location + range.length, count: initialCount, readback: readback, validate: validate)
            else { return nil }
            return SpanAnchors(
                initialCount: initialCount, prefixLength: prefixLength, prefix: prefix,
                suffixLength: suffixLength, suffix: suffix)
        }

        @MainActor
        private static func capturePrefix(
            before location: Int, readback: DictationTextReadback,
            validate: () -> DictationDeliveryOutcome.Refusal?
        ) -> (Int, String)? {
            let length = min(DictationInsertion.anchorUTF16Length, location)
            guard length > 0 else { return (0, "") }
            guard let raw = validatedRead(
                NSRange(location: location - length, length: length), readback: readback, validate: validate)
            else { return nil }
            if hasLeadingSplitSurrogate(raw) {
                let adjusted = length - 1
                guard adjusted > 0 else { return (0, "") }
                guard let trimmed = validatedRead(
                    NSRange(location: location - adjusted, length: adjusted), readback: readback, validate: validate)
                else { return nil }
                return (adjusted, trimmed)
            }
            return (length, raw)
        }

        @MainActor
        private static func captureSuffix(
            after start: Int, count: Int, readback: DictationTextReadback,
            validate: () -> DictationDeliveryOutcome.Refusal?
        ) -> (Int, String)? {
            let length = min(DictationInsertion.anchorUTF16Length, max(0, count - start))
            guard length > 0 else { return (0, "") }
            guard let raw = validatedRead(
                NSRange(location: start, length: length), readback: readback, validate: validate)
            else { return nil }
            if hasTrailingSplitSurrogate(raw) {
                let adjusted = length - 1
                guard adjusted > 0 else { return (0, "") }
                guard let trimmed = validatedRead(
                    NSRange(location: start, length: adjusted), readback: readback, validate: validate)
                else { return nil }
                return (adjusted, trimmed)
            }
            return (length, raw)
        }

        @MainActor
        private static func validatedRead(
            _ span: NSRange, readback: DictationTextReadback,
            validate: () -> DictationDeliveryOutcome.Refusal?
        ) -> String? {
            guard validate() == nil, let text = readback.string(span), validate() == nil else { return nil }
            return text
        }

        private static func hasLeadingSplitSurrogate(_ text: String) -> Bool {
            if text.first == "\u{FFFD}" { return true }
            guard let firstUnit = text.utf16.first else { return false }
            return (0xDC00...0xDFFF).contains(firstUnit)
        }

        private static func hasTrailingSplitSurrogate(_ text: String) -> Bool {
            if text.last == "\u{FFFD}" { return true }
            guard let lastUnit = text.utf16.last else { return false }
            return (0xD800...0xDBFF).contains(lastUnit)
        }

        @MainActor
        func readEditedSpan(
            range: NSRange, originalText: String, readback: DictationTextReadback,
            validate: () -> DictationDeliveryOutcome.Refusal?, holds: (NSRange, String) -> Bool
        ) -> String? {
            guard validate() == nil, let current = readback.position(), current.isValid,
                  validate() == nil else { return nil }
            let delta = current.characterCount - initialCount
            guard abs(delta) <= DictationInsertion.maximumLengthDelta else { return nil }
            let editedLength = range.length + delta
            guard editedLength > 0, editedLength <= DictationTextReadback.maximumUTF16Length,
                  range.location <= current.characterCount - editedLength else { return nil }
            if prefixLength > 0 {
                let span = NSRange(location: range.location - prefixLength, length: prefixLength)
                guard validate() == nil, holds(span, prefix), validate() == nil else { return nil }
            }
            if suffixLength > 0 {
                // Uniform whitespace cannot verify that text was not inserted past the right boundary.
                if suffix.allSatisfy(\.isWhitespace), delta != 0 { return nil }
                let span = NSRange(location: range.location + editedLength, length: suffixLength)
                guard validate() == nil, holds(span, suffix), validate() == nil else { return nil }
            }
            guard let observed = Self.validatedRead(
                NSRange(location: range.location, length: editedLength), readback: readback, validate: validate),
                  observed != originalText else { return nil }
            if prefixLength > 0, prefix.allSatisfy(\.isWhitespace),
               observed.first?.isWhitespace == true, originalText.first?.isWhitespace == false {
                return nil
            }
            return observed
        }
    }

    /// Nil for a range outside `text`, checked before the field is touched.
    static func editedText(_ text: String, replacing range: NSRange, with replacement: String) -> String? {
        let length = text.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= length,
              range.length <= length - range.location else { return nil }
        return (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// Holds the destination's latest verified insertion between deliveries.
@MainActor
final class DictationInsertionRecord {
    var value: DictationInsertion?
}
