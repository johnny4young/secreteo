# Gaps

Known limits and unresolved work.

## G1. Two apps at once

The cost of running Secreteo and Portavoz together is not measured yet: caption latency, time to first text, audio loss and footprint. Thresholds are written before measuring. Distribution waits on the result.

## G2. 8 and 16 GB Macs

Measurements so far come from one 36 GB machine, which does not prove smaller Macs. Before 1.0, measure on target hardware or declare a minimum.

## G3. Core ML compiles per app

Even with one shared download, each app compiles its own Core ML copy: the result depends on both the path and the app. Parakeet takes about 14 seconds on an M4 Max, and smaller chips are unmeasured. Onboarding shows a warm-up step ([measurements](spikes/model-path-and-specialization.md)).

## G4. Second download with an older Portavoz

A Portavoz version that does not know the shared store downloads the model again if Secreteo is installed first.

## G5. No Polish without a provider

A Mac with neither Apple Foundation Models nor Ollama has no Polish or Rewrite.

## G6. Things that do not transfer from Portavoz

Microphone and Accessibility grants, Shortcuts, MCP client configuration, and history.

## G7. Updates during a dictation

A scheduled update shows as a menu row and never interrupts. Once dictation sessions exist, relaunching for an update the user accepted has to wait for the session to end, through Sparkle's `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`.

## G8. Ownership on a network home

`flock` behavior on a home directory on a network volume is unverified. The [ownership protocol](specs/ownership-protocol.md) fails closed where `flock` reports it is unsupported. A volume that accepts `flock` without enforcing it across processes would not be detected.

## G9. Delivery limits a real device has to settle

Delivery logic has only run against scratch pasteboards and injected events. These remain open:

- A session-route paste checks the frontmost app and that the focused field is not secure, but not that the field belongs to that app. Another app's non-activating panel could receive it.
- The pasteboard offers no atomic compare and replace, so another app's write in the instant between the check and the replacement is lost.
- The clipboard returns on a fixed 1.5 second timer. An editor that stalls longer pastes the restored contents, and a verified paste still holds the clipboard for the whole window.
- One unreadable clipboard type refuses the paste and sends the text to recovery. How often real clipboards do this is unmeasured.
- A correction whose replacement fails leaves the caret where the selection moved it.
