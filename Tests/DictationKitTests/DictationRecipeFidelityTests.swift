import DictationKit
import Testing

struct DictationRecipeFidelityTests {
    @Test
    func aRecipeMayRestructureButNeverChangeFacts() {
        let original = "ship the 3 fixes on friday and email ana@example.com, don't forget the tests"
        let bullets = "- Ship the 3 fixes on Friday.\n- Email ana@example.com.\n- Don't forget the tests."
        #expect(DictationPolishFidelity.violation(
            original: original, candidate: bullets, allowsRestructuring: true) == nil)
        let numbered = "1. Ship the 3 fixes on Friday.\n2. Email ana@example.com.\n3. Don't forget the tests."
        #expect(DictationPolishFidelity.violation(
            original: original, candidate: numbered, allowsRestructuring: true) == nil)
        let changed = "- Ship the 4 fixes on Friday.\n- Email ana@example.com.\n- Don't forget the tests."
        #expect(DictationPolishFidelity.violation(
            original: original, candidate: changed, allowsRestructuring: true) == .numbers)
        let lostNegation = "- Ship the 3 fixes on Friday.\n- Email ana@example.com.\n- Forget the tests."
        #expect(DictationPolishFidelity.violation(
            original: original, candidate: lostNegation, allowsRestructuring: true) == .negation)
    }
}
