# Architecture

## Implemented today

The shell and dictation:

- `Apps/Secreteo` is the thin app target. `project.yml` generates its project.
- `AppUI` holds the composition root, the status item, the menu content, Settings, the first-run onboarding window, launch at login, the single-instance lock and the move to Applications. Onboarding shows once, when dictation exists in the build; closing it counts as finishing. Its steps live in `DictationSession/Onboarding`.
- An `NSStatusItem` with `.terminationOnRemoval` and a watchdog keep the app from running without a visible icon. The watchdog checks every 0.75 s after launch, after a miss, and after an event that can take the icon away, and every 5 s otherwise ([G13](GAPS.md#g13-an-icon-loss-no-event-announces)). Opening the app again shows Settings, which is the way back when macOS hides the icon. Menu rows that deliver words give focus back to the previous app first ([G11](GAPS.md#g11-menu-rows-and-focus)).
- `Apps/Secreteo/SparkleUpdater.swift` wraps Sparkle behind `UpdateChecking`, so `AppUI` does not link it. A scheduled update sets a menu row instead of showing an alert. `scripts/fetch-sparkle.sh` is the single source of the framework and its tools.
- UI tests launch with `-use-temp-store`, which gives them their own instance lock, no real launch at login and no onboarding, and with `-show-menu-content`, which mounts the real menu content in a window. `-show-onboarding` brings onboarding back for its own tests.
- `DictationOwnership` is the [ownership protocol](specs/ownership-protocol.md): state format, locks, admission, handoff and peer detection. Portavoz is adopting this product at a pinned revision, so a test keeps its imports to system frameworks.
- `SpeechCore` holds shared value types, `MicCapture` holds microphone capture and its permission, `LiveSpeech` holds the recognition engines and the model pins, `DictationKit` holds the dictation domain and pure text rules, and `DictationSession` holds the session controller, text delivery and the triggers. `DictationFeature` is the one public type: it implements the `AppServices` protocol the controller asks through, and `AppUI` holds it and sees nothing else. The panel lives here too, because it reads the controller's internal state. `Polish` holds the prompt, Apple Foundation Models, the Ollama client and the loopback-only gateway; the session reaches it through the `DictationTextPolishing` port ([D24](DECISIONS.md#d24-polish-runs-only-on-this-mac-and-keeps-no-journal)). A Release build does not create the feature until `SECRETEO_GLOBAL_DICTATION` is turned on ([D20](DECISIONS.md#d20-release-builds-do-not-run-global-dictation-yet)). All are copied from Portavoz ([PROVENANCE](PROVENANCE.md#dictation-code)), and [PARITY](PARITY.md) tracks what has arrived.
- `DictationStore` is the GRDB database for history, search and statistics, with its own schema ([D23](DECISIONS.md#d23-the-dictation-database-moves-forward-only-and-an-older-build-leaves-a-newer-one-alone)). It depends only on `DictationKit`, so the MCP server can open it read-only.
- Models live in the shared store ([D9](DECISIONS.md#d9-shared-model-folder)). Before downloading, an install clones the files Portavoz already has in `Portavoz/Models`, keeps only those that hash right, and never writes there.
- `Tests/Plans/Smoke.txt` lists the PR tests, and `scripts/run-ui-tests.sh full` runs everything.

## Target module graph

The app is built from SwiftPM libraries plus one thin XcodeGen app target ([D6](DECISIONS.md#d6-build-with-swiftpm-libraries-and-a-thin-xcodegen-target)). These names are responsibility groups. A separate target is created only where it isolates compilation or tests.

```
Secreteo          thin app target: @main, plist, catalogs, assets
secreteo-mcp      stdio executable
  AppUI             menu, settings, onboarding, history
  DictationSession  controller, capture, gate, measurement; text insertion, clipboard, caret, readback; Carbon hotkey, modifier and mouse push-to-talk; panel
  Polish            prompt, Apple Foundation Models, Ollama client, loopback egress gateway
  DictationKit      domain, text rules, use cases
  DictationOwnership  one global dictation at a time, shared with Portavoz
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
