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

struct PolishDictationRecipeTests {
    private struct Echo: DictationTextPolishing {
        let reply: @Sendable (String, String?) -> String
        func polish(_ text: String, recipe: String?) async throws -> String { reply(text, recipe) }
    }

    @Test
    func theRecipeReachesTheEngineAndUnlocksStructure() async {
        let polish = PolishDictation(polisher: Echo { _, recipe in
            recipe == "bullets" ? "- Ship the fix.\n- Then write the release notes for everyone." : "unused"
        })
        #expect(await polish("ship the fix then notes", recipe: "bullets")
            == .polished("- Ship the fix.\n- Then write the release notes for everyone."))
        let conservative = PolishDictation(polisher: Echo { _, _ in
            "- Ship the fix.\n- Then write the release notes for everyone."
        })
        #expect(await conservative("ship the fix then notes") == .kept(.changedMeaning(.length)))
    }
}
