# Parity with Portavoz's dictation

One row per capability and trigger. A row is `Ported` only when a test in this repository proves it, and removing a test from Portavoz never proves anything arrived here. [PROVENANCE](PROVENANCE.md) records the copied files.

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
| Parakeet recognition, EN and ES | `ParakeetEngine`, `ParakeetTokenRevisionReducer`, `ParakeetSegmentMapper` | `ParakeetLanguageConfigurationTests`, `ParakeetTokenRevisionReducerTests`, `TranscriptionTests`, `ParakeetIntegrationTests` | The same tests | Logic ported. A run with the real model is still pending |
| Parakeet Ultra | `ModelCatalog+ParakeetUltra`, `AppServices+ParakeetUltra` | `ParakeetUltraSelectionTests`, `ParakeetUltraRuntimeTests` | | Pin ported. Selection pending, P3 |
| Apple Speech | `SpeechAnalyzerLiveEngine`, `SpeechAnalyzerEngine` | `SpeechAnalyzerLiveEngineTests`, `SpeechAnalyzerLifetimeTests` | The same tests | Ported |
| Silero voice detection | `SileroVoiceActivityDetector` | `SileroVoiceActivityDetectorTests` | The same tests | Logic ported. A run with the real model is still pending |
| Microphone capture | `MicrophoneSource`, `AudioDeviceCatalog`, `CaptureDeliveryBuffer` | `AudioCaptureTests`, `CaptureDeliveryBufferTests`, `MicrophoneTapTransitionTests`, `LinearResamplerTests`, `CapturePCMGeometryTests` | The same tests | Logic ported. Engine start and route changes on a real device still have to be checked |
| Microphone permission | `MicrophonePermissionClient` | `MicrophonePermissionClientTests` | `MicrophonePermissionClientTests` | Ported |
| Choice of microphone | `MicrophoneInputSelection` | `DictationReadinessTests` | | Pending, P3 |
| Model download and storage | `ModelStore`, then `LocalModelStore` | `ModelStoreDownloadFailureTests` | In `local-model-store`, and `ModelCatalogTests` for the pins | Ported. The seed from Portavoz's models and the warm-up wait for P5 |
| Choice of live engine | `LiveSpeechSelection` | `LiveSpeechSelectionTests`, which has to be rewritten | | Pending, P3 |

## Triggers

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Global shortcut | `GlobalHotkey`, `DictationController+Hotkey` | `GlobalHotkeyRoutingTests`, `DictationShortcutTests`, `HotkeySettingTests` | | Pending, P4 |
| Push to talk, Fn and modifiers | `ModifierKeyPTT`, `DictationController+ModifierKey` | `ModifierKeyGestureTests`, `DictationModifierOwnershipTests` | | Pending, P4 |
| Push to talk, mouse | `MouseButtonPTT`, `MousePTTGesture` | `MousePTTGestureTests` | | Pending, P4 |
| Menu | `MenuBarView`, `MenuBarModel` | `MenuBarModelTests`, `DictationUITests` | | Pending, P4 |
| App Intents | `AppServices+DictationIntents` | `DictationIntentTests` | | Pending, P8 |
| Paste last | `DictationController+PasteLast`, `AppServices+PasteLastDictation` | `DictationPasteLastTests` | | Pending, P3 |
| Selection Rewrite | `SelectionRewriteController`, `SelectionCapture` | `SelectionRewriteTests`, `SelectionRewriteUITests` | | Pending, P6 |
| Practice | `DictationPracticeField`, `DictationPracticeView` | `DictationPracticeFieldTests`, `DictationPracticeUITests` | | Pending, P5 |
| One owner per Mac | `DictationOwnershipCoordinator`, `DictationAdmission` | `DictationOwnershipCoordinatorTests`, `DictationAdmissionTests` | Reference tests only | Pending, P4 |

## Sessions and delivery

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Retry with no double paste | `DictationController`, `DictationInsertion` | `DictationDeliveryPhaseTests`, `DictationDeliveryOutcomeTests` | | Pending, P3 |
| Cancel during prepare and during Stop | `DictationController` | `DictationSessionLifecycleTests` | | Pending, P3 |
| Text recovery | `DictationRecoveryView`, `CapturedDictationDestination` | `DictationDestinationRecoveryTests`, `DictationRecoveryCopyTests` | | Pending, P3 |
| Permissions revoked | `DictationMicrophoneReadiness`, `DictationController` | `DictationReadinessTests`, `DictationSessionLifecycleTests` | | Pending, P3 |
| Clipboard restored | `DictationClipboard`, `PasteboardSnapshot` | `DictationClipboardInsertionTests`, `DictationClipboardBoundaryTests` | | Pending, P3 |
| Capitals and spacing from the caret | `DictationCaretCase`, `DictationCaretJoin` | `DictationCaretCaseTests`, `DictationCaretJoinTests` | | Pending, P3 |
| Readback and verified delivery | `DictationTextReadback`, `TextInserter` | `TextInsertionReadbackTests`, `TextInsertionTargetTests` | | Pending, P3 |
| Speech gate and auto stop | `DictationSpeechGate`, `DictationAutoStop` | `DictationSpeechGateTests`, `DictationPauseDetectorTests` | | Pending, P3 |
| Spoken correction in delivery | `DictationCorrections` | `DictationCorrectionTests` | | Pending, P3 |
| Panel, compact indicator and waveform | `DictationPanel`, `DictationCompactIndicator` | `DictationPanelAnchorTests`, `DictationCompactIndicatorTests` | | Pending, P4 |
| Sounds and prewarm | `DictationSoundCue`, `AppServices+DictationPrewarm` | `DictationColdStartTests` | | Pending, P3 |
| Memory: model residency | `AppModelResidencyLedger`, `AppModelIdleReleaseScheduler` | `DictationResourceOwnershipTests`, which asserts sharing in one process and has to be rewritten | | Pending, P2 |

## Text features and data

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Modes, recipes and per-app profiles | `DictationTextPreferences`, `DictationTextSettingsModel` | `DictationRecipeTests`, `DictationTextModeDeliveryTests` | | Pending, P5 and P6 |
| Polish with Apple Foundation Models and Ollama | `PolishDictation`, `DictationTextPolishers` | `PolishDictationTests`, `DictationPolishRouterTests`, `DictationPolishDeliveryTests` | | Pending, P6 |
| Polish egress consent | `AppServices+DictationPolish`, `Schema+DictationPolish` | `DictationPolishEgressTests`, which has to be rewritten | | Pending, P6 |
| Translate while pasting | `TranslateDictation`, `AppleDictationTranslator` | `TranslateDictationTests`, `DictationTranslationDeliveryTests` | | Pending, P6 |
| History, with consent and retention | `DictationHistoryModel`, store | `DictationHistoryStoreTests`, `DictationHistoryRecordingTests` | | Pending, P7 |
| Search | Store | `DictationSearchStoreTests` | | Pending, P7 |
| Statistics | `DictationStatsModel`, store | `DictationStatsStoreTests`, `DictationStatsTests` | | Pending, P7 |
| Read-only MCP | `DictationToolbox` | `DictationToolboxTests`, `DictationAgentAccessStoreTests` | | Pending, P8 |
| Settings: vocabulary, microphone, memory and Polish panels | `DictationSection`, `DictationTextSettingsSection`, `DictationDictionaryEditor` | `SettingsUITests` | | Pending, P5 |
| Onboarding | `OnboardingDictationStep`, `OnboardingModelPreparation` | `OnboardingUITests`, `OnboardingModelPreparationTests` | | Pending, P5 |
| Preference import | `PortableSettings` | `PortableSettingsTests` | | Pending, P5 |
| English and Spanish | `Localizable.xcstrings` | `LocalizationTests` | | Pending, P5 |

## Approved losses

| Capability | Portavoz test | Replacement |
|---|---|---|
| Ask over dictations | `AskDictationsTests`, `AskDictationRetrievalTests` | Agents read history through MCP ([D2](DECISIONS.md#d2-scope-and-approved-losses)) |
| Dictation into meeting notes | `DictationMeetingNoteStoreTests` | Copy and paste |
| Polish with embedded MLX | `DictationTextPolisherTests`, in part | Apple Foundation Models and Ollama |
