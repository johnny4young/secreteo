import DictationKit
import Testing

@testable import DictationKit

struct DictationAdaptiveLearningTests {
    private static let testLexicon = DictationLexicon { word, spanish in
        if spanish {
            return ["secreto", "notas", "texto", "hola", "con", "el", "la", "de", "Cristina"].contains(word)
        }
        return ["secret", "marker", "notes", "hello", "with", "the", "and", "Cristina"].contains(word)
    }

    @Test
    func bilingualPhoneticTierFixesAccentedDistanceTwoMisspellingsSafely() {
        let vocab = [
            "Kubernetes", "Cognosos", "Secreteo", "FastAPI", "Antigravity",
            "GitHub", "Schemas", "Webpack", "Ubuntu", "Krystina", "Hashes"
        ]
        let input = "deploy cubernetis on kognosus using sekretio, fastapy, antigrabity, "
            + "guithub, skemas, uebpack, obuntu; Cristina vio hachís y el secreto del marker."
        let actual = DictationVocabularyNormalizer.applying(vocab, to: input, lexicon: Self.testLexicon)
        #expect(
            actual == "deploy Kubernetes on Cognosos using Secreteo, FastAPI, Antigravity, "
                + "GitHub, Schemas, Webpack, Ubuntu; Cristina vio hachís y el secreto del marker.")
        #expect(
            DictationVocabularyNormalizer.bilingualPhoneticKey("schema")
                == DictationVocabularyNormalizer.bilingualPhoneticKey("skema"))

        // Fails closed when either dictionary is missing.
        let englishOnly = DictationLexicon { _, spanish in spanish ? nil : false }
        #expect(DictationVocabularyNormalizer.applying(
            vocab, to: "deploy cubernetis", lexicon: englishOnly) == "deploy cubernetis")
    }

    @Test
    func editLearnerExtractsSingleAccentCorrectionFromManualPostPasteEdit() {
        let fastAPI = DictationEditLearner.extract(
            pasted: "Vamos a desplegar fase API y no JS en Kubernetes.",
            edited: "Vamos a desplegar FastAPI y no JS en Kubernetes.")
        #expect(fastAPI == DictationReplacement(trigger: "fase API", replacement: "FastAPI"))

        let nodeJS = DictationEditLearner.extract(
            pasted: "Vamos a desplegar FastAPI y no JS en Kubernetes.",
            edited: "Vamos a desplegar FastAPI y Node.js en Kubernetes.")
        #expect(nodeJS == DictationReplacement(trigger: "no JS", replacement: "Node.js"))

        let punctuated = DictationEditLearner.extract(
            pasted: "Vamos a desplegar fases. PI en Kubernetes.",
            edited: "Vamos a desplegar FastAPI en Kubernetes.")
        #expect(punctuated == DictationReplacement(trigger: "fases. PI", replacement: "FastAPI"))

        let shortPhrase = DictationEditLearner.extract(
            pasted: "sign off",
            edited: "Best regards")
        #expect(shortPhrase == DictationReplacement(trigger: "sign off", replacement: "Best regards"))

        // Balanced trailing delimiters in code expressions stay intact.
        let codeCall = DictationEditLearner.extract(
            pasted: "call print function here",
            edited: "call print() here")
        #expect(codeCall == DictationReplacement(trigger: "print function", replacement: "print()"))

        // Internal whitespace in heard trigger collapses to a single space.
        let spaced = DictationEditLearner.extract(
            pasted: "deploy fase   API now",
            edited: "deploy FastAPI now")
        #expect(spaced == DictationReplacement(trigger: "fase API", replacement: "FastAPI"))
    }

    @Test
    func editLearnerIgnoresInsertionsDeletionsNumbersFunctionWordsAndExistingRules() {
        // Pure insertion (user kept typing)
        #expect(DictationEditLearner.extract(
            pasted: "Vamos hoy", edited: "Vamos hoy temprano") == nil)
        // Trailing multi-word continuation at end of sentence
        #expect(DictationEditLearner.extract(
            pasted: "Vamos a comer hoy.", edited: "Vamos a comer en casa ahora.") == nil)
        // Pure deletion (user backspaced)
        #expect(DictationEditLearner.extract(
            pasted: "Vamos hoy temprano", edited: "Vamos hoy") == nil)
        // Only outer punctuation changed
        #expect(DictationEditLearner.extract(
            pasted: "Vamos hoy", edited: "Vamos hoy.") == nil)
        // Run-on sentence split capitalization
        #expect(DictationEditLearner.extract(
            pasted: "I'll send it now thanks", edited: "I'll send it now. Thanks") == nil)
        #expect(DictationEditLearner.extract(
            pasted: "Hola Juan buenos días", edited: "Hola Juan,\nBuenos días") == nil)
        // Sentence case at the start of the paste
        #expect(DictationEditLearner.extract(
            pasted: "hola mundo", edited: "Hola mundo") == nil)
        #expect(DictationEditLearner.extract(
            pasted: "Github is down", edited: "github is down") == nil)
        // Numeric fact change
        #expect(DictationEditLearner.extract(
            pasted: "Send 3 copies today", edited: "Send 4 copies today") == nil)
        // Single trivial function word swap (including accented Spanish)
        #expect(DictationEditLearner.extract(
            pasted: "Put it in the box", edited: "Put it on the box") == nil)
        #expect(DictationEditLearner.extract(
            pasted: "Dime sí puedes venir", edited: "Dime si puedes venir") == nil)
        // Too wide (> 3 changed words / two separate edits)
        #expect(DictationEditLearner.extract(
            pasted: "a b c d e f", edited: "a X c d Y f") == nil)
        // Already known rule
        let existing = [DictationReplacement(trigger: "fase API", replacement: "FastAPI")]
        #expect(DictationEditLearner.extract(
            pasted: "desplegar fase API hoy", edited: "desplegar FastAPI hoy", existing: existing) == nil)
    }
}
