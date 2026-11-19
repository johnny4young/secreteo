# Dictation timing log, version 2

An opt-in record of how long each dictation took, for measurement runs such as [Spike 1](../spikes/two-apps-at-once.md). It holds times, counts and an outcome. Never audio, words, the target app or anything else a person said or typed.

## Turning it on

Launch the app with `-dictation-timing-log <absolute path>`:

```sh
open -n "/Applications/Secreteo Dev.app" --args -dictation-timing-log /absolute/folder/timing.jsonl
```

- The shipped identity, `com.johnny4young.secreteo`, ignores the argument. The Dev identity and unbundled test builds honor it, in Debug and Release.
- A relative path, a folder path or a missing value turns nothing on.
- The file is created with mode `0600` and only ever appended to. A write that fails is dropped and never interrupts dictation.

## Records

One JSON object per line, one line per dictation session, written when the session ends. Keys are sorted.

| Key | Meaning |
|---|---|
| `schemaVersion` | `2`. A new or changed key needs a new version. Version 1 had no `diagnostics` |
| `startedAt` | Wall clock when the trigger was accepted, in seconds since 1970 |
| `admission` | `global` or `practice` |
| `engine` | The lane that transcribed it (`parakeet`, `parakeetUltra`, `appleSpeech`), or `null` if no model became ready |
| `session` | The controller measurement: `elapsedSeconds` per point, `terminalSeconds` and `outcome`, all measured from `startedAt` on a monotonic clock |
| `audio` | Frame counts, below |
| `diagnostics` | Why the dictation started and stopped when it did, below |

`session.elapsedSeconds` names reach-once points: `microphoneReady`, `firstBufferHandled`, `runtimeReady`, `firstCaptionHandled`, `stopRequested`, `inputEnded`, `transcriptionEnded`, `textPrepared`, `deliveryStarted`, `deliveryReturned`. A point that was never reached is absent. `outcome` is one of `permissionDenied`, `cancelled`, `pipelineFailed`, `empty`, `noSpeech`, `dispatchReported` or `deliveryRejected`; `dispatchReported` means the paste was sent, not that the target app showed it.

`audio`:

| Key | Meaning |
|---|---|
| `acceptedFrames` | Frames the capture admitted, padding included, or `null` when the source cannot prove it |
| `paddingFrames` | Silence inserted over a gap in the device's timeline: audio that never arrived |
| `rejectedFrames` | Frames refused at admission |
| `relayDroppedChunks`, `relayDroppedFrames` | Audio the relay to the model could not hold. Any drop also fails the session, so nothing partial is typed |
| `captureFailure` | The capture's failure, if any |

A session lost audio when `paddingFrames + rejectedFrames + relayDroppedFrames` is above zero.

`diagnostics`, audio levels as RMS or peak between 0 and 1, never audio:

| Key | Meaning |
|---|---|
| `inputTransport` | `builtIn`, `bluetooth`, `usb` or `other` for the microphone used, absent when unknown |
| `replacedBluetooth` | A Bluetooth system default gave way to the Mac's own microphone |
| `firstAudibleSeconds` | When the first buffer above digital silence arrived; absent if none did |
| `tail` | The stop tail's decision: the room `floor`, the `threshold`, the `loudestAfterGesture`, `quietSeconds` counted after Stop, `heardSound` and `endedEarly`. Absent when the session never stopped by its gesture |
