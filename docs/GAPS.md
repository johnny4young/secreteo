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
- The Fn and modifier tap never consumes an event but runs as an active tap on the main thread, so a main-thread stall delays typing everywhere until macOS disables the tap. A listen-only tap may need the Input Monitoring permission.
- A synthetic copy can arrive after its one second late window and stay on the clipboard, and a real copy inside that window is replaced by the old contents. The pasteboard does not say who wrote.

## G10. Words after a failure or a lock

- Words in recovery, or kept after a capture failure, stay in memory until the user closes or restarts, even across a lock. Losing a long dictation to an automatic lock is the worse outcome, so only Paste last and the controller's other copies expire.
- A lock during a delivery clears Paste last, and the delivery then stores the same words for up to 15 more minutes.
- A retry from recovery after a lock cannot update its history row, because the draft is gone.

## G11. Menu rows and focus

Dictate and the paste rows give focus back to the app that was frontmost when the menu opened, then act. If that app does not take focus within half a second the action still runs, and its words can miss. XCUITest cannot reach the status item, so a test drives the same hand-back from the window-mounted menu, and the popover's own path has not been clicked on a real Mac. Closing the menu with no action leaves focus in Secreteo, as it did before.

## G12. A model Secreteo did not install

- The readiness check counts a verified model even if only another app claims it, so Secreteo can show ready and load it with no claim of its own. If that app removes its claim, the next launch's collection, in either app, can delete the model.
- A crash after a model is published and before its claim is written leaves it unclaimed. Secreteo shows it as ready, and the next launch's collection deletes it, which costs one more download.
- Settings shows no download progress, so a resumed download looks like one starting over.
- A loaded model holds no store lease, so another app's removal can delete the files under it. The engine keeps running from memory, and the next load reports the model as missing.

## G13. An icon loss no event announces

The watchdog's events cover both halves of its check: `isVisible` through key-value observing, and the button's window through a hidden subview. Neither the per-app Menu Bar setting on macOS 26 nor a display change has been tried on a real Mac, so a loss there may only show on the 5 s timer, about 7 s after it happens. The check sees whether the item has a window, not whether it was painted.

## G14. Portavoz settings left out of the import

The import copies only settings Secreteo's Settings can show and change. Activation and every trigger stay out, because the two apps must not answer the same keys. The microphone needs its own confirmation, since another input can change a Bluetooth profile. Polish's engine stays out because Portavoz's is its summary engine, which may be MLX. Portavoz Dev's settings are not read.
