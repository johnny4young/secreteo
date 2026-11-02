# Spike: ad-hoc signing for the TCC lane

Real delivery needs real Accessibility trust ([D8](../DECISIONS.md#d8-vm-granted-tcc-proves-delivery-mechanics-only)). The lane this comes from signs with a Developer ID certificate, which pull requests cannot read inside the `release` Environment. If a TCC row can match an ad-hoc signature through its `cdhash`, the lane needs no secret and also works for forks.

## Question

On a disposable hosted `macos-26` runner, does an ad-hoc signed app with a TCC row bound to its `cdhash` get working Accessibility and event posting, with no secrets?

## Method

`.github/workflows/spike-tcc-adhoc.yml` runs on `workflow_dispatch` and reads no secrets. The repository has none set, which is the same position as a fork.

1. Build a sender and a receiver with `swiftc`, wrap them as `.app` bundles, and sign both ad-hoc.
2. Assert that the designated requirement is `cdhash H"…"` and that no signing authority is present.
3. **Before the grant:** the sender, launched with `open`, reports not trusted.
4. Write `kTCCServiceAccessibility` and `kTCCServicePostEvent` rows with the compiled requirement, only on the hosted VM.
5. **After the grant:** the sender reports trusted.
6. The sender sets the pasteboard, activates the receiver, posts ⌘V with `.cghidEventTap` as production does, and reads the focused text back through the Accessibility API.
7. The receiver independently records what its text view received.
8. **Binding:** rebuild the sender with a changed binary under the same bundle ID. It reports not trusted against the old row.

## Thresholds

Written before measuring. All must hold in 3 of 3 separate runs.

| Check | Passes if |
|---|---|
| Control before the grant | `AXIsProcessTrusted` is false |
| After the grant | `AXIsProcessTrusted` and `CGPreflightPostEventAccess` are true |
| Delivery | The receiver holds the exact text, exactly once |
| Readback | The Accessibility API returns the same text |
| Binding | A different `cdhash` under the same bundle ID is not trusted |
| Secrets | The workflow references no `secrets.*` |

If it fails, the fallback is an Environment restricted to branches of this repository. `pull_request_target` with an untrusted checkout is never an option.

## Results

Measured on 2026-11-02 on hosted `macos-26` (macOS 26.6.2, Xcode 26.6) at `9b6acaf`, in runs [41531669118](https://github.com/johnny4young/secreteo/actions/runs/41531669118), [41533157061](https://github.com/johnny4young/secreteo/actions/runs/41533157061) and [41533168511](https://github.com/johnny4young/secreteo/actions/runs/41533168511). An earlier run at `886ce8d` failed to compile, before any check ran, and does not count.

| Check | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| Not trusted before the grant | Pass | Pass | Pass |
| Trusted and able to post events after the grant | Pass | Pass | Pass |
| Receiver holds the exact text, exactly once | Pass | Pass | Pass |
| Accessibility readback matches | Pass | Pass | Pass |
| Different `cdhash`, same bundle ID, not trusted | Pass | Pass | Pass |

The workflow references no secrets, and the repository has none set. Each job took about 30 seconds.

## Verdict

**Passes.** The delivery lane can use ad-hoc signing with `cdhash` TCC rows, with no signing secret ([D18](../DECISIONS.md#d18-the-delivery-lane-signs-ad-hoc)). A rebuilt binary loses the grant, so the rows have to be written after the final build.

## Not covered

- A pull request from a real fork. The run has the same inputs as a fork, with no secrets, but no fork PR was run.
- The XCUITest runner as a TCC client, and the Hardened Runtime. Both come up when the real lane is built.
- Microphone and the cross-process Fn tap, which stay in the manual gate.
