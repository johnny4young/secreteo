import DictationKit
import XCTest

final class DictationTextRulesTests: XCTestCase {
    func testFillersDisappearInBothLanguagesWithSeamsRepaired() {
        XCTAssertEqual(
            DictationTextRules.apply(
                "Um, hello there uh let's start",
                replacements: [], removeFillers: true),
            "hello there let's start")
        XCTAssertEqual(
            DictationTextRules.apply(
                "eh, dame un momento ehm para revisar",
                replacements: [], removeFillers: true),
            "dame un momento para revisar")
        // A filler right before closing punctuation must not strand a space.
        XCTAssertEqual(
            DictationTextRules.apply(
                "so that works um.", replacements: [], removeFillers: true),
            "so that works.")
    }

    func testFillerRemovalNeverTouchesRealWordsContainingFillerLetters() {
        // "um" inside "summer"/"museum", "eh" inside "vehemente".
        XCTAssertEqual(
            DictationTextRules.apply(
                "summer at the museum was vehemente",
                replacements: [], removeFillers: true),
            "summer at the museum was vehemente")
    }

    func testFillerFilterOffLeavesTextVerbatim() {
        XCTAssertEqual(
            DictationTextRules.apply(
                "um, as I was saying", replacements: [], removeFillers: false),
            "um, as I was saying")
    }

    func testReplacementsMatchWholeWordsCaseInsensitively() {
        let rules = [DictationReplacement(trigger: "gancho", replacement: "Gancho")]
        XCTAssertEqual(
            DictationTextRules.apply(
                "abre GANCHO y busca gancho, no el desganchado",
                replacements: rules, removeFillers: false),
            "abre Gancho y busca Gancho, no el desganchado")
    }

    func testLongestTriggerWinsOverItsPrefix() {
        let rules = [
            DictationReplacement(trigger: "pull", replacement: "PULL"),
            DictationReplacement(trigger: "pull request", replacement: "PR"),
        ]
        XCTAssertEqual(
            DictationTextRules.apply(
                "open a pull request and pull main",
                replacements: rules, removeFillers: false),
            "open a PR and PULL main")
    }

    func testReplacementsAreSinglePassAndNeverCascade() {
        let rules = [
            DictationReplacement(trigger: "alpha", replacement: "beta"),
            DictationReplacement(trigger: "beta", replacement: "gamma"),
        ]
        XCTAssertEqual(
            DictationTextRules.apply(
                "alpha then beta", replacements: rules, removeFillers: false),
            "beta then gamma",
            "a replacement must not become input to a later rule")
    }

    func testTriggersWithRegexMetacharactersMatchLiterally() {
        let rules = [DictationReplacement(trigger: "c++", replacement: "C++")]
        XCTAssertEqual(
            DictationTextRules.apply(
                "learn c++ today", replacements: rules, removeFillers: false),
            "learn C++ today")
        // A replacement containing template metacharacters stays literal.
        let dollar = [DictationReplacement(trigger: "price", replacement: "$100")]
        XCTAssertEqual(
            DictationTextRules.apply(
                "the price exactly", replacements: dollar, removeFillers: false),
            "the $100 exactly")
    }

    func testCodecRoundTripsAndToleratesGarbage() {
        let rules = [
            DictationReplacement(trigger: "lvgt", replacement: "LVGT"),
            DictationReplacement(trigger: "que es ele", replacement: "QESL"),
        ]
        XCTAssertEqual(
            DictationTextRules.decode(
                replacements: DictationTextRules.encode(rules)),
            rules)
        XCTAssertEqual(DictationTextRules.decode(replacements: "not json"), [])
        XCTAssertEqual(DictationTextRules.decode(replacements: ""), [])
    }

    func testCodecCanonicalizesCorruptOrDuplicateStoredRules() {
        let rules = [
            DictationReplacement(trigger: "  gancho  ", replacement: "old"),
            DictationReplacement(trigger: "", replacement: "dead"),
            DictationReplacement(trigger: "GANCHO", replacement: "Gancho"),
            DictationReplacement(trigger: "keep", replacement: "   "),
        ]
        XCTAssertEqual(
            DictationTextRules.decode(
                replacements: DictationTextRules.encode(rules)),
            [DictationReplacement(trigger: "GANCHO", replacement: "Gancho")])
    }

    func testFillerPassRunsBeforeReplacementsAndResultIsTrimmed() {
        // The user's rule sees the cleaned text, and an edge filler leaves
        // no leading/trailing whitespace behind.
        let rules = [DictationReplacement(trigger: "hello", replacement: "Hi")]
        XCTAssertEqual(
            DictationTextRules.apply(
                "um hello world uh", replacements: rules, removeFillers: true),
            "Hi world")
    }

    func testSpokenCommandsBreakLinesAndAbsorbRecognizerPunctuation() {
        let cases = [
            ("Hola. Nueva línea. Mundo.", "Hola.\nMundo."),
            ("Hola, nueva línea, mundo", "Hola\nmundo"),
            ("Dear team, new paragraph, thanks for waiting.", "Dear team\n\nthanks for waiting."),
            ("Primero punto y aparte segundo", "Primero\n\nsegundo"),
            ("Nuevo párrafo. Listo", "\n\nListo"),
            ("Ship it new line", "Ship it\n")
        ]
        for (heard, typed) in cases {
            XCTAssertEqual(DictationTextRules.apply(heard, replacements: [], removeFillers: false,
                                                    spokenCommands: true), typed, heard)
        }
    }

    func testSpokenCommandsNeedWholePhrasesAndYieldToUserTriggers() {
        XCTAssertEqual(DictationTextRules.apply("the newline character", replacements: [],
                                                removeFillers: false, spokenCommands: true),
                       "the newline character")
        XCTAssertEqual(DictationTextRules.apply("Hola, nueva línea, mundo", replacements: [],
                                                removeFillers: false, spokenCommands: false),
                       "Hola, nueva línea, mundo")
        let rules = [DictationReplacement(trigger: "Nueva línea", replacement: "Nueva Línea Aérea")]
        XCTAssertEqual(DictationTextRules.apply("Vuelo con nueva línea hoy", replacements: rules,
                                                removeFillers: false, spokenCommands: true),
                       "Vuelo con Nueva Línea Aérea hoy")
    }

    func testSpokenCommandsKeepEarlierTrimmingAndWholeWordUserAuthority() {
        let signature = [DictationReplacement(trigger: "sig", replacement: "Best,\nJohn\n")]
        XCTAssertEqual(DictationTextRules.apply("sig", replacements: signature, removeFillers: false,
                                                spokenCommands: true),
                       "Best,\nJohn", "a newline no command produced is trimmed as before")
        XCTAssertEqual(DictationTextRules.apply("Hola nueva li\u{301}nea mundo", replacements: [],
                                                removeFillers: false, spokenCommands: true),
                       "Hola\nmundo", "a decomposed accent still reads as the command")
        let rule = [DictationReplacement(trigger: "aparte", replacement: "Aparte")]
        XCTAssertEqual(DictationTextRules.apply("Punto y aparte", replacements: rule, removeFillers: false,
                                                spokenCommands: true),
                       "Punto y Aparte", "a user trigger inside a phrase keeps it literal")
    }

    func testSpokenDomainsBecomeAddressesInBothLanguages() {
        let cases = [
            ("x dot com", "x.com"),
            ("Open X dot com.", "Open x.com."),
            ("Visita github punto com hoy", "Visita github.com hoy"),
            ("www dot apple dot com", "www.apple.com"),
            ("docs punto my-site punto io", "docs.my-site.io"),
            ("Write to claude dot ai, please", "Write to claude.ai, please"),
            ("sat punto gob punto mx", "sat.gob.mx"),
            ("Go to google dot com.", "Go to google.com."),
            ("Entra a amazon punto com y compra", "Entra a amazon.com y compra"),
            ("Visit W W www.apple.com today.", "Visit www.apple.com today."),
            ("Visit W W W dot apple dot com today.", "Visit www.apple.com today."),
            ("Entra a w. w. w. punto google punto com", "Entra a www.google.com"),
            ("Open www dot github dot com now", "Open www.github.com now")
        ]
        for (heard, typed) in cases {
            XCTAssertEqual(DictationTextRules.apply(heard, replacements: [], removeFillers: false,
                                                    spokenCommands: true, lexicon: Self.lexicon), typed, heard)
        }
    }

    func testSpokenDomainsLeaveProseAndLiteralModeAlone() {
        let prose = [
            "El punto es que no llegó",
            "The dot com bubble burst",
            "La punto com de mi primo",
            "Connect the dots com later",
            "We met at the dot",
            "x dot comedy",
            "La burbuja punto com",
            "Las empresas punto com quebraron",
            "Many dot com companies failed",
            "The early dot com days",
            "She built a polka dot app",
            "W W W wrestling is back",
            "Draw a w w"
        ]
        for text in prose {
            XCTAssertEqual(DictationTextRules.apply(text, replacements: [], removeFillers: false,
                                                    spokenCommands: true, lexicon: Self.lexicon), text)
        }
        XCTAssertEqual(DictationTextRules.apply("x dot com", replacements: [], removeFillers: false,
                                                spokenCommands: false), "x dot com")
    }

    func testSpokenDomainsYieldToUserTriggersAndKeepTrimming() {
        let rules = [DictationReplacement(trigger: "acme dot com", replacement: "ACME.com")]
        XCTAssertEqual(DictationTextRules.apply("Buy at acme dot com", replacements: rules,
                                                removeFillers: false, spokenCommands: true, lexicon: Self.lexicon),
                       "Buy at ACME.com")
        let signature = [DictationReplacement(trigger: "sig", replacement: "Best\n")]
        XCTAssertEqual(DictationTextRules.apply("x dot com sig", replacements: signature,
                                                removeFillers: false, spokenCommands: true, lexicon: Self.lexicon),
                       "x.com Best", "an address is not a break the user asked for")
    }

    func testSpokenDomainsStayWordsWhereTheDictionaryIsMissing() {
        let missing = DictationLexicon { _, _ in nil }
        let cases = [
            ("Visita github punto com", "Visita github punto com"),
            ("Many dot com companies", "Many dot com companies"),
            ("Open x dot com.", "Open x.com.")
        ]
        for (heard, typed) in cases {
            XCTAssertEqual(DictationTextRules.apply(heard, replacements: [], removeFillers: false,
                                                    spokenCommands: true, lexicon: missing), typed, heard)
        }
    }

    /// A fixed dictionary, so the result never depends on the language assets a Mac has.
    private static let lexicon = DictationLexicon { word, spanish in
        (spanish ? ["burbuja", "empresas", "era", "punto"] : ["many", "early", "polka", "google", "apple", "the", "www"])
            .contains(word)
    }
}
