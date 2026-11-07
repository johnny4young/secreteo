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
| Parakeet recognition, EN and ES | `ParakeetEngine`, `ParakeetTokenRevisionReducer`, `ParakeetSegmentMapper` | `ParakeetLanguageConfigurationTests`, `ParakeetTokenRevisionReducerTests`, `TranscriptionTests`, `ParakeetIntegrationTests` | The same tests, and [paired evidence](spikes/fluidaudio-upstream.md) with the real model | Ported |
| Parakeet Ultra | `ModelCatalog+ParakeetUltra`, `AppServices+ParakeetUltra` | `ParakeetUltraSelectionTests`, `ParakeetUltraRuntimeTests` | | Pin ported. Selection pending, P3 |
| Apple Speech | `SpeechAnalyzerLiveEngine`, `SpeechAnalyzerEngine` | `SpeechAnalyzerLiveEngineTests`, `SpeechAnalyzerLifetimeTests` | The same tests | Ported |
| Silero voice detection | `SileroVoiceActivityDetector` | `SileroVoiceActivityDetectorTests` | The same tests, and [paired evidence](spikes/fluidaudio-upstream.md) with the real model | Ported |
| Microphone capture | `MicrophoneSource`, `AudioDeviceCatalog`, `CaptureDeliveryBuffer` | `AudioCaptureTests`, `CaptureDeliveryBufferTests`, `MicrophoneTapTransitionTests`, `LinearResamplerTests`, `CapturePCMGeometryTests` | The same tests | Logic ported. Engine start and route changes on a real device still have to be checked |
| Microphone permission | `MicrophonePermissionClient` | `MicrophonePermissionClientTests` | `MicrophonePermissionClientTests` | Ported |
| Choice of microphone | `MicrophoneInputSelection` | `DictationReadinessTests` | The same tests, without the composition's | Ported, with its picker in Settings |
| Model download and storage | `ModelStore`, then `LocalModelStore` | `ModelStoreDownloadFailureTests` | In `local-model-store`, and `ModelCatalogTests` for the pins | Ported. A stopped download resumes at the next file, and unused models are collected at launch. Files Portavoz already downloaded are cloned from `Portavoz/Models` when they hash right, and onboarding warms the model |
| Choice of live engine | `LiveSpeechSelection` | `LiveSpeechSelectionTests`, which has to be rewritten | `LiveSpeechSelectionTests`, for the preference | Preference ported with no meeting lane. Routing arrives with the composition |

## Triggers

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Global shortcut | `GlobalHotkey`, `DictationController+Hotkey` | `GlobalHotkeyRoutingTests`, `DictationShortcutTests`, `HotkeySettingTests` | The same tests, without the UI fixture's | Armed in Debug and `make install`. A real shortcut still has to be checked |
| Push to talk, Fn and modifiers | `ModifierKeyPTT`, `DictationController+ModifierKey` | `ModifierKeyGestureTests`, `DictationModifierOwnershipTests` | `ModifierKeyGestureTests` | Armed in Debug and `make install` when configured, with its control in Settings |
| Push to talk, mouse | `MouseButtonPTT`, `MousePTTGesture` | `MousePTTGestureTests` | The same tests | Armed in Debug and `make install` when configured, with its control in Settings |
| Menu | `MenuBarView`, `MenuBarModel` | `MenuBarModelTests`, `DictationUITests` | `DictationUITests` | Dictate and Paste last in the menu |
| App Intents | `AppServices+DictationIntents` | `DictationIntentTests` | `DictationIntentTests` | Dictate and Paste last ported, through the shortcut's admission. Search and Open dictations wait for the history, P8 |
| Paste last | `DictationController+PasteLast`, `AppServices+PasteLastDictation` | `DictationPasteLastTests` | The same tests | In the menu, and with an optional shortcut |
| Selection Rewrite | `SelectionRewriteController`, `SelectionCapture` | `SelectionRewriteTests`, `SelectionRewriteUITests` | | Pending, P6 |
| Practice | `DictationPracticeField`, `DictationPracticeView` | `DictationPracticeFieldTests`, `DictationPracticeUITests` | The same tests, with the onboarding journey in `OnboardingUITests` | In Settings and in onboarding, each window holding the field |
| One owner per Mac | `DictationOwnershipCoordinator`, `DictationAdmission` | `DictationOwnershipCoordinatorTests`, `DictationAdmissionTests` | The same tests, without the composition's, plus `KnownDictationPeersTests` and the reference tests | Coordinator ported. The app does not run it yet, and it has not run against a real Portavoz |

## Sessions and delivery

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Retry with no double paste | `DictationController`, `DictationInsertion` | `DictationDeliveryPhaseTests`, `DictationDeliveryOutcomeTests` | The same tests | Logic ported. The app does not run a session yet |
| Cancel during prepare and during Stop | `DictationController` | `DictationSessionLifecycleTests` | The same tests | Logic ported. The app does not run a session yet |
| Text recovery | `DictationRecoveryView`, `CapturedDictationDestination` | `DictationDestinationRecoveryTests`, `DictationRecoveryCopyTests` | `DictationDestinationRecoveryTests`, `DictationSessionFixesTests` | Logic ported, and a capture failure now keeps the words too. The recovery view arrives with the panel |
| Permissions revoked | `DictationMicrophoneReadiness`, `DictationController` | `DictationReadinessTests`, `DictationSessionLifecycleTests` | The same tests, without the composition's | Logic ported. A real revoked permission still has to be checked |
| Clipboard restored | `DictationClipboard`, `PasteboardSnapshot` | `DictationClipboardInsertionTests`, `DictationClipboardBoundaryTests` | The same tests | Logic ported. The real paste into another app still has to be checked |
| Capitals and spacing from the caret | `DictationCaretCase`, `DictationCaretJoin` | `DictationCaretCaseTests`, `DictationCaretJoinTests` | The same tests | Logic ported. A real caret in another app still has to be checked |
| Readback and verified delivery | `DictationTextReadback`, `TextInserter` | `TextInsertionReadbackTests`, `TextInsertionTargetTests` | The same tests | Logic ported. Real Accessibility readback still has to be checked |
| Speech gate and auto stop | `DictationSpeechGate`, `DictationAutoStop` | `DictationSpeechGateTests`, `DictationPauseDetectorTests` | The same tests, without the composition's | Detector and pause logic ported. Session wiring arrives with the controller |
| Spoken correction in delivery | `DictationCorrections` | `DictationCorrectionTests` | The same tests, without the practice test | Logic ported. A real field still has to be checked |
| Panel, compact indicator and waveform | `DictationPanel`, `DictationCompactIndicator` | `DictationPanelAnchorTests`, `DictationCompactIndicatorTests` | `DictationUITests` | Ported. Its unit tests are still to come |
| Sounds and prewarm | `DictationSoundCue`, `AppServices+DictationPrewarm` | `DictationColdStartTests` | The same tests | Ported. Prewarm is off by default and never downloads |
| Memory: model residency | `AppModelResidencyLedger`, `AppModelIdleReleaseScheduler` | `DictationResourceOwnershipTests`, which asserts sharing in one process and has to be rewritten | | A loaded model is released after 10 idle minutes, or one with the lightweight profile, and under memory pressure |

## Text features and data

| Capability or case | Portavoz source | Portavoz test | Secreteo test | State |
|---|---|---|---|---|
| Modes, recipes and per-app profiles | `DictationTextPreferences`, `DictationTextSettingsModel` | `DictationRecipeTests`, `DictationTextModeDeliveryTests` | `DictationRecipeFidelityTests`, `DictationTextModeDeliveryTests` without Settings | Delivery ported. Settings arrives in P5, and recipes in P6 |
| Polish with Apple Foundation Models and Ollama | `PolishDictation`, `DictationTextPolishers` | `PolishDictationTests`, `DictationPolishRouterTests`, `DictationPolishDeliveryTests` | `PolishDictationTests`, `DictationPolishDeliveryTests`, `DictationPolishRouterTests`, `DictationTextPolisherTests`, `DictationPolishUITests` | Ported without MLX, with its engine and Ollama model in Settings |
| Polish egress consent | `AppServices+DictationPolish`, `Schema+DictationPolish` | `DictationPolishEgressTests`, which has to be rewritten | `DictationPolishEgressTests`, rewritten | Ported. Only loopback, with no journal ([D24](DECISIONS.md#d24-polish-runs-only-on-this-mac-and-keeps-no-journal)) |
| Translate while pasting | `TranslateDictation`, `AppleDictationTranslator` | `TranslateDictationTests`, `DictationTranslationDeliveryTests` | The same tests | Use case and delivery ported. Settings arrives in P6 |
| History, with consent and retention | `DictationHistoryModel`, store | `DictationHistoryStoreTests`, `DictationHistoryRecordingTests` | | Pending, P7 |
| Search | Store | `DictationSearchStoreTests` | | Pending, P7 |
| Statistics | `DictationStatsModel`, store | `DictationStatsStoreTests`, `DictationStatsTests` | | Pending, P7 |
| Read-only MCP | `DictationToolbox` | `DictationToolboxTests`, `DictationAgentAccessStoreTests` | | Pending, P8 |
| Settings: vocabulary, microphone, memory and Polish panels | `DictationSection`, `DictationTextSettingsSection`, `DictationDictionaryEditor` | `SettingsUITests` | `DictationSettingsUITests`, `DictationPreferenceStoreTests` | Triggers, language, microphone, replacements, vocabulary and text mode ported, without vocabulary suggestions from meetings. Memory is ported without its hardware suggestion. Polish is ported with its engine. Recipes are pending |
| Onboarding | `OnboardingDictationStep`, `OnboardingModelPreparation` | `OnboardingUITests`, `OnboardingModelPreparationTests` | `OnboardingUITests`, `OnboardingModelPreparationTests`, `FirstRunOnboardingPolicyTests` | Three steps on first launch: dictation and permissions, the speech model, which is loaded once even when installed, and practice. No meeting steps or voice enrollment |
| Preference import | `PortableSettings` | `PortableSettingsTests` | `PortavozPreferenceImportTests`, `DictationSettingsUITests` | Reads Portavoz's saved settings instead of an exported file. Imports only what Secreteo's Settings shows, after a preview ([G14](GAPS.md#g14-portavoz-settings-left-out-of-the-import)) |
| English and Spanish | `Localizable.xcstrings` | `LocalizationTests` | | Pending, P5 |

## Approved losses

| Capability | Portavoz test | Replacement |
|---|---|---|
| Ask over dictations | `AskDictationsTests`, `AskDictationRetrievalTests` | Agents read history through MCP ([D2](DECISIONS.md#d2-scope-and-approved-losses)) |
| Dictation into meeting notes | `DictationMeetingNoteStoreTests` | Copy and paste |
| Polish with embedded MLX | `DictationTextPolisherTests`, in part | Apple Foundation Models and Ollama |

## Tests that wait for their slice

| Test | Waits for |
|---|---|
| In `DictationOwnershipCoordinatorTests`: `anActivationBeforeLaunchFinishesPublishesNothing`, `turningThePreferenceOnTakesOwnershipFromNobody`, `onlyTheOwnerArmsTheShortcut`, `aWorkspaceChangeIsAHintToLookAgain`, `aHeldTriggerKeepsItsWordsWhenAHandoffDisarmsIt`, `aHeldTriggerStillCancelsWhenItIsDisabledWithNoHandoff` | The composition |
| In `DictationOwnershipCoordinatorTests`: `aSpokenInstructionKeepsItsWordsWhenTheGraceEnds`, `aPreviewGivesUpItsGlobalKeysWhenOwnershipIsLost`, `aPreviewFromBeforeAResetCannotReplace`, `aRewriteReplaceIsRefusedAfterAHandoffThereAndBack`, `aHandoffCompletesWithARewritePreviewOpenAndTheReplaceIsRefused`, `aHandoffThereAndBackWithARewritePreviewOpenRefusesTheReplace`. In `DictationAdmissionTests`: `aRefusedRewriteReadsNothing`, `aRewriteHoldsNoLeaseWhileTheUserDecides`, `aRefusedRewriteLeavesTheOneInProgressAlone`, `aRefusedSpokenInstructionLeavesTheChoicesOpen`, `aCancelledRewriteKeepsItsLeaseUntilTheReadEnds`, `aReplaceHoldsItsLeaseThroughTheClipboardRestore`, `aRefusedReplaceKeepsTheRewriteToCopy` | Rewrite |
| In `DictationAdmissionTests`: `compositionReadsOwnershipForPrewarmAndAdmission` | The composition |
| `DictationHistoryRecordingTests` | The store |
| `DictationSpeechGateCorpusTests` | The benchmark tooling |
| In `DictationReadinessTests`: `testFixtureRecoverySurvivesFreshDependenciesForEachMenuInvocation`, `testAppSettingsWriteRejectsPreparationAndAllowsApplyAfterCancel`, `testLiveCompositionReadsTheInjectedAudioPreference` | The composition |
| In `DictationTextModeDeliveryTests`: `firstEnableAfterAppCompositionStillDeliversLiteral`, `chooserWithoutAnOwnedWindowReportsFailureAndRetiresSelection`, `failedDatabaseAdmissionDoesNotInitializeTextPreferences`, `corruptProfilesStayRecoverableWithoutOverridingGlobalMode`, `settingsMutationsStayBoundedAndTemporary`, `fillerAndReplacementControlsFollowAnyCleanUse`, `rejectedIdentifiersCannotReplaceTheSavedProfile`, `chooserFixtureRequiresAllIsolationConditions` | The composition and Settings |
| In `DictationSpeechGateTests`: `testTurningOnDictationPreparesTheDetectorOnlyWhenTheGateIsOn`, `testDisposableCompositionNeverDownloadsTheDetector` | The composition |
| In `LiveSpeechSelectionTests`: `testTheDefaultUltraNeitherDownloadsNorBlocksDictation`, `testSelectedAppleWithAutomaticLanguageNeverStartsAModelLoad` | The composition |
| In `DictationShortcutTests`: the fixture half of `testNoRegistrarKeepsTemporaryCompositionInert` | The shortcut fixture |
