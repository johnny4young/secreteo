import LiveSpeech
import Testing

@testable import DictationSession
@testable import LiveSpeech

/// Auto must never let an engine write outside Secreteo's languages. A new engine
/// stops this switch from compiling until it states how it keeps the contract.
struct DictationLanguageContractTests {
    @Test(arguments: LiveSpeechSelection.allCases, [nil, "es", "en"])
    func everyDictationEngineKeepsItsOutputInTheDictationLanguages(
        _ engine: LiveSpeechSelection, _ language: String?
    ) {
        let allowed = LiveSpeechSelection.dictationLanguages
        let hints = TranscriptionHints(language: language, allowedLanguages: allowed)
        switch engine {
        case .parakeet, .parakeetUltra:
            // ParakeetLanguageConfigurationTests proves these filter the Latin script.
            let filter = ParakeetEngine.scriptFilter(hints)?.rawValue
            #expect(filter.map(allowed.contains) == true)
            #expect(language == nil || filter == language)
        case .appleSpeech:
            // Apple's live lane runs one installed locale and refuses Auto.
            #expect(SpeechAnalyzerLiveReadiness.admittedLanguage(language) == language)
        }
    }
}
