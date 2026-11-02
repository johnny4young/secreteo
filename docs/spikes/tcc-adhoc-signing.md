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

Pending.
