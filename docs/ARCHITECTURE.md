# Architecture

## Implemented today

Repository tooling, CI, and the first library, `AppUI`. There is no dictation code yet.

## Target module graph

The app is built from SwiftPM libraries plus one thin XcodeGen app target ([D6](DECISIONS.md#d6-build-with-swiftpm-libraries-and-a-thin-xcodegen-target)). These names are responsibility groups. A separate target is created only where it isolates compilation or tests.

```
Secreteo          thin app target: @main, plist, catalogs, assets
secreteo-mcp      stdio executable
  AppUI             menu, panel, settings, onboarding, history
  DictationSession  controller, capture, gate, measurement
  Delivery          text insertion, clipboard, caret, readback
  Triggers          Carbon hotkey, modifier and mouse push-to-talk
  Polish            prompts, ports, Apple Foundation Models, Ollama client, egress gateway
  DictationKit      domain, text rules, use cases
  DictationStore    GRDB, own database
  LiveSpeech        Parakeet, Silero. FluidAudio with traits: []
  MicCapture        microphone capture and permission
  SpeechCore        shared value types
  LocalModelStore   external package
  Sparkle
```

## Dependency rules

- `SpeechCore` imports no UI, store or models.
- `DictationSession` depends on ports (capture, recognition, delivery, Polish), not on the composition root.
- Store and providers implement ports, with no cycles.
- `AppUI` and the MCP executable compose. Nothing else does.
- A dependency-graph snapshot in tests proves that MLX, Whisper and diarization never enter the graph.
