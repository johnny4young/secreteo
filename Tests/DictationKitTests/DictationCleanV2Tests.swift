import DictationKit
import Foundation
import Testing

@testable import DictationKit

struct DictationCleanV2Tests {
    @Test
    func spokenPunctuationFormatsEnglishAndSpanishWhileProtectingMetaProse() {
        let cases: [(String, String)] = [
            ("are you ready question mark", "are you ready?"),
            ("what is that question mark", "what is that?"),
            ("can we ship this question mark", "can we ship this?"),
            ("are you ready question mark?", "are you ready?"),
            ("ship it now exclamation mark", "ship it now!"),
            ("what a win, exclamation point.", "what a win!"),
            ("first part semicolon second part", "first part; second part"),
            ("use open parenthesis fast mode close parenthesis today", "use (fast mode) today"),
            ("use open parenthesis, fast mode close parenthesis", "use (fast mode)"),
            ("step one open parenthesis optional close parenthesis", "step one (optional)"),
            ("see open parenthesis apples, etc. close parenthesis. Next.", "see (apples, etc.). Next."),
            ("see open parenthesis section 2 close parenthesis, and more", "see (section 2), and more"),
            ("vamos hoy signo de interrogación", "vamos hoy?"),
            ("es esta signo de interrogación", "es esta?"),
            ("listo signo de exclamación.", "listo!"),
            ("primero punto y coma segundo", "primero; segundo"),
            ("ver abrir paréntesis detalle cerrar paréntesis aquí", "ver (detalle) aquí"),
            // Article/possessive-framed prose mentions stay literal.
            ("add a question mark at the end", "add a question mark at the end"),
            ("falta el signo de interrogación", "falta el signo de interrogación"),
            ("forget the semicolon here", "forget the semicolon here")
        ]
        for (input, expected) in cases {
            let actual = DictationTextRules.apply(
                input, replacements: [], removeFillers: false, spokenCommands: true)
            #expect(actual == expected, "input: \(input)")
        }
        // Literal mode (spokenCommands: false) leaves spoken punctuation untouched.
        #expect(DictationTextRules.apply(
            "are you ready question mark", replacements: [], removeFillers: false, spokenCommands: false)
            == "are you ready question mark")
    }

    @Test
    func spokenPunctuationAndSelfCorrectionsYieldToMultiWordAndNFDTriggers() {
        let rules = [
            DictationReplacement(trigger: "big question mark", replacement: "???"),
            DictationReplacement(trigger: "scratch that idea", replacement: "DROP"),
            DictationReplacement(trigger: "signo de interrogacio\u{0301}n", replacement: "INTERROG")
        ]
        #expect(DictationTextRules.apply(
            "put big question mark and scratch that idea and signo de interrogación",
            replacements: rules, removeFillers: false, spokenCommands: true)
            == "put ??? and DROP and INTERROG")
    }

    @Test
    func safeSelfCorrectionsDropDiscardedClausesAndProtectProseAndAbbreviations() {
        let cases: [(String, String)] = [
            ("Let's ship Monday. Send it today, scratch that, hold it until Tuesday.",
             "Let's ship Monday. Hold it until Tuesday."),
            ("Let's ship Monday. Send it today. Scratch that, hold it until Tuesday.",
             "Let's ship Monday. Hold it until Tuesday."),
            ("Are we meeting Monday? Scratch that, Tuesday.", "Tuesday."),
            ("Let's ship Monday. Send it today, scratch that.", "Let's ship Monday."),
            ("Send it today scratch that", ""),
            ("Scratch that.", "Scratch that."),
            ("Monday, scratch that, Tuesday, scratch that, Wednesday", "Wednesday"),
            ("Send it, scratch that, scratch that, hold it", "Hold it"),
            ("Deploy v1.2 today, scratch that, deploy v1.3 tomorrow.", "Deploy v1.3 tomorrow."),
            ("Call Dr. Smith today, scratch that, call Jones.", "Call Jones."),
            ("Update to v1.2. Scratch that, keep v1.1.", "Keep v1.1."),
            ("First line, new line, wrong line, scratch that, right line", "First line\nright line"),
            ("Are you ready question mark send it now, scratch that, wait", "Are you ready? wait"),
            ("Enviamos el lunes, borra eso, mejor el martes.", "Mejor el martes."),
            ("¿Vamos el lunes, borra eso, vamos el martes?", "¿Vamos el martes?"),
            ("Primero revisa. Llama hoy, olvida eso, escribe mañana.", "Primero revisa. Escribe mañana."),
            // Mid-clause transitive verbs and literal prose stay untouched.
            ("I will scratch that off the list", "I will scratch that off the list"),
            ("Did you scratch that car?", "Did you scratch that car?"),
            ("Él borra eso del disco", "Él borra eso del disco"),
            ("Ella siempre olvida eso cuando sale", "Ella siempre olvida eso cuando sale"),
            ("Please don't scratch that finish", "Please don't scratch that finish"),
            ("He literally said \"scratch that\" in the meeting", "He literally said \"scratch that\" in the meeting")
        ]
        for (input, expected) in cases {
            let actual = DictationTextRules.apply(
                input, replacements: [], removeFillers: false, spokenCommands: true)
            #expect(actual == expected, "input: \(input)")
        }
    }

    @Test
    func polishFidelityAllowsClauseDelimitedSelfCorrectionsAndBlocksNegationInversions() {
        // Explicit clause-delimited self-corrections pass (including long discarded clauses).
        #expect(DictationPolishFidelity.violation(
            original: "let's meet at 3, actually no, at 4 tomorrow",
            candidate: "Let's meet at 4 tomorrow.") == nil)
        #expect(DictationPolishFidelity.violation(
            original: "envía 2 copias, espera no, 5 copias hoy",
            candidate: "Envía 5 copias hoy.") == nil)
        #expect(DictationPolishFidelity.violation(
            original: "Tell Sarah we are shipping the new build this afternoon, wait no, Tell Sarah to hold off",
            candidate: "Tell Sarah to hold off.") == nil)
        // Conservative Polish keeping the cue must NOT fail .negation or .length.
        #expect(DictationPolishFidelity.violation(
            original: "actually no, we need more time",
            candidate: "Actually, no, we need more time.") == nil)
        #expect(DictationPolishFidelity.violation(
            original: "I mean yes",
            candidate: "I mean, yes.") == nil)

        // Real negation inversions MUST still fail .negation.
        #expect(DictationPolishFidelity.violation(
            original: "There is actually no budget for this project",
            candidate: "There is budget for this project.") == .negation)
        #expect(DictationPolishFidelity.violation(
            original: "El cliente espera no pagar cargos adicionales",
            candidate: "El cliente espera pagar cargos adicionales.") == .negation)
        #expect(DictationPolishFidelity.violation(
            original: "Can we merge this today? Actually no.",
            candidate: "Can we merge this today? Yes.") == .negation)

        // Unrelated numbers in earlier sentences MUST NOT be dropped during a self-correction.
        #expect(DictationPolishFidelity.violation(
            original: "Order 50 laptops and 12 monitors. Meet at 3, actually no, at 4.",
            candidate: "Order laptops and monitors. Meet at 4.") == .numbers)
        #expect(DictationPolishFidelity.violation(
            original: "Order 50 laptops and 12 monitors. Meet at 3, actually no, at 4.",
            candidate: "Order 50 laptops and 12 monitors. Meet at 4.") == nil)
        #expect(DictationPolishFidelity.violation(
            original: "let's meet at 3, actually no, at 4 tomorrow",
            candidate: "Let's meet at 9 tomorrow.") == .numbers)
        #expect(DictationPolishFidelity.violation(
            original: "don't meet at 3, actually no, don't meet at 4",
            candidate: "Meet at 4.") == .negation)
    }

    @Test
    func polishFidelityAllowsNoPrefixVocabularyFixesWithoutOpeningStopwordLoopholes() {
        #expect(DictationPolishFidelity.violation(
            original: "vamos a desplegar con no JS en Kubernetes hoy",
            candidate: "Vamos a desplegar con Node.js en Kubernetes hoy.",
            protectedTerms: ["Node.js", "Kubernetes"]) == nil)
        #expect(DictationPolishFidelity.violation(
            original: "vamos a desplegar con no. GS en Kubernetes hoy",
            candidate: "Vamos a desplegar con Node.js en Kubernetes hoy.",
            protectedTerms: ["Node.js", "Kubernetes"]) == nil)

        // Common Spanish/English stopwords after "no" ("no es", "no te") MUST still fail .negation.
        #expect(DictationPolishFidelity.violation(
            original: "Esto no es compatible con node js hoy",
            candidate: "Esto es compatible con Node.js hoy.",
            protectedTerms: ["Node.js"]) == .negation)
        #expect(DictationPolishFidelity.violation(
            original: "Esto no te sirve con node hoy",
            candidate: "Esto te sirve con Node hoy.",
            protectedTerms: ["Node"]) == .negation)
        #expect(DictationPolishFidelity.violation(
            original: "no quiero usar Node.js en este servicio",
            candidate: "Quiero usar Node.js en este servicio.",
            protectedTerms: ["Node.js"]) == .negation)
    }

    @Test
    func profilePresetsCodeTokenProtectionAndNormalizedDecoding() throws {
        #expect(DictationProfilePreset.suggested(for: "com.tinyspeck.slackmacgap") == .chat)
        #expect(DictationProfilePreset.suggested(for: "com.apple.mail") == .email)
        #expect(DictationProfilePreset.suggested(for: "com.apple.Terminal") == .code)
        #expect(DictationProfilePreset.suggested(for: "com.example.unknown") == nil)

        let codeProfile = DictationProfilePreset.code.makeProfile(bundleIdentifier: "com.apple.Terminal")
        #expect(codeProfile.mode == .clean)
        #expect(codeProfile.keepsCodeTokens)

        // Legacy JSON and unnormalized fields decode identically to init(...).
        let unnormalizedJSON = #"{"bundleIdentifier":"com.apple.Terminal","mode":"clean","preservesCodeTokens":false,"polishRecipeID":"builtin.formal"}"#
        let decoded = try JSONDecoder().decode(
            DictationApplicationTextProfile.self, from: Data(unnormalizedJSON.utf8))
        #expect(decoded == DictationApplicationTextProfile(bundleIdentifier: "com.apple.Terminal", mode: .clean))
        #expect(decoded.preservesCodeTokens == nil)
        #expect(decoded.polishRecipeID == nil)

        // Code token protection keeps camelCase (even matching vocab), parenthesized/key=val flags, and backticks verbatim.
        let lexicon = DictationLexicon { _, _ in false }
        let input = "run (--secreteo) --app=secreteo fastApi gitHub `secreteo` with secreteo and fast api"
        let actual = DictationTextRules.apply(
            input, replacements: [], removeFillers: false, spokenCommands: true,
            vocabulary: ["Secreteo", "FastAPI", "GitHub"], preservesCodeTokens: true, lexicon: lexicon)
        #expect(actual == "run (--secreteo) --app=secreteo fastApi gitHub `secreteo` with Secreteo and FastAPI")
    }
}
