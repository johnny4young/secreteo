# Decisions

Binding decisions, numbered from D1. `Portavoz Dxxx` points to the [decision log of the app this code came from](https://github.com/johnny4young/portavoz/blob/main/docs/DECISIONS.md). A new decision supersedes an old one explicitly; history is not rewritten.

## D1. Name and identity

Secreteo. Bundle ID `com.johnny4young.secreteo`, Dev `com.johnny4young.secreteo.dev`, repository `johnny4young/secreteo`, cask `secreteo`. The update feed URL is effectively permanent once shipped.

## D2. Scope and approved losses

Secreteo inherits global dictation from Portavoz, which keeps meetings. Three capabilities are deliberately not carried over:

| Loss | Portavoz reference | What replaces it |
|---|---|---|
| Ask over dictations | D580 | Agents read history through MCP |
| Dictation into meeting notes | D579 | Copy and paste |
| Polish with embedded MLX | | Apple Foundation Models and Ollama. A Mac with neither has no Polish or Rewrite |

The single resident model (Portavoz D565) and capture admission (Portavoz D552) do not cross processes. Dictating during a meeting costs RAM and a cold start, and Portavoz no longer pauses background work while you dictate. This is measured before distribution ([G1](GAPS.md#g1-two-apps-at-once)).

## D3. History, stats and search are included

They use GRDB and their own database. The schema starts at v1 from the final shape of history, full-text search and stats, not from a copy of the Portavoz migrations. Consents start off, retention is explicit, and there are no meeting-note links.

## D4. A read-only MCP server of its own

`secreteo-mcp` is a stdio executable (Portavoz D578). Reading does not take the dictation lock.

## D5. Code is copied, not shared

Dictation code is copied from an export of one frozen Portavoz commit and recorded in [PROVENANCE.md](PROVENANCE.md). The two apps then diverge. The model store is the only shared package.

## D6. Build with SwiftPM libraries and a thin XcodeGen target

Logic and views live in libraries so `swift test` covers them. The app target holds `@main`, plist, catalogs and assets, which removes the scripts Portavoz needs because SwiftPM cannot build an app. This departs from Portavoz D20.

## D7. Releases are signed by a tag workflow

A `v*` tag runs `release.yml` in an Environment that requires the owner's approval, with the toolchain CI tested. A local fallback uses the same scripts. Both the app and the DMG are notarized and stapled because Homebrew extracts the app (Portavoz D74).

## D8. VM-granted TCC proves delivery mechanics only

A permission grant on a disposable VM qualifies AX inspection, event dispatch, clipboard handling and receipts. The permission experience, the microphone and the cross-process Fn tap stay in the manual gate. This replaces Portavoz D540 here and keeps the bar from Portavoz D515: a synthetic inserter cannot qualify delivery.

## D9. Shared model folder

`~/Library/Application Support/com.johnny4young.local-models/`. This is permanent, and it is never part of a cask `zap`. App Groups would tie contributors to a signing team, `~/Library/Caches` can be purged by the system, and `Portavoz/Models` is deleted by `brew zap portavoz`.

## D10. Fresh git history

A path filter would mix dictation with shared files, produce commits that never compiled, and carry trailers and PR numbers that would mislink here.

## D11. MIT and free

No GPL code. Mechanisms from GPL projects may inform the design, but no code is copied from them.

## D12. Menu bar through `NSStatusItem`, never without an icon

`NSStatusItem` with `.terminationOnRemoval`, no autosave, and a watchdog, because a `MenuBarExtra` scene can stay registered without painting on macOS 26. An agent with microphone and Accessibility access never runs without a visible icon. The watchdog reacts to the events that can remove the icon, so an announced loss quits within 2.25 s and one no event announces within about 7 s. An external helper is added only if the hidden-icon test reproduces the problem.

## D13. FluidAudio from upstream with no traits

Portavoz's fork is no longer needed for this graph. The pin is 0.18.2, with [paired evidence](spikes/fluidaudio-upstream.md). The pin moves only through explicit review with paired evidence (Portavoz D516), and Dependabot excludes it.

## D14. No URL scheme

A web page must not be able to reach the microphone path.

## D15. One dictation owner per Mac

Two apps on the same Fn hold would start two sessions and paste twice. Ownership goes through a cooperative per-user protocol, specified in [the ownership protocol](specs/ownership-protocol.md). Secreteo does not arm global triggers while a Portavoz version without the protocol has dictation active, and no binary that arms them is published until a Portavoz release with the protocol is out. This is cooperative and not a security boundary. Portavoz takes the `DictationOwnership` product at a pinned revision, so dependencies added to this package reach it when it bumps.

## D16. Security reports through GitHub only

GitHub's private reporting is the only channel. No email address is published until one is known to receive mail.

## D17. Preference import by allowlist, no history import

Import is typed and versioned, with a preview and an idempotent apply. Activation, login, ownership, active shortcuts, agent access, history saving, model consent and egress are never imported.

## D18. The delivery lane signs ad-hoc

The hosted delivery lane signs ad-hoc and grants TCC through `cdhash` rows, written after the final build, on the disposable VM only. It needs no secret. Developer ID signing happens only in `release.yml` ([evidence](spikes/tcc-adhoc-signing.md)).

## D19. The default shortcut is ⌃⌥⌘D

The [ownership protocol](specs/ownership-protocol.md) requires a shortcut other than Portavoz's ⌥⌘D. That one is also the system's Dock shortcut. ⌃⌥⌘D keeps the D and adds a third modifier to make a clash less likely. It has not been checked on a real Mac, and a conflict shows as an unavailable shortcut in Settings.

## D20. Release builds do not run global dictation yet

`SECRETEO_GLOBAL_DICTATION` is off in Release and on in Debug and `make install`. With it off the app does not create `DictationFeature`, so no trigger, event tap or lease can exist. A binary must not arm global dictation before Portavoz's cooperating version ships, and this makes that true of any tag. Turning it on is one line in `project.yml`, after that release.

## D21. A remembered model shows as ready while its hash runs

Secreteo keeps, between launches, what a model's files looked like after their last clean hash: inode, size and both timestamps of each file and directory. While it matches, the model reads as ready during the first hash of a launch, so the shortcut works at once and Settings does not offer a download for an installed model. The hash still runs and takes this back if the bytes are bad, and a load still needs `verifiedInstallation`, so the record can never put unverified files in front of a loader. `LocalModelStore` asks callers not to infer readiness from their own file checks. This is the one exception, and it applies only until that first hash ends.

## D22. The voice detector is part of the model download

Settings offers the download until Parakeet and Silero are both verified, and a failure of either shows and can be retried. Only Parakeet holds dictation back: without Silero the speech gate fails open, so dictation keeps working and can paste silence until the download succeeds.
