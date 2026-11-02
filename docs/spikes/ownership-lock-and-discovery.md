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

Measured on 2026-11-02 on an M4 Max with macOS 26.6.2.

| Scenario | Admitted | Refused | Overlaps | Other |
|---|---|---|---|---|
| Negative control, lock disabled | 6,000 | 0 | **8,433** | The checker detects double admission |
| Simultaneous launch | 2,000 | 4,000 | 0 | Only the owner was admitted |
| Toggle | 3,749 | 4,251 | 0 | Generation reached 501, with no gaps |
| Stale read | 1,976 | 2,024 | 0 | Generation reached 501, with no gaps |
| Handoff during a session | 200 | 0 | 0 | 0 handoffs inside a session. All 200 applied after the session ended |
| Competing handoffs | | | 0 | Generation reached exactly 1,001, with none lost |

| Check | Result | Verdict |
|---|---|---|
| Crash, 200 SIGKILLs | Lock available at p50 0.02 ms, p99 0.05 ms. 0 wrongly admitted, 0 owner changes, 0 failed recoveries | Pass |
| Timed-out handoff | Reports `timeout`, and owner and generation are unchanged | Pass |
| Foreign writes | Plist byte-identical after 50 reads. No plist created for a missing domain | Pass |
| Staleness | With `CFPreferencesAppSynchronize` before each read: p50 2.25 ms, max 2.6 ms, 30 of 30 seen | Recorded |
| Dev and Release | 100 of 100 refused without confirmation, 0 admitted. Admitted after a confirmed handoff | Pass |

## Verdict

**Passes.** A `flock` held for the session, with owner and generation read under it, gave no double admission, and a crash frees the lock without moving ownership.

## Constraints for the protocol

- **Close on exec.** Open the lock with `O_CLOEXEC`. A `flock` belongs to the open file description, so a child that inherits it would keep the lock after the parent dies.
- **Admission never trusts a hint.** The stale-read scenario passes because admission re-reads under the lock. Discovery reads can inform the UI only.
- **Handoffs need a timeout.** A live but wedged holder keeps the lock forever, because only process death releases it. The timeout changes nothing, and the UI has to offer a way out.
- **Discovery readers must synchronize.** The staleness figure holds only with `CFPreferencesAppSynchronize`.

## Not covered

- Sleep and wake, upgrades, uninstall, revoked permissions, and real triggers. These belong to the protocol's own matrix.
- A real Portavoz, which this spike never touches.
- Home directories on network volumes, where `flock` behavior is unverified.
