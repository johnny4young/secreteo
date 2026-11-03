# Dictation ownership protocol, version 1

Two apps that both listen for the same trigger would start two sessions and paste twice. This protocol keeps one macOS user to at most one admitted global capture or delivery, across Portavoz, Secreteo and their Dev builds ([D15](../DECISIONS.md#d15-one-dictation-owner-per-mac)).

It is cooperative and not a security boundary. Any process running as the user can ignore it or edit its files.

**Status:** `Sources/DictationOwnership` is the reference implementation. `Tests/DictationOwnershipTests` proves the [acceptance matrix](#acceptance-matrix) in scratch folders, with a synthetic app standing in for sessions, triggers and delivery. No real app uses it yet, so it has not run against a real Portavoz, real triggers or a microphone, and each app still has to show that it keeps text and cancels as this document says. If the code and this document disagree, that is a bug in one of them. The locks and discovery come from a [spike](../spikes/ownership-lock-and-discovery.md).

## Terms

| Term | Meaning |
|---|---|
| Participant | An app that implements this protocol, named by its bundle identifier |
| Dev participant | A participant whose identifier ends in `.dev` |
| Owner | The one participant allowed to admit global sessions. May be nobody |
| Preference | The participant's own "global dictation on" setting. The protocol reads it and never writes it |
| Readiness | Microphone and Accessibility granted, engine installed (not necessarily loaded), practice done, and triggers able to arm, as the participant defines them locally |
| Lease | The right to run one operation, which is the capture lock held for that operation |
| Intent | A published request to move ownership, with an expiry |

Three things stay separate: the durable owner (a file), whether a process is running and ready (local), and the temporary right to run a session (a lease). Being one does not imply another.

## Invariants

1. At most one process holds a lease. The kernel enforces this through `flock`, with a new descriptor for each acquisition.
2. `owner` and `generation` change only while the writer holds both locks, so they cannot change during a lease.
3. A global lease is granted only after reading the state under the capture lock and finding this participant as owner, with no live intent, in a known format version.
4. A lease lasts until delivery has finished, the pasteboard is restored, and Stop has drained.
5. Between participants, safety depends only on invariants 1 to 4. Clocks, notifications, process lists and preferences affect what the UI shows and how fast things recover. None of them can admit a second session.

## Files

All files live in `~/Library/Application Support/com.johnny4young.dictation-ownership/`, mode `0700`, excluded from backups so a restore cannot bring back an old owner. An existing folder with group or other access is repaired. Failing to set the backup exclusion does not stop anything, because a restore is the only cost. The name is permanent.

A sandboxed process resolves that path into its container and would lock private files. It must detect the sandbox (`APP_SANDBOX_CONTAINER_ID` in its environment) and report `unavailable(sandboxed)` without creating anything.

| File | Purpose |
|---|---|
| `capture.lock` | Held exclusively for each lease, and during an ownership change |
| `state.lock` | Held briefly around every write to the state file. Never held across a wait |
| `ownership.json` | The state |

**Lock order:** capture, then state. Marking an intent takes only the state lock, because it has to work while another app's session holds the capture lock.

**Opening a lock:** each acquisition calls `open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)`, then `flock(fd, LOCK_EX | LOCK_NB)`, and owns that descriptor alone.

- Never cache or `dup` the descriptor. `flock` does not conflict with a lock on the same open file description, so a reused one would admit twice.
- `O_CLOEXEC` is required: a child that inherits the descriptor keeps the lock after the parent dies.
- A release calls `flock(fd, LOCK_UN)` and then `close`. Closing alone can leave the lock held for a moment, because a child being spawned holds the open file description until its exec.
- After locking, `fstat(fd)` and `stat(path)` must name the same device and inode. If not, the file was replaced between those calls: close and retry once, then report `ioError`.
- `ENOTSUP` or `EOPNOTSUPP` from `flock` means `unavailable(lockUnsupported)`. This fails closed: a volume without `flock` cannot give this guarantee.
- The state lock is polled for at most 1 second. After that the operation changes nothing and reports `ioError`.
- Lock files are never deleted. An uninstall, including the cask's `zap`, leaves this folder in place. Deleting or replacing one while a participant runs is outside the protocol: a later client cannot detect it, and `revalidate()` stops only the older holder's delivery.

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
| `generation` | Starts at 0 and rises by exactly 1 with each change of `owner`. Marking or clearing an intent does not change it. Only a reset can lower it |
| `previous` | The owner before the last change, or `null`. It only labels the UI's way back and grants nothing |
| `intent` | `null` or as above. `from` is the owner when it was published, which may be `null`. `from` can differ from a later `owner`, because turning off leaves the intent for its target to discard. Times are UTC in whole seconds: `createdAt` is rounded down and `expiresAt` is `createdAt` plus 15 seconds |

An intent is live until `now >= expiresAt`, or until `expiresAt` is more than 15 seconds ahead of `now`, so a clock moved far back cannot pin it. A small backward change can extend it by that amount, which delays recovery and affects nothing else.

A missing file means `owner: null`, `generation: 0`. A file that exists and does not parse or validate reports `unavailable(corruptState)`. That includes an empty file, one over 64 KiB, an empty `owner` or intent participant, and an `expiresAt` that is not `createdAt` plus 15 seconds. Any other read failure reports `ioError`.

**Writes** happen under the state lock: write a temporary file in the same directory, `fcntl(F_FULLFSYNC)`, then `rename`. The rename is the commit point. Any leftover temporary file seen under the state lock is stale and may be removed. Reads need no lock, because the rename is atomic.

The files hold identifiers, a counter and timestamps. Never audio, text, or anything about a session.

## States

Each participant derives its state locally, and re-derives it on every event in [Reevaluation](#reevaluation). The first row that matches wins.

| # | Condition | State | Triggers armed | Prewarm |
|---|---|---|---|---|
| 1 | `lockUnsupported`, `newerProtocol`, `corruptState`, `ioError` or `sandboxed` | `unavailable(reason)` | No | No |
| 2 | A non-cooperating peer is active ([below](#non-cooperating-peers)) | `unavailable(legacyPeerActive)` | No | No |
| 3 | Live intent with this participant as `from` or `to` | `transferring` | Only the target, in step 5 of a [handoff](#handoff) | No |
| 4 | Preference is off | `off` | No | No |
| 5 | Is owner, and not ready | `unavailable(reason)`, naming the missing piece | No | No |
| 6 | Is owner, and ready | `owned` | Yes | Yes |
| 7 | Not owner, and not ready | `preparing` | No | No |
| 8 | Not owner, and ready | `available` | No | No |

Outside that one step, only `owned` arms triggers, so a non-owner gives up exclusive shortcuts and event taps. Disarming is not what keeps a Mac safe: a stale trigger reaches admission and is refused there.

A participant in `available` may offer to take ownership. Secreteo offers it only then, and ships with a shortcut other than ⌥⌘D and with Fn off by default.

Prewarm needs `owned` but no lease. A stale read can waste a model load, not cause a capture. Leaving `owned` disarms the triggers and unloads a prewarmed model, so two apps do not keep one each.

## Admission

Every operation that can capture or deliver globally goes through one port. This covers dictation sessions from any trigger, the menu and Intents, Rewrite, retry, and paste-last. Recording a meeting is not dictation and takes no lease. Reading through MCP does not need one either.

```
acquire(kind) -> lease | refused(reason)

1. Try the capture lock without waiting. Held: refuse `busy`.
2. Read the state under it. Refuse `unavailable(reason)` on any failure in row 1.
3. Live intent: refuse `transferring`.
4. Kind `global`: owner is not this participant: refuse `notOwner`.
5. Kind `global`: re-read rows 2, 4 and 5, not from a cached state: refuse with that state's reason.
6. Return the lease, carrying `owner` and `generation`.
```

Every refusal closes the lock first. Admission never waits, and because it does file I/O it never runs in an audio or event tap callback. A second operation in the same process is refused `busy`, because it opens its own descriptor.

**Kinds.** `global` is everything above. `practice` skips steps 4 and 5, so a participant that is not the owner or not ready yet can run the practice it needs. It competes for capture and refuses on an intent, and it never delivers outside the app's own window.

**Holding.** The lease is held through capture, transcription, delivery and Stop. Each start attempt has its own token, and a Stop acts only on the lease its own attempt received. So the release that follows a refused start does nothing, even while another session holds a lease.

**Watching.** A holder re-reads the state at least once a second, so a missed notification cannot hide an intent.

**Revalidating.** Immediately before delivering, `revalidate()` confirms the lock file is still the same inode and the state still has this owner and generation. If it fails, the session keeps its text for explicit recovery and does not paste.

**Text.** A cancelled or invalidated session never pastes later. Its text stays available through the app's own recovery surface, and no text is lost by a refusal or a handoff.

## Handoff

Ownership moves only on a user action, with one exception: [First run](#first-run). Target `T` takes ownership from prior owner `P`, who may be nobody, not running, or a participant that crashed.

| Step | Who | What |
|---|---|---|
| 1 | `T` | Confirms it is `available` and the user asked for this. Refuses otherwise. A handoff to the current owner does nothing. A participant runs one handoff at a time, through the end of its rollback |
| 2 | `T` | Under the state lock: refuses `busy` if a live intent exists, otherwise publishes an intent with a new `id` and remembers `generation`. Posts the notification |
| 3 | `P` | On seeing the intent, refuses new admissions, disarms, and handles its session by the table below. No change to its preference |
| 4 | `T` | Polls the capture lock without blocking, until 10 seconds after step 2 on a clock that counts sleep |
| 5 | `T` | Holding the capture lock, re-reads its preference, readiness and row 2. Arms its triggers, retrying until the same deadline. A trigger firing now is refused `busy` by `T`'s own lock |
| 6 | `T` | Re-reads its preference, readiness and row 2 again. Under the state lock: re-reads the state, and requires the intent to have its `id` and be live, and `generation` to be the remembered value. Publishes `owner: T`, `previous: P`, `generation + 1`, `intent: null`. Posts the notification |
| 7 | `T` | Releases the capture lock. It is now `owned` |
| 8 | `P` | Reevaluates to `available`, or `off` if its preference is off, and stays disarmed |

| When the intent is seen | What the holder does |
|---|---|
| `preparing`, before the microphone opens | Cancels at once |
| `listening`, microphone open | Runs for at most 5 seconds more, then cancels |
| Microphone closed: transcribing, polishing, delivering, restoring the pasteboard | Runs to the end. A session that has no microphone stage, such as Rewrite or paste-last, is here |
| A practice lease, in any participant | Cancels at once, whoever the intent names |

The rename in step 6 is the commit. It means no one held a lease, because `T` held the capture lock, and `T` was armed. A failure after it, including a failed notification, undoes nothing. Nothing changes hands during a delivery, because a delivery holds the lease.

**Rollback.** Before the commit the owner has not changed. On any failure, `T` always disarms and releases the lock, tries to clear its own intent if the `id` still matches, and posts the notification. If it cannot write, the intent simply expires.

| Failure | Outcome | What the user sees |
|---|---|---|
| Another session still holds the lock at the deadline, even one that is only delivering | `timedOut`, nothing changes and nothing is interrupted | Another session is busy, and the way out is to retry or quit an app. `flock` does not reveal the holder, so no app is named. `T` never kills anything |
| `T` cannot arm a trigger by the deadline | `triggerConflict`, nothing changes | Which shortcut conflicts |
| The operation is cancelled before the commit | `cancelled`, nothing changes | Nothing |
| `T`'s preference, readiness or row 2 changed | `targetNotReady`, nothing changes | What changed |
| Intent replaced or expired, or generation changed | `superseded`, nothing changes | Retry |
| `T` crashes before the commit | Lock freed. `P` rearms when the intent expires, at most 15 seconds later | Nothing, or a short `transferring` |
| `P` crashes | Lock freed, `T` continues | Nothing |
| `T` crashes after the commit | `T` stays owner | See [Recovery](#recovery) |

**Other changes.** All are user actions. Those that write take both locks, re-read the state under them, and apply only if their condition still holds. Otherwise they change nothing.

- **Turning on with no owner:** the same action runs a handoff if the participant is ready, and step 2 refuses it if an owner appeared in the meantime. If not ready, it offers one once it is `available`.
- **Turning off in the owner:** the app cancels its own session, takes the capture lock with a 10-second limit, and publishes `owner: null`, `previous: self`, `generation + 1`, if it is still the owner and its preference is still off. If the lock stays busy, the state is `off` anyway and the app retries on reevaluation.
- **Reset after `corruptState`:** publishes `owner: null`, `generation: 1`, `previous: null`, if the file is still corrupt.

## First run

So that an existing user keeps dictating, Portavoz, from its first version with this protocol until it removes dictation, claims ownership with no user action when all of these hold: `generation` is 0, no intent is live, its preference is on, and it is not a Dev participant. It takes the capture lock without waiting, then the state lock, re-checks those conditions, and publishes `generation: 1`. If the capture lock is busy, it retries on reevaluation.

Secreteo never claims at first run. Its user takes ownership after onboarding, through a handoff from nobody.

## Reevaluation

Re-derive the state on each admission, session start, app activation, ownership change, and change of the participant's own preference or readiness. A participant that sees a live intent also schedules a reevaluation for `expiresAt`, on a timer that fires after wake.

These are hints that prompt a re-read and never decide anything: the notification, app launch and termination, sleep and wake.

- **Notification:** `notify_post("com.johnny4young.dictation-ownership.changed")`, with no payload. A failed or coalesced post affects only how fast others notice.
- **Reading another app's preferences:** discovery only, with `CFPreferencesAppSynchronize` first. Never written. A missing domain must not be created.

## Non-cooperating peers

Some versions of a known peer app run dictation with no knowledge of this protocol. Each participant carries a list of known peers, with each peer's preference key. The values for Portavoz are in [PROVENANCE](../PROVENANCE.md#ownership-protocol-peers).

A build declares itself with an Info.plist key, read from the file on disk at each check, because a `Bundle` caches its dictionary for the life of the process:

| `DictationOwnershipProtocol` | Meaning |
|---|---|
| Absent | Does not cooperate |
| `0` | Has no global capture at all. Ignored as a peer |
| `1` or higher | Implements that version |

A peer is **active** when a running app has a known identifier, no declaration, and its preference on. Then the participant reports `unavailable(legacyPeerActive)`, arms nothing, and gives one instruction: update that app or turn off dictation in it. Practice stays usable.

Not running means not active, and the launch notification re-checks.

Such a peer takes no lock, so this check is best effort. Known limits, accepted because the protocol is cooperative:

- A session can already be running when the peer launches.
- A change the peer has not stored yet reads as its old preference, because synchronizing does not make another process publish.
- An updated bundle on disk can declare the key for a moment while the old process still runs.

## Recovery

| Event | Owner | Lock | What happens |
|---|---|---|---|
| Crash or SIGKILL of the owner | Unchanged | Freed by the kernel | Others are still refused `notOwner`. On relaunch the owner is admitted again |
| Quit, including an update relaunch | Unchanged | Freed | Same |
| Owner uninstalled | Unchanged, since nothing runs to change it | Free | Others keep their state, and only a user action moves ownership |
| Permission revoked or engine missing | Unchanged | The session fails through its normal path, keeps its text, releases | `unavailable(reason)`, offering to fix it or move ownership |
| Sleep | Unchanged | The app cancels a session whose microphone is open, and releases. A lease survives if it does not, and stays safe | Reevaluates on wake |
| Owner turned off | `null` | | Other apps with their preference on stay as they are, and none claims by itself |

A participant in `available` whose owner is not running offers two actions: open that app, or return to this one, which is a normal handoff. Hiding "open" when the app no longer exists relies on a hint and is only a UI choice. Nothing turns on the microphone by itself, and no path writes `false` or `true` to a user's preference.

A wedged holder keeps the lock, since only process death releases it. Handoffs time out, and the way out belongs to the user.

## Dev and Release

Both share these files and the same exclusion: only one capture across all of them. They keep their own databases, preferences and shortcuts.

- A Dev participant takes ownership only through a user action, and never claims at first run. Once it has, it stays owner across relaunches like any other.
- Tests and UI tests pass a scratch root. The root is a constructor parameter, with no environment variable or argument that moves it in a shipped build.

## Versioning

A change clients must understand raises `version`. An older client then fails closed with `newerProtocol` until updated, which is the correct behavior for global capture.

## What Portavoz has to do

1. Add one admission port, and route every entry point in [Admission](#admission) through it, including those that call the controller directly. Prewarm follows [States](#states).
2. Set `DictationOwnershipProtocol` to `1` in shipping and Dev builds.
3. Claim at [First run](#first-run) when its preference is on.
4. Never write its preference because of ownership. Offer the two actions in [Recovery](#recovery).
5. The version that removes dictation sets the key to `0`. If it finds itself owner on first launch, it publishes `owner: null` under both locks.

## Acceptance matrix

Passing means: at most one global capture or delivery admitted among participants, no duplicate paste, explicit recovery, no text lost. The reference implementation proves each row without real triggers or a microphone.

| Scenario | Expected |
|---|---|
| Simultaneous launch | Only the owner is admitted. With no state file, at most one first-run claim lands |
| First-run claim during a handoff from nobody | No claim while the intent is live. The handoff wins, or the claim lands after a rollback |
| Second acquire in one process | Refused `busy`, while the first lease stays valid |
| Release while the process spawns children | The lock is free at once |
| Toggle, both alive, active and inactive | Generation rises by 1 per change, with no overlap |
| Handoff during `preparing` | Session cancelled at once, handoff completes |
| Handoff during `listening` | Ends or is cancelled within 5 seconds. Text kept, no late paste |
| Handoff after the microphone closes | Runs to the end under the lease. Handoff completes if it ends before the deadline, otherwise `timedOut` with nothing interrupted |
| Handoff with a practice lease in a third participant | The practice is cancelled, handoff completes |
| Handoff with a wedged holder | `timedOut`, no app named. Owner and generation unchanged, intent cleared |
| Handoff with a missed notification | The holder sees the intent within a second |
| Target turned off or losing readiness during a handoff | `targetNotReady`, nothing armed, owner unchanged |
| Late PTT release | Stop after a refused start does nothing, even while another session holds a lease. Stop after a handoff began still ends its own session |
| Crash or SIGKILL of the holder | Lock freed, owner unchanged, others refused, recovered only explicitly or by relaunch |
| Crash of `T` before the commit | Intent expires, `P` rearms on its own timer with no other event, owner unchanged |
| Crash of `T` after the commit | `T` stays owner, `P` stays disarmed |
| Failed write during rollback | `T` disarms and releases anyway, and the intent expires |
| Failed notification after the commit | The handoff stands |
| Sleep and wake | An intent past `expiresAt` on wake is expired. A held lease stays exclusive |
| Upgrade | Owner survives the relaunch. A higher `version` fails closed and leaves the file byte-identical |
| Uninstall | Other apps keep their state, and only a user action moves ownership |
| Permission revoked | Owner reports `unavailable`, refused, no ownership change |
| Engine missing | Same |
| Preference off in a non-owner | Never armed, never offered, and the file does not change |
| Turning off in the owner | Publishes `owner: null`. Changes nothing if it lost ownership first |
| Turning on with no owner | Runs a handoff if ready, otherwise offers one when `available` |
| Dev and Release | Dev is refused without a user action and admitted after a confirmed handoff, including after a relaunch. One capture across both |
| Non-cooperating peer | `legacyPeerActive`, nothing armed, practice allowed. A `0` declaration is ignored |
| Back to the previous owner | A normal handoff, with `previous` updated |
| Corrupt state | `unavailable`, refused, recovers only through reset. A reset changes nothing if another one landed first |
| Sandboxed process | `unavailable(sandboxed)`, no files created |
| Lock file replaced between open and lock | Detected and retried. An older holder's `revalidate()` refuses delivery |

Not covered:

- Home directories on network volumes, tracked in [GAPS](../GAPS.md#g8-ownership-on-a-network-home).
- A second macOS user logged in at the same time, who has their own files and locks.
