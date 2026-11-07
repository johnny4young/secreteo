# Provenance

Secreteo starts from a fresh git history ([D10](DECISIONS.md#d10-fresh-git-history)). This file maps each copied file to its origin. Both source projects are MIT, by the same author.

## Dictation code

Copied from an export (`git archive`) of one frozen commit of [`johnny4young/portavoz`](https://github.com/johnny4young/portavoz).

**Frozen commit:** `a957253b0a54eb385a400bed0e80d853a8e8b41a`.

`Sources/DictationStore/DictationSchema.swift` is written anew as one v1 ([D3](DECISIONS.md#d3-history-stats-and-search-are-included)). Its tables follow `Sources/StorageKit/Schema+DictationHistory.swift`, `Schema+DictationSearch.swift`, `Schema+DictationAgentAccess.swift` and `Schema+DictationStats.swift`, with no meeting-note link, and add secure delete.

`scripts/port_diff.py <export>` compares each row with an unpacked export of that commit. `Renames` must match after the renames in that script, and any other row prints its differences for review.

| Secreteo path | Portavoz path | Change |
|---|---|---|
| `Sources/DictationKit/DictationDeliveryOutcome.swift` | `Sources/PortavozCore/DictationDeliveryOutcome.swift` | Renames |
| `Sources/DictationKit/DictationRecipe.swift` | `Sources/PortavozCore/DictationRecipe.swift` | Renames |
| `Sources/DictationKit/DictationTextMode.swift` | `Sources/PortavozCore/DictationTextMode.swift` | Renames |
| `Sources/DictationKit/DictationHistory.swift` | `Sources/PortavozCore/DictationHistory.swift` | Seam: imports `SpeechCore`; no meeting-note types ([D2](DECISIONS.md#d2-scope-and-approved-losses)); a comment no longer names Ask |
| `Sources/DictationKit/DictationStats.swift` | `Sources/PortavozCore/DictationStats.swift` | Seam: imports `SpeechCore` |
| `Sources/DictationKit/DictationAssembler.swift` | `Sources/TranscriptionKit/DictationAssembler.swift` | Renames |
| `Sources/DictationKit/DictationCorrectionCommand.swift` | `Sources/TranscriptionKit/DictationCorrectionCommand.swift` | Renames |
| `Sources/DictationKit/DictationDictionaryTerms.swift` | `Sources/TranscriptionKit/DictationDictionaryTerms.swift` | Renames |
| `Sources/DictationKit/DictationPolishFidelity.swift` | `Sources/TranscriptionKit/DictationPolishFidelity.swift` | Renames |
| `Sources/DictationKit/DictationTextRules.swift` | `Sources/TranscriptionKit/DictationTextRules.swift` | Renames |
| `Sources/SpeechCore/Identifiers.swift` | `Sources/PortavozCore/Identifiers.swift` | Seam: only the four identifiers used so far |
| `Tests/DictationKitTests/DictationDictionaryTermsTests.swift` | `Tests/PortavozKitTests/DictationDictionaryTermsTests.swift` | Renames |
| `Tests/DictationKitTests/DictationPolishFidelityTests.swift` | `Tests/PortavozKitTests/DictationPolishFidelityTests.swift` | Renames |
| `Tests/DictationKitTests/DictationTextRulesTests.swift` | `Tests/PortavozKitTests/DictationTextRulesTests.swift` | Renames |
| `Tests/DictationKitTests/DictationAssemblerTests.swift` | `Tests/PortavozAppTests/DictationTests.swift` | Extract: the tests with no app |
| `Tests/DictationKitTests/DictationCorrectionCommandTests.swift` | `Tests/PortavozAppTests/DictationCorrectionTests.swift` | Extract: the tests with no app |
| `Tests/DictationKitTests/DictationRecipeFidelityTests.swift` | `Tests/PortavozAppTests/DictationRecipeTests.swift` | Extract: the tests with no app |
| `Tests/DictationKitTests/DictationStatsTests.swift` | `Tests/PortavozAppTests/DictationStatsTests.swift` | Extract: the tests with no app |
| `Sources/MicCapture/AudioDeviceCatalog.swift` | `Sources/AudioCaptureKit/AudioDeviceCatalog.swift` | Renames |
| `Sources/MicCapture/Support.swift` | `Sources/AudioCaptureKit/Support.swift` | Renames |
| `Sources/MicCapture/Downmix.swift` | `Sources/AudioCaptureKit/Downmix.swift` | Renames |
| `Sources/MicCapture/CapturePCMGeometry.swift` | `Sources/AudioCaptureKit/CapturePCMGeometry.swift` | Renames |
| `Sources/MicCapture/CaptureDeliveryBuffer.swift` | `Sources/AudioCaptureKit/CaptureDeliveryBuffer.swift` | Renames |
| `Sources/MicCapture/AudioCaptureSource.swift` | `Sources/AudioCaptureKit/AudioCaptureSource.swift` | Seam: no `AudioRetentionPolicy`, which only meetings use |
| `Sources/MicCapture/MicrophoneSource.swift` | `Sources/AudioCaptureKit/MicrophoneSource.swift` | Seam: queue label and two comments name Secreteo |
| `Sources/MicCapture/MicrophonePermissionClient.swift` | `Sources/PlatformKit/MicrophonePermissionClient.swift` | Renames |
| `Sources/SpeechCore/CaptureReport.swift` | `Sources/PortavozCore/CaptureReport.swift` | Renames |
| `Sources/SpeechCore/StreamingLinearResampler.swift` | `Sources/PortavozCore/StreamingLinearResampler.swift` | Renames |
| `Sources/SpeechCore/AudioTypes.swift` | `Sources/PortavozCore/AudioTypes.swift` | Seam: a comment about meeting channels is removed |
| `Tests/MicCaptureTests/MicrophoneTapTransitionTests.swift` | `Tests/PortavozKitTests/MicrophoneTapTransitionTests.swift` | Renames |
| `Tests/MicCaptureTests/MicrophonePermissionClientTests.swift` | `Tests/PortavozKitTests/MicrophonePermissionClientTests.swift` | Renames |
| `Tests/MicCaptureTests/StreamingLinearResamplerTests.swift` | `Tests/PortavozKitTests/StreamingLinearResamplerTests.swift` | Renames |
| `Tests/MicCaptureTests/CaptureDeliveryBufferTests.swift` | `Tests/PortavozKitTests/CaptureDeliveryBufferTests.swift` | Extract: all but the recording session test |
| `Tests/MicCaptureTests/LinearResamplerTests.swift` | `Tests/PortavozKitTests/LinearResamplerTests.swift` | Renames |
| `Tests/MicCaptureTests/CapturePCMGeometryTests.swift` | `Tests/PortavozKitTests/CapturePCMGeometryTests.swift` | Extract: all but the file writer test |
| `Tests/MicCaptureTests/AudioCaptureTests.swift` | `Tests/PortavozKitTests/AudioCaptureTests.swift` | Extract: format, route and downmix tests |
| `Sources/LiveSpeech/ParakeetSegmentMapper.swift` | `Sources/TranscriptionKit/ParakeetSegmentMapper.swift` | Renames |
| `Sources/LiveSpeech/ParakeetTokenRevisionReducer.swift` | `Sources/TranscriptionKit/ParakeetTokenRevisionReducer.swift` | Renames |
| `Sources/LiveSpeech/ParakeetLiveWorkProbe.swift` | `Sources/TranscriptionKit/ParakeetLiveWorkProbe.swift` | Renames |
| `Sources/LiveSpeech/CaptionCoalescer.swift` | `Sources/TranscriptionKit/CaptionCoalescer.swift` | Renames |
| `Sources/LiveSpeech/MicBleedFilter.swift` | `Sources/TranscriptionKit/MicBleedFilter.swift` | Renames |
| `Sources/LiveSpeech/TranscriptionTextFilter.swift` | `Sources/TranscriptionKit/TranscriptionTextFilter.swift` | Renames |
| `Sources/LiveSpeech/SpeechAnalyzerLiveEngine.swift` | `Sources/TranscriptionKit/SpeechAnalyzerLiveEngine.swift` | Renames |
| `Sources/LiveSpeech/SpeechAnalyzerEngine.swift` | `Sources/TranscriptionKit/SpeechAnalyzerEngine.swift` | Renames |
| `Sources/LiveSpeech/BoundedLiveAudioFeeds.swift` | `Sources/TranscriptionKit/BoundedLiveAudioFeeds.swift` | Renames |
| `Sources/LiveSpeech/SpokenLanguageDetector.swift` | `Sources/TranscriptionKit/SpokenLanguageDetector.swift` | Renames |
| `Sources/LiveSpeech/VocabularyPrompt.swift` | `Sources/TranscriptionKit/VocabularyPrompt.swift` | Renames |
| `Sources/LiveSpeech/TranscriptionEngine.swift` | `Sources/TranscriptionKit/TranscriptionEngine.swift` | Renames |
| `Sources/LiveSpeech/FileTranscription.swift` | `Sources/TranscriptionKit/FileTranscription.swift` | Renames |
| `Sources/LiveSpeech/ParakeetEngine.swift` | `Sources/TranscriptionKit/ParakeetEngine.swift` | Seam: loads through `LocalModelStore`, with v3 named directly instead of a routing table, and takes seeds |
| `Sources/LiveSpeech/SileroVoiceActivityDetector.swift` | `Sources/TranscriptionKit/SileroVoiceActivityDetector.swift` | Seam: loads through `LocalModelStore` |
| `Sources/LiveSpeech/ModelCatalog.swift` | `Sources/ModelStoreKit/ModelRegistry.swift` | Extract: the Parakeet v3 pin as a `ModelManifest`, with no task or folder name |
| `Sources/LiveSpeech/ModelCatalog+ParakeetUltra.swift` | `Sources/ModelStoreKit/ModelCatalog+ParakeetUltra.swift` | Seam: a `ModelManifest`, with no task or folder name |
| `Sources/LiveSpeech/ModelCatalog+SileroVAD.swift` | `Sources/ModelStoreKit/ModelCatalog+SileroVAD.swift` | Seam: a `ModelManifest`, with no task or folder name |
| `Sources/SpeechCore/TranscriptTypes.swift` | `Sources/PortavozCore/TranscriptTypes.swift` | Renames |
| `Sources/SpeechCore/LanguagePolicy.swift` | `Sources/PortavozCore/LanguagePolicy.swift` | Renames |
| `Sources/SpeechCore/TranscriptContentPolicy.swift` | `Sources/PortavozCore/TranscriptContentPolicy.swift` | Renames |
| `Tests/LiveSpeechTests/CaptionCoalescerTests.swift` | `Tests/PortavozKitTests/CaptionCoalescerTests.swift` | Renames |
| `Tests/LiveSpeechTests/CaptionCoalescerTokenModeTests.swift` | `Tests/PortavozKitTests/CaptionCoalescerTokenModeTests.swift` | Renames |
| `Tests/LiveSpeechTests/ParakeetLanguageConfigurationTests.swift` | `Tests/PortavozKitTests/ParakeetLanguageConfigurationTests.swift` | Renames |
| `Tests/LiveSpeechTests/ParakeetTokenRevisionReducerTests.swift` | `Tests/PortavozKitTests/ParakeetTokenRevisionReducerTests.swift` | Renames |
| `Tests/LiveSpeechTests/ParakeetAudioChunkTests.swift` | `Tests/PortavozKitTests/ParakeetAudioChunkTests.swift` | Renames |
| `Tests/LiveSpeechTests/ParakeetLiveWorkProbeTests.swift` | `Tests/PortavozKitTests/ParakeetLiveWorkProbeTests.swift` | Renames |
| `Tests/LiveSpeechTests/SpeechAnalyzerLiveEngineTests.swift` | `Tests/PortavozKitTests/SpeechAnalyzerLiveEngineTests.swift` | Renames |
| `Tests/LiveSpeechTests/SpeechAnalyzerLifetimeTests.swift` | `Tests/PortavozKitTests/SpeechAnalyzerLifetimeTests.swift` | Renames |
| `Tests/LiveSpeechTests/ParakeetIntegrationTests.swift` | `Tests/PortavozKitTests/ParakeetIntegrationTests.swift` | Seam: an explicit scratch store from `SECRETEO_MODEL_ROOT` |
| `Tests/LiveSpeechTests/SileroVoiceActivityDetectorTests.swift` | `Tests/PortavozKitTests/SileroVoiceActivityDetectorTests.swift` | Seam: an explicit scratch store |
| `Tests/LiveSpeechTests/TranscriptionTests.swift` | `Tests/PortavozAppTests/TranscriptionTests.swift` | Extract: the engine tests, without the catalog, store and Whisper ones |
| `Tests/LiveSpeechTests/ModelCatalogTests.swift` | `Tests/PortavozAppTests/TranscriptionTests.swift` | Extract: the three pins, without task or folder name checks |
| `Tests/LiveSpeechTests/ParakeetSegmentMapper+LiveStream.swift` | `Tests/PortavozAppTests/DictationVendorProbe.swift` | Extract: the mapper test helper |
| `Sources/DictationSession/Delivery/CapturedDictationDestination.swift` | `Sources/portavoz-app/CapturedDictationDestination.swift` | Renames |
| `Sources/DictationSession/Delivery/DictationCaretCase.swift` | `Sources/portavoz-app/DictationCaretCase.swift` | Seam: a sentence start keeps protected and mixed-case spellings |
| `Sources/DictationSession/Delivery/DictationCaretJoin.swift` | `Sources/portavoz-app/DictationCaretJoin.swift` | Renames |
| `Sources/DictationSession/Delivery/DictationClipboard.swift` | `Sources/portavoz-app/DictationClipboard.swift` | Seam: a late copy still restores, a borrow is refused during a copy, and an overdue restore outlasts a mutation |
| `Sources/DictationSession/Delivery/DictationInsertion.swift` | `Sources/portavoz-app/DictationInsertion.swift` | Seam: a correction range is checked before the field is touched |
| `Sources/DictationSession/Delivery/DictationTextReadback+Accessibility.swift` | `Sources/portavoz-app/DictationTextReadback+Accessibility.swift` | Renames |
| `Sources/DictationSession/Delivery/DictationTextReadback.swift` | `Sources/portavoz-app/DictationTextReadback.swift` | Renames |
| `Sources/DictationSession/Delivery/PasteboardSnapshot.swift` | `Sources/portavoz-app/PasteboardSnapshot.swift` | Renames |
| `Sources/DictationSession/Delivery/TextInserter.swift` | `Sources/portavoz-app/TextInserter.swift` | Seam: layouts match by exact name, and the copy event runs on the main actor |
| `Tests/DictationSessionTests/Delivery/DictationClipboardBoundaryTests.swift` | `Tests/PortavozAppTests/DictationClipboardBoundaryTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Delivery/DictationClipboardInsertionTests.swift` | `Tests/PortavozAppTests/DictationClipboardInsertionTests.swift` | Renames |
| `Tests/DictationSessionTests/Delivery/DictationCaretCaseTests.swift` | `Tests/PortavozAppTests/DictationCaretCaseTests.swift` | Renames |
| `Tests/DictationSessionTests/Delivery/DictationCaretJoinTests.swift` | `Tests/PortavozAppTests/DictationCaretJoinTests.swift` | Renames |
| `Tests/DictationSessionTests/Delivery/TextInsertionReadbackTests.swift` | `Tests/PortavozAppTests/TextInsertionReadbackTests.swift` | Renames |
| `Tests/DictationSessionTests/Delivery/TextInsertionTargetTests.swift` | `Tests/PortavozAppTests/TextInsertionTargetTests.swift` | Renames |
| `Tests/DictationSessionTests/Support/TestPolling.swift` | `Tests/PortavozTestSupport/TestPolling.swift` | Renames |
| `Tests/DictationSessionTests/Support/ControlledTestSleep.swift` | `Tests/PortavozTestSupport/ControlledTestSleep.swift` | Renames |
| `Sources/DictationSession/AppLanguage.swift` | `Sources/portavoz-app/AppLanguage.swift` | Extract: without the view modifier, which arrives with Settings |
| `Sources/DictationSession/DictationAutoStop.swift` | `Sources/portavoz-app/DictationAutoStop.swift` | Seam: imports `LiveSpeech`, uses `LocalModelStore` |
| `Sources/DictationSession/DictationCaptureOwnership.swift` | `Sources/portavoz-app/DictationCaptureOwnership.swift` | Renames |
| `Sources/DictationSession/DictationCapturePolicy.swift` | `Sources/portavoz-app/DictationCapturePolicy.swift` | Seam: imports `SpeechCore` |
| `Sources/DictationSession/DictationCorrections.swift` | `Sources/portavoz-app/DictationCorrections.swift` | Renames |
| `Sources/DictationSession/DictationFeedbackTimer.swift` | `Sources/portavoz-app/DictationFeedbackTimer.swift` | Renames |
| `Sources/DictationSession/DictationLastText.swift` | `Sources/portavoz-app/DictationLastText.swift` | Seam: expired text leaves memory on time, and a clear notifies its owner |
| `Sources/DictationSession/DictationMicrophoneReadiness.swift` | `Sources/portavoz-app/DictationMicrophoneReadiness.swift` | Seam: imports `SpeechCore` |
| `Sources/DictationSession/DictationPauseDetector.swift` | `Sources/portavoz-app/DictationPauseDetector.swift` | Seam: imports `SpeechCore` |
| `Sources/DictationSession/DictationRuntimeAcquisition.swift` | `Sources/portavoz-app/DictationRuntimeAcquisition.swift` | Renames |
| `Sources/DictationSession/DictationSessionMeasurement.swift` | `Sources/portavoz-app/DictationSessionMeasurement.swift` | Seam: imports `SpeechCore` |
| `Sources/DictationSession/DictationSoundCue.swift` | `Sources/portavoz-app/DictationSoundCue.swift` | Renames |
| `Sources/DictationSession/DictationSpeechGate.swift` | `Sources/portavoz-app/DictationSpeechGate.swift` | Seam: imports `SpeechCore` |
| `Sources/DictationSession/DictationTranscriptProjection.swift` | `Sources/portavoz-app/DictationTranscriptProjection.swift` | Seam: imports `SpeechCore` and `LiveSpeech` |
| `Sources/DictationSession/L10n.swift` | `Sources/portavoz-app/L10n.swift` | Renames |
| `Sources/DictationSession/LiveSpeechSelection.swift` | `Sources/portavoz-app/LiveSpeechSelection.swift` | Seam: imports `LiveSpeech`, dictation only with no meeting lane |
| `Sources/DictationSession/MicrophoneInputSelection.swift` | `Sources/portavoz-app/MicrophoneInputSelection.swift` | Renames |
| `Sources/DictationSession/LiveTranscriptionRuntime.swift` | `Sources/portavoz-app/LiveTranscriptionAttacher.swift` | Extract: only the runtime handle, the attacher is meeting code |
| `Sources/DictationSession/DictationSpeechGate+Silero.swift` | `Sources/portavoz-app/AppServices+DictationSpeechGate.swift` | Extract: the gate rules, with `LocalModelStore` |
| `Tests/DictationSessionTests/DictationPauseDetectorTests.swift` | `Tests/PortavozAppTests/DictationPauseDetectorTests.swift` | Seam: imports `SpeechCore` |
| `Tests/DictationSessionTests/DictationSpeechGateTests.swift` | `Tests/PortavozAppTests/DictationSpeechGateTests.swift` | Extract: without the tests of the composition, which arrive with it |
| `Tests/DictationSessionTests/DictationTranscriptProjectionTests.swift` | `Tests/PortavozAppTests/DictationTranscriptProjectionTests.swift` | Seam: imports `LiveSpeech` and `SpeechCore` |
| `Tests/DictationSessionTests/LiveSpeechSelectionTests.swift` | `Tests/PortavozAppTests/LiveSpeechSelectionTests.swift` | Extract: the dictation preference, routing arrives with the composition |
| `Sources/DictationSession/Triggers/DictationShortcut.swift` | `Sources/portavoz-app/DictationShortcut.swift` | Seam: `pause()`, which frees the combination while the recorder listens |
| `Sources/DictationSession/Triggers/GlobalHotkey.swift` | `Sources/portavoz-app/GlobalHotkey.swift` | Renames |
| `Sources/DictationSession/Triggers/HotkeySetting.swift` | `Sources/portavoz-app/HotkeySetting.swift` | Seam: its own default shortcut, and without the recorder view, which is in `Settings/HotkeyRecorder.swift` |
| `Sources/DictationSession/Triggers/HotkeySetting+Labels.swift` | `Sources/portavoz-app/HotkeySetting+Labels.swift` | Renames |
| `Sources/DictationSession/Triggers/ModifierKeyPTT.swift` | `Sources/portavoz-app/ModifierKeyPTT.swift` | Renames |
| `Sources/DictationSession/Triggers/MouseButtonPTT.swift` | `Sources/portavoz-app/MouseButtonPTT.swift` | Seam: a lost tap ends a hold, and without the recorder view, which is in `Settings/MouseButtonRecorder.swift` |
| `Sources/DictationSession/Triggers/MousePTTGesture.swift` | `Sources/portavoz-app/MousePTTGesture.swift` | Seam: adds the hold tracker |
| `Tests/DictationSessionTests/Triggers/GlobalHotkeyRoutingTests.swift` | `Tests/PortavozAppTests/GlobalHotkeyRoutingTests.swift` | Renames |
| `Tests/DictationSessionTests/Triggers/DictationShortcutTests.swift` | `Tests/PortavozAppTests/DictationShortcutTests.swift` | Extract: without the test of the UI fixture, which arrives with it |
| `Tests/DictationSessionTests/Triggers/HotkeySettingTests.swift` | `Tests/PortavozAppTests/HotkeySettingTests.swift` | Renames |
| `Tests/DictationSessionTests/Triggers/ModifierKeyGestureTests.swift` | `Tests/PortavozAppTests/ModifierKeyGestureTests.swift` | Renames |
| `Tests/DictationSessionTests/Triggers/MousePTTGestureTests.swift` | `Tests/PortavozAppTests/MousePTTGestureTests.swift` | Renames |
| `Sources/DictationSession/DictationController.swift` | `Sources/portavoz-app/DictationController.swift` | Seam: imports the split targets, messages that named Portavoz's engine and panels are rewritten, and the panel is a placeholder for now. Fixes: a cancelled session corrects nothing, an old transform keeps its hands off a new Escape key, a capture failure keeps the words, expired words leave its state, a closed notice frees Paste last, and Paste last says whether it sent anything |
| `Sources/DictationSession/DictationController+History.swift` | `Sources/portavoz-app/DictationController+History.swift` | Seam: imports the split targets, and the draft can be forgotten |
| `Sources/DictationSession/DictationController+Hotkey.swift` | `Sources/portavoz-app/DictationController+Hotkey.swift` | Renames |
| `Sources/DictationSession/DictationController+ModifierKey.swift` | `Sources/portavoz-app/DictationController+ModifierKey.swift` | Renames |
| `Sources/DictationSession/DictationController+Ownership.swift` | `Sources/portavoz-app/DictationController+Ownership.swift` | Renames |
| `Sources/DictationSession/DictationController+PasteLast.swift` | `Sources/portavoz-app/DictationController+PasteLast.swift` | Seam: paste chooses its text by the kind of session, in `DictationController.swift` |
| `Sources/DictationSession/DictationController+Stats.swift` | `Sources/portavoz-app/DictationController+Stats.swift` | Seam: imports the split targets |
| `Sources/DictationSession/DictationSessionDependencies.swift` | `Sources/portavoz-app/DictationSessionDependencies.swift` | Seam: imports the split targets, and caret case reads the injected defaults |
| `Sources/DictationSession/DictationAdmission.swift` | `Sources/portavoz-app/DictationAdmission.swift` | Extract: the port and lease, the composition stays out |
| `Sources/DictationSession/DictationTextPreferences.swift` | `Sources/portavoz-app/DictationTextPreferences.swift` | Seam: imports the split targets |
| `Sources/DictationSession/Panel/DictationPanelAnchor.swift` | `Sources/portavoz-app/DictationPanelAnchor.swift` | Renames |
| `Sources/DictationSession/AppleDictationTranslator.swift` | `Sources/portavoz-app/AppleDictationTranslator.swift` | Seam: imports the split targets |
| `Sources/DictationKit/DictationTextPolishing.swift` | `Sources/IntelligenceKit/DictationTextPolishing.swift` | Renames |
| `Sources/DictationKit/PolishDictation.swift` | `Sources/ApplicationKit/PolishDictation.swift` | Seam: imports the split targets |
| `Sources/DictationKit/TranslateDictation.swift` | `Sources/ApplicationKit/TranslateDictation.swift` | Renames |
| `Sources/Polish/DictationPolishPrompt.swift` | `Sources/IntelligenceKit/DictationPolishPrompt.swift` | Renames |
| `Sources/Polish/ReasoningEnvelope.swift` | `Sources/IntelligenceKit/ReasoningEnvelope.swift` | Renames |
| `Sources/Polish/GenerationOptions+Greedy.swift` | `Sources/IntelligenceKit/GenerationOptions+Greedy.swift` | Seam: a comment no longer names the source app |
| `Sources/Polish/OpenAICompatibleChatCodec.swift` | `Sources/IntelligenceKit/BYOK.swift` | Extract: the chat codec, with an error of its own and no answer-only parse |
| `Sources/Polish/OllamaService.swift` | `Sources/IntelligenceKit/OllamaService.swift` | Extract: the endpoint, the model list, which tells a silent Ollama from one with no models, and the Polish client |
| `Sources/Polish/DictationTextPolishers.swift` | `Sources/IntelligenceKit/DictationTextPolishers.swift` | Seam: imports `DictationKit`, no MLX, no scheduler, and metadata with no meeting, operation or consent fields |
| `Sources/Polish/FoundationModelsAvailability.swift` | `Sources/IntelligenceKit/FoundationModelSummaryProvider.swift` | Extract: the availability check and its reasons |
| `Sources/Polish/DataEgress.swift` | `Sources/PortavozCore/DataEgress.swift` | Extract: destination scope, provider disclosure, request, response, error and port, for Polish only |
| `Sources/Polish/URLSessionDataEgressGateway.swift` | `Sources/IntegrationsKit/URLSessionDataEgressGateway.swift` | Extract: the Polish validation and transport, with no receipt journal ([D24](DECISIONS.md#d24-polish-runs-only-on-this-mac-and-keeps-no-journal)) |
| `Sources/DictationSession/FoundationModelsCapability.swift` | `Sources/portavoz-app/FoundationModelsCapability.swift` | Seam: the fallback engine is Ollama instead of MLX |
| `Sources/DictationSession/DictationPolishRouter.swift` | `Sources/portavoz-app/AppServices+DictationPolish.swift` | Seam: two engines with Polish's own preference keys, messages point at Settings, and no MLX or resource governor |
| `Tests/PolishTests/DictationPolishPromptTests.swift` | `Tests/PortavozKitTests/DictationPolishPromptTests.swift` | Renames |
| `Tests/PolishTests/OllamaChatTests.swift` | `Tests/PortavozKitTests/IntelligenceTests.swift` | Extract: the chat codec, Ollama model list and reasoning tests, on a loopback endpoint |
| `Tests/PolishTests/DataEgressGatewayTestDoubles.swift` | `Tests/PortavozTestSupport/DataEgressGatewayTestDoubles.swift` | Extract: the capturing gateway |
| `Tests/PolishTests/DictationTextPolisherTests.swift` | `Tests/PortavozKitTests/DictationTextPolisherTests.swift` | Extract: without the MLX tests |
| `Tests/PolishTests/DictationPolishEgressTests.swift` | `Tests/PortavozKitTests/DictationPolishEgressTests.swift` | Extract: the gateway tests, rewritten for one operation with no store or journal |
| `Tests/DictationSessionTests/Session/DictationPolishRouterTests.swift` | `Tests/PortavozAppTests/DictationPolishRouterTests.swift` | Extract: without the MLX tests, plus the default engine |
| `Sources/DictationSession/Settings/DictationTextSettingsModel.swift` | `Sources/portavoz-app/DictationTextSettingsModel.swift` | Seam: `reload()`, for an import that writes the same keys |
| `Sources/DictationSession/Settings/DictationRecipeSettings.swift` | `Sources/portavoz-app/DictationRecipeSettings.swift` | Seam: no helper text, the instruction field named instead of asked about, labels in title case, and row identifiers joined from a prefix |
| `Sources/DictationSession/Settings/DictationTranslationSettings.swift` | `Sources/portavoz-app/DictationTranslationSettings.swift` | Seam: a status and the download only when translation is on and needs them, and the label in title case |
| `Tests/DictationSessionTests/Session/DictationRecipePreferenceTests.swift` | `Tests/PortavozAppTests/DictationRecipeTests.swift` | Extract: the preference and Settings tests, guarded like the other suites that read the argument domain |
| `Tests/PolishTests/DictationRecipePromptTests.swift` | `Tests/PortavozAppTests/DictationRecipeTests.swift` | Extract: the prompt tests |
| `Sources/DictationSession/Rewrite/SelectionRewriteController.swift` | `Sources/portavoz-app/SelectionRewriteController.swift` | Seam: imports the split targets, and two messages name the rewrite and the model instead of the summary engine |
| `Sources/DictationSession/Rewrite/SelectionCapture.swift` | `Sources/portavoz-app/SelectionCapture.swift` | Seam: imports the split targets |
| `Sources/DictationSession/Rewrite/SelectionRewritePanel.swift` | `Sources/portavoz-app/SelectionRewritePanel.swift` | Seam: imports the split targets, no helper text, and recipe identifiers joined from a prefix |
| `Sources/DictationSession/Rewrite/DictationFeature+SelectionRewrite.swift` | `Sources/portavoz-app/AppServices+SelectionRewrite.swift` | Seam: the feature instead of the app's services, the shortcut as a `HotkeySetting` through the injectable registrar, and its Settings binding |
| `Tests/DictationSessionTests/Session/SelectionRewriteTests.swift` | `Tests/PortavozAppTests/SelectionRewriteTests.swift` | Seam: imports the split targets |
| `Tests/SecreteoUITests/SelectionRewriteUITests.swift` | `Tests/PortavozUITests/SelectionRewriteUITests.swift` | Seam: assertions for choosing again, cancelling and the spoken instruction |
| `Sources/DictationSession/Settings/DictationFeature+TextProfiles.swift` | `Sources/portavoz-app/AppServices+DictationTextProfiles.swift` | Seam: the feature instead of the app's services, and no message in the chooser |
| `Sources/DictationSession/Settings/DictationProfileSettings.swift` | `Sources/portavoz-app/DictationTextSettingsSection.swift` | Extract: the application profiles, without the privacy note, labels in title case, and row identifiers joined from a prefix |
| `Sources/DictationSession/Fixtures/DictationProfilePickerUITestFixture.swift` | `Sources/portavoz-app/AppServices+DictationTextProfileUITestFixture.swift` | Renames |
| `Sources/DictationSession/Fixtures/DictationUITestFixture.swift` | `Sources/portavoz-app/AppServices+DictationUITestFixture.swift` | Extract: without the composition extension |
| `Sources/DictationSession/Fixtures/DictationNativeUITestFixture.swift` | `Sources/portavoz-app/AppServices+DictationNativeUITestFixture.swift` | Seam: a line wrapped for the longer identifier |
| `Sources/DictationSession/Fixtures/DictationNativeControllerUITestFixture.swift` | `Sources/portavoz-app/AppServices+DictationNativeControllerUITestFixture.swift` | Renames |
| `Tests/DictationSessionTests/Session/DictationControllerTests.swift` | `Tests/PortavozAppTests/DictationControllerTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationSessionLifecycleTests.swift` | `Tests/PortavozAppTests/DictationSessionLifecycleTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationDeliveryOutcomeTests.swift` | `Tests/PortavozAppTests/DictationDeliveryOutcomeTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationDeliveryPhaseTests.swift` | `Tests/PortavozAppTests/DictationDeliveryPhaseTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationStreamingProjectionTests.swift` | `Tests/PortavozAppTests/DictationStreamingProjectionTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationPasteLastTests.swift` | `Tests/PortavozAppTests/DictationPasteLastTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationSpeechGateDeliveryTests.swift` | `Tests/PortavozAppTests/DictationSpeechGateDeliveryTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationSessionMeasurementTests.swift` | `Tests/PortavozAppTests/DictationSessionMeasurementTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationModifierOwnershipTests.swift` | `Tests/PortavozAppTests/DictationModifierOwnershipTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationPolishDeliveryTests.swift` | `Tests/PortavozAppTests/DictationPolishDeliveryTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationTranslationDeliveryTests.swift` | `Tests/PortavozAppTests/DictationTranslationDeliveryTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationTextModeDeliveryTests+NativeController.swift` | `Tests/PortavozAppTests/DictationTextModeDeliveryTests+NativeController.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/DictationCorrectionTests.swift` | `Tests/PortavozAppTests/DictationCorrectionTests.swift` | Extract: without the practice test, which arrives with Practice |
| `Tests/DictationSessionTests/Session/DictationColdStartTests.swift` | `Tests/PortavozAppTests/DictationColdStartTests.swift` | Extract: without the prewarm tests, which arrive with the composition |
| `Tests/DictationSessionTests/Session/DictationReadinessTests.swift` | `Tests/PortavozAppTests/DictationReadinessTests.swift` | Extract: without the tests of the composition, which arrive with it |
| `Tests/DictationSessionTests/Session/DictationTextModeDeliveryTests.swift` | `Tests/PortavozAppTests/DictationTextModeDeliveryTests.swift` | Extract: without the composition tests, which arrive with it. The chooser test builds the feature instead of the app's services |
| `Tests/DictationSessionTests/Delivery/DictationDestinationRecoveryTests.swift` | `Tests/PortavozAppTests/DictationDestinationRecoveryTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/DictationAutoStopTests.swift` | `Tests/PortavozAppTests/DictationAutoStopTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Session/TranslateDictationTests.swift` | `Tests/PortavozKitTests/TranslateDictationTests.swift` | Seam: imports the split targets |
| `Tests/DictationKitTests/PolishDictationTests.swift` | `Tests/PortavozKitTests/PolishDictationTests.swift` | Seam: imports the split targets |
| `Tests/DictationSessionTests/Support/ExclusiveArgumentDomain.swift` | `Tests/PortavozAppTests/ExclusiveArgumentDomain.swift` | Renames |
| `Tests/DictationSessionTests/Support/DictationAdmission+Testing.swift` | `Tests/PortavozAppTests/DictationAdmissionTests.swift` | Extract: only the admission helpers |
| `Sources/DictationSession/DictationOwnershipCoordinator.swift` | `Sources/portavoz-app/DictationOwnershipCoordinator.swift` | Seam: the legacy peers are the other app's builds, not this app's, this app never claims at first run, the user can take ownership and hear why it failed, readiness comes from the composition, a busy turn off retries, and a corrupt file can be seeded and reset |
| `Tests/DictationSessionTests/Session/DictationOwnershipCoordinatorTests.swift` | `Tests/PortavozAppTests/DictationOwnershipCoordinatorTests.swift` | Extract: without the composition and practice cases, which arrive with them. The first run test is inverted, because only Portavoz claims |
| `Tests/DictationSessionTests/Session/DictationAdmissionTests.swift` | `Tests/PortavozAppTests/DictationAdmissionTests.swift` | Extract: without the composition and practice cases, which arrive with them |
| `Sources/DictationSession/Panel/DictationPanel.swift` | `Sources/portavoz-app/DictationPanel.swift` | Seam: two comments lose the source's internal identifiers |
| `Sources/DictationSession/Panel/DictationCompactIndicator.swift` | `Sources/portavoz-app/DictationCompactIndicator.swift` | Renames |
| `Sources/DictationSession/Panel/DictationCopyStatusLabel.swift` | `Sources/portavoz-app/DictationCopyStatusLabel.swift` | Renames |
| `Sources/DictationSession/Panel/DictationNoSpeechView.swift` | `Sources/portavoz-app/DictationNoSpeechView.swift` | Renames |
| `Sources/DictationSession/Panel/DictationPanelTranscript.swift` | `Sources/portavoz-app/DictationPanelTranscript.swift` | Renames |
| `Sources/DictationSession/Panel/DictationRecoveryView.swift` | `Sources/portavoz-app/DictationRecoveryView.swift` | Renames |
| `Sources/DictationSession/Panel/DictationUnverifiedDeliveryView.swift` | `Sources/portavoz-app/DictationUnverifiedDeliveryView.swift` | Renames |
| `Sources/DictationSession/Panel/DictationWaveform.swift` | `Sources/portavoz-app/DictationWaveform.swift` | Renames |
| `Sources/DictationSession/Panel/DictationTextPickers.swift` | `Sources/portavoz-app/DictationTextSettingsSection.swift` | Extract: the two pickers the panel uses |
| `Sources/DictationSession/Settings/DictationSettingsControls.swift` | `Sources/portavoz-app/DictationSection.swift` | Seam: the controls and labels that have behavior here, grouped anew, with no helper text, and the microphone picker from `AudioSection.swift` |
| `Sources/DictationSession/Settings/DictationVocabularyEditor.swift` | `Sources/portavoz-app/SettingsView.swift` | Extract: the vocabulary list and add field, with no suggestions from meetings |
| `Sources/DictationSession/Settings/HotkeyRecorder.swift` | `Sources/portavoz-app/HotkeySetting.swift` | Extract: the recorder view, which hands the setting back instead of saving it and frees the shortcut while listening |
| `Sources/DictationSession/Settings/MouseButtonRecorder.swift` | `Sources/portavoz-app/MouseButtonPTT.swift` | Extract: the recorder view, which hands the button back instead of saving it |
| `Sources/DictationSession/Settings/DictationShortcutSettings.swift` | `Sources/portavoz-app/DictationShortcutSettings.swift` | Seam: no helper text, and saving goes through the caller |
| `Sources/DictationSession/DictationPracticeField.swift` | `Sources/portavoz-app/DictationPracticeField.swift` | Seam: tells its owner when the words go. Fixes: practice words no longer replace the last dictation |
| `Sources/DictationSession/Settings/DictationPracticeView.swift` | `Sources/portavoz-app/DictationPracticeView.swift` | Seam: reads the feature, literal identifiers per surface instead of a prefix, no helper text, no model preparation, which Settings and onboarding already offer, and the window rather than the row holds the field |
| `Tests/DictationSessionTests/Session/DictationPracticeFieldTests.swift` | `Tests/PortavozAppTests/DictationPracticeFieldTests.swift` | Seam: builds the feature instead of the app's services |
| `Tests/SecreteoUITests/DictationPracticeUITests.swift` | `Tests/PortavozUITests/DictationPracticeUITests.swift` | Seam: the Settings journey only, and closing the window forgets the words |
| `Sources/AppUI/FirstRunOnboarding.swift` | `Sources/ApplicationKit/FirstRunOnboarding.swift` | Seam: no meeting library, so no decision to remember |
| `Sources/DictationSession/Onboarding/OnboardingModelPreparation.swift` | `Sources/portavoz-app/OnboardingModelPreparation.swift` | Seam: classifies `LocalModelStore` errors, and `DictationFeature` owns the loads |
| `Sources/DictationSession/Onboarding/OnboardingDictationStep.swift` | `Sources/portavoz-app/OnboardingDictationStep.swift` | Seam: binds through the feature, adds the microphone row, no helper text, and the practice field and Parakeet Ultra offer are not on this step |
| `Sources/DictationSession/Onboarding/OnboardingView.swift` | `Sources/portavoz-app/OnboardingView.swift` | Extract: the frame, footer, model preparation and its status, around the three dictation steps |
| `Tests/DictationSessionTests/Session/OnboardingModelPreparationTests.swift` | `Tests/PortavozAppTests/OnboardingModelPreparationTests.swift` | Seam: `LocalModelStore` errors, plus a busy store and a missing model |
| `Tests/SecreteoUITests/OnboardingUITests.swift` | `Tests/PortavozUITests/OnboardingUITests.swift` | Extract: the model recovery journey, with the dictation steps, Skip, permissions and practice |
| `Sources/DictationSession/Triggers/PasteLastShortcut.swift` | `Sources/portavoz-app/AppServices+PasteLastDictation.swift` | Extract: the key and its default, as a `HotkeySetting`. The registration is in `DictationFeature.swift`, frees the key while a shortcut is being recorded, and is injectable |
| `Sources/DictationSession/Intents/DictationIntents.swift` | `Sources/portavoz-app/PortavozAppIntents.swift` | Extract: Dictate, Paste last and their bridge, which calls one handler instead of posting. Refusals name ownership, unavailability and Accessibility apart. Search and Open dictations wait for the history |
| `Sources/DictationSession/Intents/AppServices+DictationIntents.swift` | `Sources/portavoz-app/PortavozAppDelegate.swift` | Extract: the intent outcome, on the controller with the shortcut's dependencies and admission. The feature answers instead of the delegate, a paste in recovery is allowed like the menu's, and a paste that sent nothing says why |
| `Tests/DictationSessionTests/Triggers/DictationIntentTests.swift` | `Tests/PortavozAppTests/DictationIntentTests.swift` | Extract: the dictation and paste tests, plus refusals by ownership |
| `Sources/DictationSession/DictationModelMemory.swift` | `Sources/portavoz-app/AppServices+DictationPrewarm.swift` | Extract: the prewarm policy, and the profile and dictation's idle delays from `AppModelMemoryPreferences.swift` and `AppModelIdleReleaseScheduler.swift` |
| `Sources/DictationSession/Settings/DictationDictionaryEditor.swift` | `Sources/portavoz-app/DictationDictionaryEditor.swift` | Seam: its text comes through a binding, and imports `DictationKit` |
| `Sources/DictationSession/Panel/DictationPanelSupport.swift` | `Sources/portavoz-app/PVDesign.swift` | Extract: the accent, three symbols, and the locale modifier from `AppLanguage` |
| `Sources/DictationSession/Fixtures/UITestDefaults.swift` | `Sources/portavoz-app/UITestDefaults.swift` | Renames |
| `Tests/SecreteoUITests/DictationUITests.swift` | `Tests/PortavozUITests/DictationUITests.swift` | Extract: without the native delivery tests, whose receiver arrives with the signed lane |
| `Tests/SecreteoUITests/DictationCorrectionUITests.swift` | `Tests/PortavozUITests/DictationCorrectionUITests.swift` | Extract: without the dictionary test, which arrives with Settings |
| `Tests/SecreteoUITests/DictationPolishUITests.swift` | `Tests/PortavozUITests/DictationPolishUITests.swift` | Extract: without the Settings tests, which are rewritten for the Polish section |
| `Tests/SecreteoUITests/DictationTranslationUITests.swift` | `Tests/PortavozUITests/DictationTranslationUITests.swift` | Extract: the Settings test is rewritten for Secreteo's form |
| `Tests/SecreteoUITests/DictationTextModeUITests.swift` | `Tests/PortavozUITests/DictationTextModeUITests.swift` | Seam: the Settings tests reach the form by scrolling, without the privacy note, and drive the chooser with plain keys |
| `Sources/DictationStore/DictationStore+History.swift` | `Sources/StorageKit/MeetingStore+DictationHistory.swift` | Seam: imports `DictationKit` and `SpeechCore`, and deleting, retention, a save that expires rows and a policy change end with a truncating checkpoint |
| `Sources/DictationSession/History/ApplicationUseCase.swift` | `Sources/ApplicationKit/ApplicationUseCase.swift` | Renames |
| `Sources/DictationSession/History/DictationHistoryUseCases.swift` | `Sources/ApplicationKit/DictationHistory.swift` | Seam: imports `SpeechCore` |
| `Sources/DictationSession/History/DictationHistoryModel.swift` | `Sources/portavoz-app/DictationHistoryModel.swift` | Seam: imports `SpeechCore`, with no meeting links or Ask focus ([D2](DECISIONS.md#d2-scope-and-approved-losses)) |
| `Sources/DictationSession/History/DictationFeature+History.swift` | `Sources/portavoz-app/AppServices+DictationSetup.swift` | Extract: the history seed, plus opening the store, and a logged stand-in when it cannot open |
| `Sources/DictationSession/History/DictationHistoryView.swift` | `Sources/portavoz-app/DictationHistoryView.swift` | Seam: reads the feature in its own window, title case, no helper text, and no meetings, Ask focus or statistics yet |
| `Sources/DictationSession/Settings/DictationHistorySettingsSection.swift` | `Sources/portavoz-app/DictationHistorySettingsSection.swift` | Seam: reads the feature, title case, no helper text, shows a failure, and the agents switch arrives with the MCP server |
| `Tests/DictationStoreTests/DictationHistoryStoreTests.swift` | `Tests/PortavozKitTests/DictationHistoryStoreTests.swift` | Seam: v1 instead of v54, imports `SpeechCore`, no `ApplicationKit` |
| `Tests/DictationStoreTests/DictationSearchStoreTests.swift` | `Tests/PortavozKitTests/DictationSearchStoreTests.swift` | Seam: imports `SpeechCore`, and v1 has no migration to index older rows, so a reopened store finds what it saved instead |
| `Tests/DictationSessionTests/History/DictationHistoryModelTests.swift` | `Tests/PortavozAppTests/DictationHistoryModelTests.swift` | Seam: imports `SpeechCore` |
| `Tests/DictationSessionTests/History/DictationHistoryRecordingTests.swift` | `Tests/PortavozAppTests/DictationHistoryRecordingTests.swift` | Seam: builds a `DictationFeature`, and the statistics test arrives with statistics |
| `Tests/SecreteoUITests/DictationHistoryUITests.swift` | `Tests/PortavozUITests/DictationHistoryUITests.swift` | Seam: opens a window from the menu, English only, filters in the list test, waits for seeded consent, and no meetings, Ask or statistics yet |

## Repository bootstrap

Adapted from `johnny4young/portavoz@cffa87bb36f800108bd8e366bbaa153e2c9ec88f`.

| Secreteo path | Portavoz path | Change |
|---|---|---|
| `.swiftlint.yml` | `.swiftlint.yml` | Lints `Apps` and `Sources`; drops Portavoz identifier exceptions |
| `.github/dependabot.yml` | `.github/dependabot.yml` | Comment reworded |
| `.github/pull_request_template.md` | `.github/pull_request_template.md` | New structure, with the checklist kept |
| `.github/ISSUE_TEMPLATE/*` | `.github/ISSUE_TEMPLATE/*` | Dictation areas |
| `CODE_OF_CONDUCT.md` | `CODE_OF_CONDUCT.md` | Reports through GitHub; no email |
| `CONTRIBUTING.md` | `CONTRIBUTING.md` | Module rules removed |
| `SECURITY.md` | `SECURITY.md` | Dictation commitments; no email |
| `scripts/verify-ci-toolchain.sh` | `scripts/verify-ci-toolchain.sh` | None |
| `scripts/run-ci-swiftlint.sh` | `scripts/run-ci-swiftlint.sh` | Scratch prefix |
| `scripts/install-ci-xcodegen.sh` | `scripts/install-ci-xcodegen.sh` | None |
| `scripts/check-repository-hygiene.sh` | `scripts/check-repository-hygiene.sh` | Keeps tracked-file, ticket and action-pin checks; adds identifier ratchet, license, attribution, accent-bar and Node checks |

## Shell

| Secreteo path | Source | Change |
|---|---|---|
| `scripts/fetch-sparkle.sh` | `johnny4young/gancho`, `scripts/fetch-sparkle.sh` (MIT, same author) | Comments |

## Spikes

| Secreteo path | Source | Change |
|---|---|---|
| `spikes/tcc-adhoc/grant.py` | `johnny4young/gancho`, `scripts/prepare-hosted-handoff-permissions.py` (MIT, same author) | One app, `cdhash` requirements only |

## Other projects compared

Portavoz's dictation sources were compared with [Megaphone](https://github.com/Kuberwastaken/megaphone) (MIT, Copyright Kuber Mehta and Zach Latta) at `5a9136b3`. None of its distinctive types appear in Portavoz, and the 77 long lines the two share are generic SwiftUI, AppKit and Foundation calls. This comparison cannot detect a rewrite. No Megaphone code is knowingly imported, so its notices are not included. If any derivation is found, both copyright lines go in the derived file and in the notices.

## Ownership protocol peers

The [ownership protocol](specs/ownership-protocol.md) has to recognize Portavoz builds that do not cooperate, so it needs these values:

| Value | Portavoz |
|---|---|
| Release identifier | `app.portavoz.mac` |
| Dev identifier | `app.portavoz.mac.dev` |
| Preference key | `globalDictationEnabled`, off when absent |

## Identifier ratchet

These source-app identifiers are rejected everywhere except this file, the notices and `Sources/DictationSession/KnownDictationPeers.swift`, which the protocol needs:

`app.portavoz`, `PORTAVOZ_`, `PVDesign`, `"PVOZ"`, `0x5056_4F5A`, `Apuntador`, `CloudKit`, `PortavozSourceCommit`, `portavozLocalized`, `portavoz-ui-tests`, `Application Support/Portavoz`.

## Release tooling

Adapted from `johnny4young/gancho@d747c028ffb5af4a9430bc43d63f581520a03458`.

| Secreteo path | Gancho path | Change |
|---|---|---|
| `.github/workflows/release.yml` | `.github/workflows/release.yml` | Separates signing from write access; creates a draft; no provisioning profile |
| `.github/workflows/update-cask.yml` | `.github/workflows/update-cask.yml` | Runs on publish and refuses a draft |
| `.github/workflows/pages.yml` | `.github/workflows/pages.yml` | Node from `.nvmrc`; no site script |
| `scripts/package-release.sh`, `scripts/sign-app.sh` | `scripts/package-macos-dmg.sh` | Adds the dry-run mode; signs before notarizing with no ignored failures |
| `scripts/generate-appcast.sh` | `scripts/generate-appcast.sh` | Embeds notes; the requirement checks moved to `scripts/verify_appcast.py` |
| `scripts/update-homebrew-tap.sh` | `scripts/update-homebrew-tap.sh` | Cask only; fails without a key; pins GitHub's host key |
