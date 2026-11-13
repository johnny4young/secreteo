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

Each cell runs **at least 30 launches**, in alternating order, on the same corpus.

| Axis | Values |
|---|---|
| Who runs | Portavoz alone (control), Secreteo alone (control), both |
| Model state | Cold (first load after login), warm |
| Model | Parakeet v3, Parakeet Ultra |
| Background work | Idle, a Portavoz meeting recording in progress |
| Microphone | Same input for both apps, different inputs |
| Endings | Stop, cancel |
| Events | Bluetooth headset connected, sleep and wake during a dictation |

## Thresholds

| Measure | Passes when |
|---|---|
| Caption latency, p95 | Rises less than 500 ms against the same app alone |
| Time to first text, p95 | At most 1.5 times the control, and never above 2.5 s |
| Lost audio | Zero frames dropped in any cell |
| Double delivery | Zero: no text pasted twice, or pasted by both apps |
| Crashes | Zero |

Also recorded, without a threshold: footprint per process, memory pressure and swap.

## If it fails

Apply the no-go rule in order, and measure again after each step:

1. Release the idle model, never one with a lease or a running session.
2. Offer the compact engine explicitly, without changing the preference silently.
3. Serialize dictation and meeting capture, or revisit the split with the owner.

## Result

Not measured yet.
