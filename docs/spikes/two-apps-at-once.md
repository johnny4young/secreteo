# Spike 1: two apps at once

**Question:** does running Secreteo and Portavoz together degrade either one? ([G1](../GAPS.md#g1-two-apps-at-once))

**Status:** thresholds written 2026-11-11, before any measurement. Not run yet.

## Setup

- The release Mac, Apple silicon. Note the chip, memory, macOS build and power source.
- A macOS user account used only for this run. Portavoz keeps its database at a fixed path whatever its bundle id, so a separate account is what keeps the owner's library out of reach.
- In that account, Portavoz `v1.5.1` or a later tag that ships the ownership protocol. Never the owner's Portavoz or its library.
- Secreteo from `make install`, without `-use-temp-store`: that flag swaps in a fake microphone, a fake engine and a private ownership root, so the two apps would never meet. Release builds ignore it.
- The public synthetic corpus from `scripts/materialize_dictation_corpus.py`, played to the input through a loopback device, or the owner's voice reading the same cells.
- A line in `STATUS.md` before starting, removed after.

## Cells

Each cell runs **at least 30 launches**, in alternating order, on the same corpus. The Bluetooth and sleep cells are the exception: the owner runs them by hand, 5 times each, by the owner's decision of 2026-11-12. The thresholds are the same for them.

| Axis | Values |
|---|---|
| Who runs | Portavoz alone (control), Secreteo alone (control), both |
| Model state | Cold (first load after login), warm |
| Model | Parakeet v3, Parakeet Ultra |
| Background work | Idle, a Portavoz meeting recording in progress |
| Microphone | Same input for both apps, different inputs |
| Endings | Stop, cancel |
| Events | Bluetooth headset connected, sleep and wake during a dictation |

The harness builds 48 automated cells from these axes. Per app: cold or warm, Parakeet v3 or Ultra, Stop or cancel. Each has a control, that app alone and idle, and a treatment with the other app running idle. Secreteo also dictates beside a Portavoz meeting, on the same input and on a different one; Portavoz never dictates during its own meeting. The 4 manual cells are each app, warm, Ultra and Stop, with a Bluetooth headset connected or a sleep and wake.

## Thresholds

| Measure | Passes when |
|---|---|
| Caption latency, p95 | Rises less than 500 ms against the same app alone |
| Time to first text, p95 | At most 1.5 times the control, and never above 2.5 s |
| Lost audio | Zero frames dropped in any cell |
| Double delivery | Zero: no text pasted twice, or pasted by both apps |
| Crashes | Zero |

Also recorded, without a threshold: footprint per process, memory pressure and swap.

How each one is measured:

| Measure | How |
|---|---|
| Time to first text | From the trigger key to the first word in the dictating app's panel, read over Accessibility every 30 ms |
| Caption latency | From the end of speech in the played file to the last caption change before Stop. Stop comes once captions have been still for 1.5 s, at most 6 s after speech; a trial that hit the cap is flagged |
| Lost audio | Secreteo: its [timing log](../specs/dictation-timing-log.md), padding plus rejected plus relay-dropped frames. Portavoz 1.5.1 reports no frames, so a Stop that typed nothing counts instead, marked indirect |
| Double delivery | Separate pastes in the harness's receiver window; insertions within 50 ms are one paste |
| Crashes | A new crash report for either app, or its process gone |

Cold means the dictating app relaunched before each trial. The disk cache is not purged, so it stands in for the first load after login.

## How to run

The harness is `scripts/spike_two_apps.py`. It compiles `scripts/spike-agent.swift`, which posts the trigger keys, reads the panels, plays the corpus into the loopback and keeps the receiver window. Rows and the report hold times and counts, never audio or words.

Once, as an administrator:

1. Install BlackHole 2ch. It is GPL-3.0 and used only as an installed device.
2. Create the macOS account for the spike and log in to it. Fast user switching keeps your own account in the background.
3. In your own account, `make install` from `main`. `/Applications/Secreteo Dev.app` is shared by every account.

In the spike account:

1. Install Portavoz 1.5.1 from its release disk image into `~/Applications`, never over `/Applications`. The harness turns off its automatic updates.
2. Open both apps, finish onboarding, download Parakeet v3 and Ultra in each, and turn dictation on. Secreteo triggers with ⌃⌥⌘D and Portavoz with ⌥⌘D.
3. Grant Microphone to both apps, and Accessibility to both apps and to Terminal. Accept the prompts that let Terminal quit each app.
4. In Shortcuts, create `Spike Start Meeting` with Portavoz's Start Recording action and `Spike Stop Meeting` with Stop Recording.
5. Render the corpus with `scripts/materialize_dictation_corpus.py` ([Fixtures/DictationValidation](../../Fixtures/DictationValidation/README.md)) into a new folder.
6. Plug in the Mac and add the line in `STATUS.md`.

Then run, and leave the Mac alone:

```sh
caffeinate -dims python3 -I scripts/spike_two_apps.py run --corpus ~/spike/corpus --output ~/spike/result-1
```

- It stops early with a list of what is missing: permissions, the loopback, the Shortcuts, the Dev identity. Pass `--other-input` with the name of a second microphone if the Mac's own is named differently.
- It pauses once to move dictation from Secreteo to Portavoz, and for each Bluetooth and sleep trial.
- About 6 hours unattended, plus 15 minutes for the manual cells. `plan` prints the estimate for the current options.
- Ctrl-C stops it, and the same command resumes. `--automated-only` skips the manual cells, and `report --output <folder>` scores the rows again.
- `run --dry-run --output <folder>` drives simulated apps: it checks the pipeline and measures nothing.

The verdict is `pass`, `fail` or `incomplete` (too few trials, or a measure missing). Copy `report.md` from the result folder into [Result](#result).

## If it fails

Apply the no-go rule in order, and measure again after each step:

1. Release the idle model, never one with a lease or a running session.
2. Offer the compact engine explicitly, without changing the preference silently.
3. Serialize dictation and meeting capture, or revisit the split with the owner.

## Result

Not measured yet.
