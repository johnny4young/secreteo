# Spike: ownership lock and discovery

Two apps must never admit a global capture at once ([D15](../DECISIONS.md#d15-one-dictation-owner-per-mac)). This spike tests the two mechanisms the protocol would rest on: a `flock` held for the whole session, with owner and generation read under it, and reading another app's preferences as a hint only. It does not specify the protocol.

## Questions

1. Can two clients ever be admitted at once under simultaneous launch, ownership toggles, or a stale read made before taking the lock?
2. After a crash, is the lock released with the owner unchanged, and does recovery need an explicit step?
3. Can an owner change land in the middle of a session?
4. Does reading another domain's preferences write to it, and how stale can a read be?
5. Does a Dev client stay out of a Release owner's way unless the user confirms?

## Method

Everything uses scratch roots and throwaway `com.johnny4young.secreteo.spike.*` domains, with no microphone, no triggers, and no contact with installed apps.

`spikes/ownership/client.swift` is one client binary. Sessions log `enter` and `exit` while holding the lock, through one `O_APPEND` file, so file order is the order of events. `spikes/ownership/run.py` runs these scenarios and checks the log:

| Scenario | What runs |
|---|---|
| Simultaneous launch | Release, Dev and a third client start together, 3 × 2,000 rounds, fixed owner |
| Toggle | Two clients in a loop while a driver flips the owner through 500 handoffs |
| Stale read | Each round reads state before the lock, and a handoff lands between the read and the lock |
| Crash | 200 × SIGKILL of the holder at a random point in the session, then the other client tries to admit |
| Handoff during a session | A handoff starts while a session holds the lock, 200 times, and with a timeout shorter than the session |
| Competing handoffs | Two drivers hand off at once, 500 times each |
| Discovery | A writer changes a domain while a reader polls it, 30 samples, and a reader opens a domain that does not exist |
| Dev and Release | A Dev client tries to admit and to take ownership from Release, with and without user confirmation |
| Negative control | The same log checker runs on clients with the lock disabled |

## Thresholds

Written before measuring.

| Check | Passes if |
|---|---|
| Double admission | 0 overlapping `enter` and `exit` pairs in every scenario |
| Negative control | The checker reports overlaps with the lock disabled. Otherwise the whole result is void |
| Admission | Every `enter` has the client as owner, at the generation current under the lock |
| Generations | Strictly increasing by 1, with none lost across competing handoffs |
| Crash | The other client gets the lock within 100 ms at p99 and is **not** admitted, the owner is unchanged, and it is admitted only after an explicit handoff |
| Mid-session handoff | 0 handoffs inside an `enter`/`exit` pair. A timed-out handoff changes nothing |
| Foreign writes | A reader leaves the other domain's plist byte-identical and creates no plist for a missing domain |
| Staleness | Recorded, not gated: discovery is a hint and never decides admission |
| Dev | Refused without confirmation in 100% of attempts, and admitted only after a confirmed handoff |

## Results

Pending.
