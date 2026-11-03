# Dictation ownership protocol, version 1

Two apps that both listen for the same trigger would start two sessions and paste twice. This protocol keeps a Mac to at most one admitted global capture or delivery, across Portavoz, Secreteo and their Dev builds ([D15](../DECISIONS.md#d15-one-dictation-owner-per-mac)).

It is cooperative and not a security boundary. Any process running as the user can ignore it or edit its files.

The mechanisms come from a [spike](../spikes/ownership-lock-and-discovery.md). The reference implementation in this repository is the executable form of this document. If they disagree, that is a bug in one of them.

## Terms

| Term | Meaning |
|---|---|
| Participant | An app that implements this protocol, named by its bundle identifier |
| Dev participant | A participant whose identifier ends in `.dev` |
| Owner | The one participant allowed to admit global sessions. May be nobody |
| Preference | The participant's own "global dictation on" setting. The protocol reads it and never writes it |
| Readiness | Microphone, Accessibility, engine and practice are all satisfied, as the participant defines them locally |
| Lease | The right to run one operation, which is the capture lock held for that operation |
| Intent | A published request to move ownership, with an expiry |

Three things stay separate: the durable owner (a file), whether a process is running and ready (local), and the temporary right to run a session (a lease). Being one does not imply another.

## Invariants

1. At most one process holds a lease. The kernel enforces this through `flock`.
2. `owner` and `generation` change only while the writer holds both locks, so they cannot change during a lease.
3. A global lease is granted only after reading the state under the capture lock and finding this participant as owner, with no live intent, in a known format version.
4. A lease lasts until delivery has finished and Stop has drained.
5. Safety depends only on invariants 1 to 4. Clocks, notifications, process lists and other apps' preferences affect what the UI shows and how fast things recover. None of them can admit a second session.

## Files

All files live in `~/Library/Application Support/com.johnny4young.dictation-ownership/`, mode `0700`, excluded from backups so a restore cannot bring back an old owner. The name is permanent. A sandboxed process has no access to it and reports `unavailable`.

| File | Purpose |
|---|---|
| `capture.lock` | Held exclusively for each lease, and during an ownership change |
| `state.lock` | Held briefly around every write to the state file. Never held across a wait |
| `ownership.json` | The state |

**Lock order:** capture, then state. Marking an intent takes only the state lock, because it has to work while another app's session holds the capture lock.

**Opening a lock:** `open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)`, then `flock(fd, LOCK_EX | LOCK_NB)`.

- `O_CLOEXEC` is required: a child that inherits the descriptor keeps the lock after the parent dies.
- After locking, `fstat(fd)` and `stat(path)` must name the same device and inode. If not, the file was replaced: close and retry once, then report `ioError`.
- `ENOTSUP` or `EOPNOTSUPP` from `flock` means `unavailable(lockUnsupported)`. This fails closed: a volume without `flock` cannot give this guarantee.
- Lock files are never deleted. An uninstall, including the cask's `zap`, leaves this folder in place.

**The state file:**

```json
{
  "version": 1,
  "owner": "com.example.app",
  "generation": 7,
  "previous": "com.example.other",
  "intent": {
    "id": "6F1E1A52-5C1B-4E58-9C49-0D0B4C2F6A11",
    "from": "com.example.app",
    "to": "com.example.other",
    "createdAt": "2026-11-03T12:00:00Z",
    "expiresAt": "2026-11-03T12:00:15Z"
  }
}
```

| Field | Rule |
|---|---|
| `version` | A reader that does not know the value reports `unavailable(newerProtocol)` and never rewrites the file. Any new field needs a new version |
| `owner` | A participant, or `null` for nobody |
| `generation` | Starts at 0 and rises by exactly 1 with each change of `owner`. Marking or clearing an intent does not change it |
| `previous` | The owner before the last change, or `null`. It only labels the UI's way back and grants nothing |
| `intent` | `null` or as above. Expired means `now >= expiresAt`, or `expiresAt` more than 15 seconds ahead of `now`, so a clock change cannot pin it |

A missing file means `owner: null`, `generation: 0`. An unreadable or invalid one, including an empty one, reports `unavailable(corruptState)`.

**Writes** happen under the state lock: write a temporary file in the same directory, `fsync`, then `rename`. Any leftover temporary file seen under the state lock is stale and may be removed. Reads need no lock, because the rename is atomic.

The files hold identifiers, a counter and timestamps. Never audio, text, or anything about a session.

## States

Each participant derives its state locally, and re-derives it on every event in [Reevaluation](#reevaluation). The first row that matches wins.

| # | Condition | State | Triggers armed | Prewarm |
|---|---|---|---|---|
| 1 | Lock unsupported, `newerProtocol`, `corruptState`, `ioError` or sandboxed | `unavailable(reason)` | No | No |
| 2 | A non-cooperating peer is active ([below](#non-cooperating-peers)) | `unavailable(legacyPeerActive)` | No | No |
| 3 | Live intent with this participant as `from` or `to` | `transferring` | See [Handoff](#handoff) | No |
| 4 | Preference is off | `off` | No | No |
| 5 | Is owner, and not ready | `unavailable(reason)`, naming the missing piece | No | No |
| 6 | Is owner, and ready | `owned` | Yes | Yes |
| 7 | Not owner, and not ready | `preparing` | No | No |
| 8 | Not owner, and ready | `available` | No | No |

Only `owned` arms triggers, so a non-owner gives up exclusive shortcuts and event taps. Disarming is not what keeps a Mac safe: a stale trigger reaches admission and is refused there.

A participant in `available` may offer to take ownership. Secreteo offers it only then, and ships with a shortcut other than ⌥⌘D and with Fn off by default.

Prewarm needs `owned` but no lease. A stale read can waste a model load, not cause a capture.

## Admission

Every operation that can capture or deliver globally goes through one port. This covers sessions from any trigger, the menu and Intents, Rewrite, retry, and paste-last. Reading through MCP does not need it.

```
acquire(kind) -> lease | refused(reason)

1. Try the capture lock without waiting. Held: refuse `busy`.
2. Read the state under it. Refuse `unavailable(reason)` on any failure in row 1.
3. Live intent: refuse `transferring`.
4. Kind `global`: owner is not this participant: refuse `notOwner`.
5. Check rows 2, 4 and 5 from local inputs: refuse with that state's reason.
6. Return the lease, carrying `owner` and `generation`.
```

Every refusal closes the lock first. Admission never waits, so it can run where the trigger is handled, but it never runs from an audio callback. A second operation in the same process is refused `busy`, because `flock` belongs to the open file description.

**Kinds.** `global` is everything above. `practice` skips steps 4 and 5, so a participant that is not the owner or not ready yet can run the practice it needs. It competes for capture and refuses on an intent, and it never delivers outside the app's own window.

**Holding.** The lease is held through capture, transcription, delivery and Stop. A Stop that arrives with no lease does nothing, which covers a late PTT release after a refused start.

**Revalidating.** Immediately before delivering, `revalidate()` confirms the lock file is still the same inode and the state still has this owner and generation. If it fails, the session keeps its text for explicit recovery and does not paste.

**Text.** A cancelled or invalidated session never pastes later. Its text stays available through the app's own recovery surface, and no text is lost by a refusal or a handoff.

## Handoff

Ownership moves only on a user action, with one exception: [First run](#first-run). Target `T` takes ownership from prior owner `P`, who may be nobody, not running, or a participant that crashed.

| Step | Who | What |
|---|---|---|
| 1 | `T` | Confirms it is ready and the user asked for this. Refuses otherwise |
| 2 | `T` | Under the state lock: refuses `busy` if a live intent exists, otherwise publishes an intent with a new `id` and a 15-second expiry. Posts the notification |
| 3 | `P` | On seeing the intent, refuses new admissions and disarms. Cancels a session in `preparing` at once. Lets `listening` run for at most 5 seconds from `createdAt`, then cancels it. Always lets `delivering` finish. No change to its preference |
| 4 | `T` | Polls the capture lock without blocking, until 10 seconds from `createdAt` |
| 5 | `T` | Holding the capture lock, arms its triggers, retrying until the same deadline. A trigger firing now is refused `busy` by `T`'s own lock |
| 6 | `T` | Under the state lock: re-reads, and requires the intent to have its `id` and be unexpired, and `generation` to be the value it saw in step 2. Publishes `owner: T`, `previous: P`, `generation + 1`, `intent: null`. Posts the notification |
| 7 | `T` | Releases the capture lock. It is now `owned` |
| 8 | `P` | Reevaluates to `available`, or `off` if its preference is off, and stays disarmed |

The handoff is confirmed when step 6 lands. It means `P` holds no lease, because `T` held the capture lock, and `T` is armed. Nothing changes hands during a delivery, because a delivery holds the lease.

**Rollback.** Before step 6 the owner has not changed. On any failure, `T` disarms, clears its own intent if the `id` still matches, releases the lock and reports it.

| Failure | Outcome | What the user sees |
|---|---|---|
| `P` still holds the lock at the deadline | `timedOut`, nothing changes | Named app is busy. The way out is to retry or quit it. `T` never kills `P` |
| `T` cannot arm a trigger | `triggerConflict`, nothing changes | Which shortcut conflicts |
| Intent replaced or expired | `superseded`, nothing changes | Retry |
| `T` crashes before step 6 | Lock freed, intent expires in at most 15 seconds, `P` resumes | Nothing, or a short `transferring` |
| `P` crashes | Lock freed, `T` continues | Nothing |
| `T` crashes after step 6 | `T` stays owner | See [Recovery](#recovery) |

**Other changes.** All take both locks and are user actions:

- **Turning off in the owner:** the app cancels its own session, takes the capture lock with a 10-second limit, and publishes `owner: null`, `previous: self`, `generation + 1`. If the lock stays busy, the state is `off` anyway and the app retries on reevaluation.
- **Reset after `corruptState`:** publishes `owner: null`, `generation: 1`, `previous: null`.

## First run

A participant may claim ownership with no user action only if all of these hold: the state file is missing, its preference is on, it is not a Dev participant, and it is declared as the existing owner by its own migration. Only Portavoz's first version with this protocol does this, so an existing user keeps dictating. It takes both locks without waiting, re-checks that `generation` is 0, and publishes `generation: 1`. If a lock is busy, it retries on reevaluation.

Secreteo never claims at first run. Its user takes ownership after onboarding, through a handoff from nobody.

## Reevaluation

Re-derive the state on each admission, session start, app activation, and ownership change.

These are hints that prompt a re-read and never decide anything: the notification, app launch and termination, sleep and wake.

- **Notification:** `notify_post("com.johnny4young.dictation-ownership.changed")`, with no payload.
- **Reading another app's preferences:** discovery only, with `CFPreferencesAppSynchronize` first. Never written. A missing domain must not be created.

## Non-cooperating peers

Some versions of a known peer app run dictation with no knowledge of this protocol. Each participant carries a list of known peers, with each peer's preference key. The values for Portavoz are in [PROVENANCE](../PROVENANCE.md#ownership-protocol-peers).

A build declares itself with an Info.plist key:

| `DictationOwnershipProtocol` | Meaning |
|---|---|
| Absent | Does not cooperate |
| `0` | Has no global capture at all. Ignored as a peer |
| `1` or higher | Implements that version |

A peer is **active** when a running app has a known identifier, no declaration, and its preference on. Then the participant reports `unavailable(legacyPeerActive)`, arms nothing, and gives one instruction: update that app or turn off dictation in it. Practice stays usable.

Not running means not active, and the launch notification re-checks. This can only refuse, so a wrong read cannot admit anything. Known limits, both accepted because the protocol is cooperative: a session can already be running when such a peer launches, and an updated bundle on disk can declare the key for a moment while the old process still runs.

## Recovery

| Event | Owner | Lock | What happens |
|---|---|---|---|
| Crash or SIGKILL of the owner | Unchanged | Freed by the kernel | Others are still refused `notOwner`. On relaunch the owner is admitted again |
| Quit, including an update relaunch | Unchanged | Freed | Same |
| Owner uninstalled | Unchanged, since nothing runs to change it | Free | Others stay `available` and offer a way back |
| Permission revoked or engine missing | Unchanged | The session fails through its normal path, keeps its text, releases | `unavailable(reason)`, offering to fix it or move ownership |
| Sleep | Unchanged | The app cancels anything not `delivering` and releases. A lease survives if it does not, and stays safe | Reevaluates on wake |
| Owner turned off | `null` | | Other apps with their preference on become `available`, and none claims by itself |

A surviving participant whose owner is not running offers two actions: open that app, or return to this one, which is a normal handoff. Hiding "open" when the app no longer exists relies on a hint and is only a UI choice. Nothing turns on the microphone by itself, and no path writes `false` or `true` to a user's preference.

A wedged holder keeps the lock, since only process death releases it. Handoffs time out and name it, and the way out belongs to the user.

## Dev and Release

Both share these files and the same exclusion: only one capture across all of them. They keep their own databases, preferences and shortcuts.

- A Dev participant never takes ownership without a user action in that session, and never claims at first run.
- Tests and UI tests pass a scratch root. The root is a constructor parameter, with no environment variable or argument that moves it in a shipped build.

## Versioning

A change clients must understand raises `version`. An older client then fails closed with `newerProtocol` until updated, which is the correct behavior for global capture.

## What Portavoz has to do

1. Add one admission port, and route every entry point in [Admission](#admission) through it, including those that call the controller directly. Prewarm follows [States](#states).
2. Set `DictationOwnershipProtocol` to `1` in shipping and Dev builds.
3. Claim at [First run](#first-run) when its preference is on.
4. Never write its preference because of ownership. Offer the two actions in [Recovery](#recovery).
5. The version that removes dictation sets the key to `0`. If it finds itself owner on first launch, it publishes `owner: null`.

## Acceptance matrix

Passing means: at most one global capture or delivery admitted, no duplicate paste, explicit recovery, no text lost. The reference implementation proves each row without real triggers or a microphone.

| Scenario | Expected |
|---|---|
| Simultaneous launch | Only the owner is admitted. With no state file, at most one first-run claim lands |
| Toggle, both alive, active and inactive | Generation rises by 1 per change, with no overlap |
| Handoff during `preparing` | Session cancelled at once, handoff completes |
| Handoff during `listening` | Ends or is cancelled by 5 seconds. Text kept, no late paste |
| Handoff during `delivering` | Delivery finishes under the lease, then the handoff completes |
| Handoff with a wedged holder | `timedOut`. Owner and generation unchanged, intent cleared |
| Late PTT release | Stop after a refused start does nothing. Stop after a handoff began still ends its own session |
| Crash or SIGKILL of the holder | Lock freed, owner unchanged, others refused, recovered only explicitly or by relaunch |
| Crash of `T` during a handoff | Intent expires, `P` is admitted again, owner unchanged |
| Sleep and wake | A clock jump expires an intent. A held lease stays exclusive |
| Upgrade | Owner survives the relaunch. A higher `version` fails closed and leaves the file byte-identical |
| Uninstall | Other apps stay `available`, and only a user action moves ownership |
| Permission revoked | Owner reports `unavailable`, refused, no ownership change |
| Engine missing | Same |
| Preference off | Never armed, never offered, and the file does not change |
| Dev and Release | Dev is refused without confirmation and admitted only after a confirmed handoff. One capture across both |
| Non-cooperating peer | `legacyPeerActive`, nothing armed, practice allowed. A `0` declaration is ignored |
| Back to the previous owner | A normal handoff, with `previous` updated |
| Corrupt state | `unavailable`, refused, recovers only through reset |
| Replaced lock file | A later client detects it, and `revalidate()` refuses delivery |

Not covered, and tracked in [GAPS](../GAPS.md#g8-ownership-on-a-network-home): home directories on network volumes.
