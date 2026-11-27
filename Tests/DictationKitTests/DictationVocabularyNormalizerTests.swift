import DictationKit
import Testing

@testable import DictationKit

struct DictationVocabularyNormalizerTests {
    private static let testLexicon = DictationLexicon { word, spanish in
        if spanish {
            return ["secreto", "notas", "texto", "hola", "con", "el", "la", "de", "no", "vino", "hoy"].contains(word)
        }
        return [
            "secret", "marker", "marks", "doctor", "notes", "hello", "with", "the", "and", "fast", "open",
            "just", "in", "time", "brand", "on", "cars", "entry"
        ].contains(word)
    }

    @Test
    func exactFoldedMatchesFixCasingDiacriticsAndMultiWordNames() {
        let vocab = ["Secreteo", "PostgreSQL", "macOS", "Café", "Johnny Young", "Node.js", "O'Brien"]
        let input = "we met johnny young and o'brien at the cafe to run secreteo on macos with postgresql and node js."
        let actual = DictationVocabularyNormalizer.applying(vocab, to: input, lexicon: Self.testLexicon)
        #expect(
            actual == "we met Johnny Young and O'Brien at the Café to run Secreteo on macOS with PostgreSQL and Node.js.")
    }

    @Test
    func splitCompoundsJoinAtCamelBoundariesWithoutMergingFlatNames() {
        let vocab = ["FastAPI", "PostgreSQL", "GraphQL", "OpenAI", "Antigravity", "Mariano", "Justin", "Brandon"]
        let input = "build fast api, graph ql, postgre sql, open ai, anti-gravity. María no vino just in time on brand on."
        let actual = DictationVocabularyNormalizer.applying(vocab, to: input, lexicon: Self.testLexicon)
        #expect(actual == "build FastAPI, GraphQL, PostgreSQL, OpenAI, Antigravity. María no vino just in time on brand on.")

        let hyphenated = DictationVocabularyNormalizer.applying(["Justin"], to: "just-in-time", lexicon: Self.testLexicon)
        #expect(hyphenated == "just-in-time")
    }

    @Test
    func boundedFuzzyMatchesMisspellingsWithoutCorruptingDictionaryWordsOrPlurals() {
        let vocab = ["Kubernetes", "Secreteo", "Cognosos", "Market", "MacBook", "Webhook", "AirPods", "Mark"]
        let input = "deploy kubernetis and cubernetes on cognosus with secreteyo, el secreto del marker, "
            + "two macbooks, configure webhooks, left airpod, high marks."
        let actual = DictationVocabularyNormalizer.applying(vocab, to: input, lexicon: Self.testLexicon)
        #expect(
            actual == "deploy Kubernetes and Kubernetes on Cognosos with Secreteo, el secreto del marker, "
                + "two MacBooks, configure Webhooks, left airpod, high marks.")
    }

    @Test
    func fuzzyMatchingFailsClosedWhenEitherDictionaryIsMissingAndSkipsAmbiguousTies() {
        let missingLexicon = DictationLexicon { _, _ in nil }
        #expect(DictationVocabularyNormalizer.applying(
            ["Kubernetes"], to: "run kubernetis", lexicon: missingLexicon) == "run kubernetis")

        // English-only Mac (Spanish dictionary missing) must not corrupt Spanish "secreto".
        let englishOnly = DictationLexicon { word, spanish in
            spanish ? nil : ["secret", "marker"].contains(word)
        }
        #expect(DictationVocabularyNormalizer.applying(
            ["Secreteo"], to: "el secreto", lexicon: englishOnly) == "el secreto")

        // Exact match still works even without a lexicon.
        #expect(DictationVocabularyNormalizer.applying(
            ["Kubernetes"], to: "run kubernetes", lexicon: missingLexicon) == "run Kubernetes")

        // Distance-1 tie between two vocabulary terms is left untouched.
        #expect(DictationVocabularyNormalizer.applying(
            ["Katana", "Kabana"], to: "the kalana", lexicon: Self.testLexicon) == "the kalana")
    }

    @Test
    func contractionsAndPossessivesStayIntactWhilePossessiveVocabNormalizes() {
        let vocab = ["Don", "Coulon", "Sentry", "Secreteo", "O'Brien", "It"]
        let input = "we don't know, I couldn't go, check john's entry, it's secreteo's config for o'brien."
        let actual = DictationVocabularyNormalizer.applying(vocab, to: input, lexicon: Self.testLexicon)
        #expect(actual == "we don't know, I couldn't go, check john's entry, it's Secreteo's config for O'Brien.")
    }

    @Test
    func decomposedUnicodeVocabAndInputNormalizeWithoutDoubleDiacritics() {
        let nfdVocab = ["Cafe\u{0301}", "Sa\u{0301}nchez"]
        let nfdInput = "visit cafe\u{0301} with sa\u{0301}nchez"
        let actual = DictationVocabularyNormalizer.applying(nfdVocab, to: nfdInput, lexicon: Self.testLexicon)
        #expect(actual == "visit Café with Sánchez")
    }

    @Test
    func urlsPathsStayProtectedWhileSlashProseDotTermsAndJoinedTokensNormalize() {
        let vocab = ["Secreteo", "Kubernetes", "FastAPI", "PostgreSQL", "macOS", "iOS", "ASP.NET", "Socket.IO", "Node.js", "O'Brien"]
        let protectedInput = "see https://github.com/secreteo secreteo.com hi@secreteo.dev @secreteo #secreteo /tmp/secreteo my_secreteo_app"
        #expect(DictationVocabularyNormalizer.applying(vocab, to: protectedInput, lexicon: Self.testLexicon) == protectedInput)

        let proseInput = "support macos/ios and fastapi/postgresql with asp.net, socket.io, nodejs and obrien"
        let actual = DictationVocabularyNormalizer.applying(vocab, to: proseInput, lexicon: Self.testLexicon)
        #expect(actual == "support macOS/iOS and FastAPI/PostgreSQL with ASP.NET, Socket.IO, Node.js and O'Brien")
    }

    @Test
    func explicitReplacementsWinOverVocabularyIncludingMultiWordTriggersAndEmptyRules() {
        let rules = [
            DictationReplacement(trigger: "my signoff", replacement: "Best regards,\nJohnny"),
            DictationReplacement(trigger: "secreteo", replacement: "SECRETEO-CUSTOM"),
            DictationReplacement(trigger: "open ai key", replacement: "OPENAI_API_KEY"),
            DictationReplacement(trigger: "", replacement: "ignored")
        ]
        let encoded = DictationTextRules.encode(rules)
        let decoded = DictationTextRules.decode(replacements: encoded)
        #expect(decoded.count == 3)

        let actual = DictationTextRules.apply(
            "um, send fast api notes for secreteo using open ai key. my signoff",
            replacements: rules, removeFillers: true, spokenCommands: true,
            vocabulary: ["Secreteo", "FastAPI", "OpenAI"], lexicon: Self.testLexicon)
        #expect(actual == "send FastAPI notes for SECRETEO-CUSTOM using OPENAI_API_KEY. Best regards,\nJohnny")
    }

    @Test
    func polishDictationForwardsVocabularyAndAvoidsIdentifierAndLowercaseCatch22() async {
        struct RecordingPolisher: DictationTextPolishing {
            let reply: @Sendable (String, [String]) -> String
            func polish(_ text: String, recipe _: String?, vocabulary: [String]) async throws -> String {
                reply(text, vocabulary)
            }
        }

        let kept = PolishDictation(polisher: RecordingPolisher { text, vocab in
            #expect(vocab == ["Secreteo", "FastAPI"])
            return text + "."
        })
        let good = await kept("ship Secreteo with FastAPI today", vocabulary: ["Secreteo", "FastAPI"])
        #expect(good == .polished("ship Secreteo with FastAPI today."))

        let mangled = PolishDictation(polisher: RecordingPolisher { _, _ in
            "ship secreteo with fastapi today."
        })
        let rejected = await mangled("ship Secreteo with FastAPI today", vocabulary: ["Secreteo", "FastAPI"])
        #expect(rejected == .kept(.changedMeaning(.protectedTerm)))

        // URL/path containing lowercase vocab term must not create an unsolvable catch-22.
        let urlPolisher = PolishDictation(polisher: RecordingPolisher { _, _ in
            "Please check https://github.com/secreteo and /tmp/secreteo tomorrow."
        })
        let urlResult = await urlPolisher(
            "please check https://github.com/secreteo and /tmp/secreteo tomorrow",
            vocabulary: ["Secreteo", "GitHub"])
        #expect(urlResult == .polished("Please check https://github.com/secreteo and /tmp/secreteo tomorrow."))

        // Lowercase selection rewrite obeys "keep as written" without false protectedTerm failure.
        let rewritePolisher = PolishDictation(polisher: RecordingPolisher { _, _ in
            "We use fastapi in production."
        })
        let rewriteResult = await rewritePolisher("we use fastapi in production", vocabulary: ["FastAPI"])
        #expect(rewriteResult == .polished("We use fastapi in production."))
    }
}
