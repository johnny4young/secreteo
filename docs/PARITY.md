# Parity with Portavoz's dictation

One row per capability and trigger. A row is `Ported` only when a test in this repository proves it, and removing a test from Portavoz never proves anything arrived here. [PROVENANCE](PROVENANCE.md) records the copied files.

Disposable UI journeys and injected unit fixtures prove the paths they exercise; they do not close physical delivery, TCC, coexistence, microphone or model-quality acceptance. Those limits remain in [GAPS](GAPS.md) and the [release contract](QUALITY.md#release-contract).

## Domain and text

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Filler removal, dictionary and spoken layout commands | `DictationTextRules` | `DictationTextRulesTests` | `DictationTextRulesTests` | Ported |
| Learned dictionary terms | `DictationDictionaryTerms` | `DictationDictionaryTermsTests` | `DictationDictionaryTermsTests` | Ported |
| Parsing a spoken correction, EN and ES | `DictationCorrectionCommand` | `DictationCorrectionTests` | `DictationCorrectionCommandTests` | Ported |
| Assembling text, and rejecting noise artifacts | `DictationAssembler` | `DictationTests` | `DictationAssemblerTests` | Ported |
| Polish may fix form, never facts | `DictationPolishFidelity` | `DictationPolishFidelityTests`, `DictationRecipeTests` | `DictationPolishFidelityTests`, `DictationRecipeFidelityTests` | Ported |
| Word counts, days and time saved | `DictationStats` | `DictationStatsTests` | `DictationStatsTests`, `DictationStatsValueTests` | Ported |
| Record, consent, filter and recipe values | `DictationHistory`, `DictationRecipe`, `DictationTextMode` | Through the store and settings tests | `DictationDomainTests` | Ported |

## Speech and capture

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Parakeet recognition, EN and ES | `ParakeetEngine`, `ParakeetTokenRevisionReducer`, `ParakeetSegmentMapper` | `ParakeetLanguageConfigurationTests`, `ParakeetTokenRevisionReducerTests`, `TranscriptionTests`, `ParakeetIntegrationTests` | The same tests, and [paired evidence](spikes/fluidaudio-upstream.md) with the real model | Ported |
| Parakeet Ultra | `ModelCatalog+ParakeetUltra`, `AppServices+ParakeetUltra` | `ParakeetUltraSelectionTests`, `ParakeetUltraRuntimeTests` | `SpeechUltraDownloadTests`, `DictationSettingsUITests` | Ported. Settings offers it, it downloads only on request, and dictation keeps v3 until it verifies |
| Apple Speech | `SpeechAnalyzerLiveEngine`, `SpeechAnalyzerEngine` | `SpeechAnalyzerLiveEngineTests`, `SpeechAnalyzerLifetimeTests` | The same tests | Ported |
| Silero voice detection | `SileroVoiceActivityDetector` | `SileroVoiceActivityDetectorTests` | The same tests, and [paired evidence](spikes/fluidaudio-upstream.md) with the real model | Ported |
| Microphone capture | `MicrophoneSource`, `AudioDeviceCatalog`, `CaptureDeliveryBuffer` | `AudioCaptureTests`, `CaptureDeliveryBufferTests`, `MicrophoneTapTransitionTests`, `LinearResamplerTests`, `CapturePCMGeometryTests` | The same tests | Logic ported. Engine start and route changes on a real device still have to be checked |
| Microphone permission | `MicrophonePermissionClient` | `MicrophonePermissionClientTests` | `MicrophonePermissionClientTests` | Ported |
| Choice of microphone | `MicrophoneInputSelection` | `DictationReadinessTests` | The same tests, with `testLiveCompositionReadsTheInjectedAudioPreference` | Ported, with its picker in Settings |
| Model download and storage | `ModelStore`, then `LocalModelStore` | `ModelStoreDownloadFailureTests` | In `local-model-store`, and `ModelCatalogTests` for the pins | Ported. A stopped download resumes at the next file, and unused models are collected at launch. Files Portavoz already downloaded are cloned from `Portavoz/Models` when they hash right, and onboarding warms the model. Settings lists the shared folder and removes only Secreteo's claim (`DictationModelListTests`, `DictationModelListUITests`) |
| Choice of live engine | `LiveSpeechSelection` | `LiveSpeechSelectionTests`, which has to be rewritten | `LiveSpeechSelectionTests`: the preference, `testSelectedAppleWithAutomaticLanguageNeverStartsAModelLoad`, and `testTheDefaultUltraNeitherDownloadsNorBlocksDictation` rewritten for a default Ultra that is not downloaded | Ported with no meeting lane. Settings chooses Parakeet, Parakeet Ultra or Apple Speech, and the warm model reloads on a change. Until Ultra is downloaded, its default reads v3 and never downloads |

## Triggers

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Global shortcut | `GlobalHotkey`, `DictationController+Hotkey` | `GlobalHotkeyRoutingTests`, `DictationShortcutTests`, `HotkeySettingTests` | The same tests. `testNoRegistrarKeepsTemporaryCompositionInert` checks the disposable feature instead of a shortcut fixture | Armed in every build since 0.1.0 ([D28](DECISIONS.md#d28-release-builds-run-global-dictation-from-010)). A real shortcut still has to be checked |
| Push to talk, Fn and modifiers | `ModifierKeyPTT`, `DictationController+ModifierKey` | `ModifierKeyGestureTests`, `DictationModifierOwnershipTests` | `ModifierKeyGestureTests` | Armed in every build since 0.1.0 ([D28](DECISIONS.md#d28-release-builds-run-global-dictation-from-010)) when configured, with its control in Settings |
| Push to talk, mouse | `MouseButtonPTT`, `MousePTTGesture` | `MousePTTGestureTests` | The same tests | Armed in every build since 0.1.0 ([D28](DECISIONS.md#d28-release-builds-run-global-dictation-from-010)) when configured, with its control in Settings |
| Menu | `MenuBarView`, `MenuBarModel` | `MenuBarModelTests`, `DictationUITests` | `DictationUITests` | Dictate and Paste last in the menu |
| App Intents | `AppServices+DictationIntents` | `DictationIntentTests` | `DictationIntentTests` | Ported: Dictate and Paste last through the shortcut's admission, and Search and Open dictations behind the agent consent |
| Paste last | `DictationController+PasteLast`, `AppServices+PasteLastDictation` | `DictationPasteLastTests` | The same tests | In the menu, and with an optional shortcut |
| Selection Rewrite | `SelectionRewriteController`, `SelectionCapture` | `SelectionRewriteTests`, `SelectionRewriteUITests` | The same tests, and the Rewrite cases of `DictationAdmissionTests` and `DictationOwnershipCoordinatorTests` | Ported, in the menu and with an optional ⌃⌥⌘R. A real selection in another app still has to be checked |
| Practice | `DictationPracticeField`, `DictationPracticeView` | `DictationPracticeFieldTests`, `DictationPracticeUITests` | The same tests, with the onboarding journey in `OnboardingUITests` and readiness cases in `DictationPracticeReadinessTests` | In Settings and onboarding. Verified delivery to a visible practice field records completion before global readiness; late delivery to a hidden field is rejected. Disposable UI fixtures retain their synthetic readiness override |
| One owner per Mac | `DictationOwnershipCoordinator`, `DictationAdmission` | `DictationOwnershipCoordinatorTests`, `DictationAdmissionTests` | The same tests, with the composition's, among them `onlyTheOwnerArmsTheShortcut`, `aHeldTriggerKeepsItsWordsWhenAHandoffDisarmsIt` and `compositionReadsOwnershipForPrewarmAndAdmission`, plus `KnownDictationPeersTests` and the reference tests | Ported. `DictationFeature.start()` runs the coordinator. It has not run against a real Portavoz |

## Sessions and delivery

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Retry with no double paste | `DictationController`, `DictationInsertion` | `DictationDeliveryPhaseTests`, `DictationDeliveryOutcomeTests` | The same tests, plus `testUndeliveredTextCanBeCopiedAndExplicitlyRetried` in `DictationUITests` | Wired into app sessions and exercised with disposable recovery/delivery fixtures. Real delivery into another app remains open |
| Cancel during prepare and during Stop | `DictationController` | `DictationSessionLifecycleTests` | The same tests, plus `testPreparingDictationCanCancelWithoutAListeningClaim` and `testDictationPanelCancelsAndRestartsWithoutGlobalInput` in `DictationUITests` | Wired into app sessions. Synthetic tests cover cancellation, restart and native Stop ordering; a real capture still has to be checked |
| Text recovery | `DictationRecoveryView`, `CapturedDictationDestination` | `DictationDestinationRecoveryTests`, `DictationRecoveryCopyTests` | `DictationDestinationRecoveryTests`, `DictationSessionFixesTests`, `DictationUITests` | Recovery is present in the panel. Fixtures cover copy, explicit retry, retention across another trigger and capture failure with words. Physical clipboard behavior remains open |
| Permissions revoked | `DictationMicrophoneReadiness`, `DictationController` | `DictationReadinessTests`, `DictationSessionLifecycleTests` | The same tests, with `testFixtureRecoverySurvivesFreshDependenciesForEachMenuInvocation` | Logic ported. A real revoked permission still has to be checked |
| Clipboard restored | `DictationClipboard`, `PasteboardSnapshot` | `DictationClipboardInsertionTests`, `DictationClipboardBoundaryTests` | The same tests | Logic ported. The real paste into another app still has to be checked |
| Capitals and spacing from the caret | `DictationCaretCase`, `DictationCaretJoin` | `DictationCaretCaseTests`, `DictationCaretJoinTests` | The same tests | Logic ported. A real caret in another app still has to be checked |
| Readback and verified delivery | `DictationTextReadback`, `TextInserter` | `TextInsertionReadbackTests`, `TextInsertionTargetTests` | The same tests | Logic ported. Real Accessibility readback still has to be checked |
| Speech gate and auto stop | `DictationSpeechGate`, `DictationAutoStop` | `DictationSpeechGateTests`, `DictationPauseDetectorTests` | The same tests, with `testDisposableCompositionNeverDownloadsTheDetector`, and `testTurningOnDictationDownloadsNoModelWhateverTheGate` rewritten, because the detector comes with the speech model | Detector and pause logic are wired through live session dependencies. Disposable tests do not download the detector; real speech/model acceptance remains separate |
| Spoken correction in delivery | `DictationCorrections` | `DictationCorrectionTests` | The same tests, without the practice test | Logic ported. A real field still has to be checked |
| Panel, compact indicator and waveform | `DictationPanel`, `DictationCompactIndicator` | `DictationPanelAnchorTests`, `DictationCompactIndicatorTests` | The same tests, with `DictationWaveformTests` and `testTheStripAnchorIsReadWithTheDestination`, plus `DictationMeterTests` for the meter stopping at Stop, and `DictationUITests` | Ported. A real caret in another app still has to be checked |
| Sounds and prewarm | `DictationSoundCue`, `AppServices+DictationPrewarm` | `DictationColdStartTests` | The same tests | Ported. Prewarm is off by default and never downloads |
| Memory: model residency | `AppModelResidencyLedger`, `AppModelIdleReleaseScheduler` | `DictationResourceOwnershipTests`, which asserts sharing in one process | `DictationModelResidencyTests`, rewritten for one app with a synthetic loader and a held clock, and `WarmModelTests` | Ported. A loaded model is released after 10 idle minutes, after one with the lightweight profile, and at once under memory pressure. A model in use has no idle clock, and pressure never takes it from a session. The next use loads it again, or, with Prewarm on, the end of the pressure. |

## Text features and data

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Modes, recipes and per-app profiles | `DictationTextPreferences`, `DictationTextSettingsModel` | `DictationRecipeTests`, `DictationTextModeDeliveryTests` | `DictationRecipeFidelityTests`, `DictationRecipePreferenceTests`, `DictationRecipePromptTests`, `DictationTextModeDeliveryTests` with `firstEnableAfterAppCompositionStillDeliversLiteral` and `buildingTheFeatureDoesNotInitializeTextPreferences`, rewritten because a database that cannot open no longer fails the feature, `DictationPolishUITests` | Ported, with recipes and per-app profiles in Settings |
| Polish with Apple Foundation Models and Ollama | `PolishDictation`, `DictationTextPolishers` | `PolishDictationTests`, `DictationPolishRouterTests`, `DictationPolishDeliveryTests` | `PolishDictationTests`, `DictationPolishDeliveryTests`, `DictationPolishRouterTests`, `DictationTextPolisherTests`, `DictationPolishUITests` | Ported without MLX, with its engine and Ollama model in Settings |
| Polish egress consent | `AppServices+DictationPolish`, `Schema+DictationPolish` | `DictationPolishEgressTests`, which has to be rewritten | `DictationPolishEgressTests`, rewritten | Ported. Only loopback, with no journal ([D24](DECISIONS.md#d24-polish-runs-only-on-this-mac-and-keeps-no-journal)) |
| Translate while pasting | `TranslateDictation`, `AppleDictationTranslator` | `TranslateDictationTests`, `DictationTranslationDeliveryTests` | The same tests, and `DictationTranslationUITests` | Ported, with the target and the language download in Settings |
| History, with consent and retention | `DictationHistoryModel`, store | `DictationHistoryStoreTests`, `DictationHistoryRecordingTests` | The same tests, `DictationHistoryModelTests`, `DictationHistoryErasureTests` and `DictationHistoryUITests` | Ported, in its own window from the menu and in Settings. Erasing leaves no words in the files. Never imported from Portavoz |
| Search | Store | `DictationSearchStoreTests` | The same tests, and `DictationHistoryUITests` | Ported. Accents and case are ignored, the last word completes, and typed search syntax is matched as text |
| Statistics | `DictationStatsModel`, store | `DictationStatsStoreTests`, `DictationStatsTests` | The same tests, and `DictationHistoryUITests` | Ported. Their own consent, off by default, counts without text for a year, shown in the history window |
| Read-only MCP | `DictationToolbox` | `DictationToolboxTests`, `DictationAgentAccessStoreTests` | `DictationToolboxTests`, `DictationAgentAccessStoreTests`, `MCPServerTests`, `DictationMCPCommandTests`, `DictationAgentAccessUITests` | Ported: `secreteo-mcp` in `Contents/Helpers`, off until the user turns on agent access in Settings, which is never imported from Portavoz |
| Settings: vocabulary, microphone, memory and Polish panels | `DictationSection`, `DictationTextSettingsSection`, `DictationDictionaryEditor` | `SettingsUITests` | `DictationSettingsUITests`, `DictationPreferenceStoreTests` | Triggers, language, microphone, replacements, vocabulary and text mode ported, without vocabulary suggestions from meetings. Memory is ported without its hardware suggestion. Polish is ported with its engine, recipes and translation |
| Onboarding | `OnboardingDictationStep`, `OnboardingModelPreparation` | `OnboardingUITests`, `OnboardingModelPreparationTests` | `OnboardingUITests`, `OnboardingModelPreparationTests`, `FirstRunOnboardingPolicyTests` | Three steps on first launch: dictation and permissions, the speech model, which is loaded once even when installed, and practice. No meeting steps or voice enrollment |
| Preference import | `PortableSettings` | `PortableSettingsTests` | `PortavozPreferenceImportTests`, `DictationSettingsUITests` | Reads Portavoz's saved settings instead of an exported file. Imports only what Secreteo's Settings shows, after a preview ([G14](GAPS.md#g14-portavoz-settings-left-out-of-the-import)) |
| English and Spanish | `Localizable.xcstrings` | `LocalizationTests` | `Tests/Tooling/test_ui_contract.py`, run by `legacy-tooling` | Ported: unique keys, Spanish for every key, matching placeholders, English left only for shared terms, every visible literal cataloged and no stale keys. The exporter and AppKit panel checks have no Secreteo counterpart |

## Quality tooling

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Public corpus and audio admission | `dictation_corpus.py`, `Fixtures/DictationValidation` | `test_dictation_corpus` | The same test | Ported |
| Rendering the corpus with macOS voices | `materialize_dictation_corpus.py`, `dictation_audio.py` | `test_dictation_materialization` | The same test | Ported |
| Field recordings with a real microphone | `dictation_field_corpus.py`, `record-dictation-field-corpus.swift` | `test_dictation_field_corpus` | The same test, without the comparison | Ported |
| Offline benchmark report | `dictation_benchmark.py`, `dictation_model_receipt.py` | `test_dictation_benchmark`, `test_dictation_model_runner` | `test_dictation_benchmark`, `test_dictation_model_runner`, `test_dictation_model_receipt` | Ported |
| Speech gate over every cell | `DictationSpeechGateCorpusTests` | The same test | The same test | Ported. Skipped unless a scratch corpus and model store are named |
| Search quality scorecard | `dictation_search_quality.py`, `Fixtures/DictationSearch`, `bench-dictation-search` | `test_dictation_search_quality` | `test_dictation_search_quality`, `DictationSearchQualityTests` | Ported, without the meeting lane. The producer is a test lane that searches as the history window does, since Secreteo has no Ask retrieval |
| Model, controller and Ultra comparison lanes | `run_dictation_model_baseline.py`, `run_dictation_controller_matrix.py`, `run_dictation_model_comparison.py` | `test_dictation_model_runner`, `test_dictation_controller_runner`, `test_dictation_controller_matrix`, `DictationModelProbeTests`, `DictationVendorProbeTests`, `DictationControllerModelProbeTests` | The same tests | Ported. The receivers read only a named scratch store and skip unless a run names one; `make test-model-gated` runs v3, Ultra and Silero together. The vendor parity check has no meeting consumer |

## Approved losses

| Capability | Portavoz test | Replacement |
|---|---|---|
| Ask over dictations | `AskDictationsTests`, `AskDictationRetrievalTests` | Agents read history through MCP ([D2](DECISIONS.md#d2-scope-and-approved-losses)) |
| Dictation into meeting notes | `DictationMeetingNoteStoreTests` | Copy and paste |
| Polish with embedded MLX | `DictationTextPolisherTests`, in part | Apple Foundation Models and Ollama |
| A settings import refused while a capture prepares | `testAppSettingsWriteRejectsPreparationAndAllowsApplyAfterCancel`, in `DictationReadinessTests` | No settings file. The Portavoz import writes only what Settings edits during a session |
| A shortcut conflict fixture refused outside a disposable launch | The fixture half of `testNoRegistrarKeepsTemporaryCompositionInert` | No such fixture. A disposable launch registers no shortcut |

## Tests that wait for their slice

None. Every ported test runs, or is listed above as rewritten or an approved loss.
