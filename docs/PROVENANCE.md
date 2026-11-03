# Provenance

Secreteo starts from a fresh git history ([D10](DECISIONS.md#d10-fresh-git-history)). This file maps each copied file to its origin. Both source projects are MIT, by the same author.

## Dictation code

Copied from an export (`git archive`) of one frozen commit of [`johnny4young/portavoz`](https://github.com/johnny4young/portavoz).

**Frozen commit:** set when porting begins.

| Secreteo path | Portavoz path |
|---|---|

## Repository bootstrap

Adapted from `johnny4young/portavoz@cffa87bb36f800108bd8e366bbaa153e2c9ec88f`.

| Secreteo path | Portavoz path | Change |
|---|---|---|
| `.swiftlint.yml` | `.swiftlint.yml` | Lints `Apps` and `Sources`; drops Portavoz identifier exceptions |
| `.github/dependabot.yml` | `.github/dependabot.yml` | Comment reworded |
| `.github/pull_request_template.md` | `.github/pull_request_template.md` | New structure, with the checklist kept |
| `.github/ISSUE_TEMPLATE/*` | `.github/ISSUE_TEMPLATE/*` | Dictation areas |
| `CODE_OF_CONDUCT.md` | `CODE_OF_CONDUCT.md` | Reports through GitHub; no email |
| `CONTRIBUTING.md` | `CONTRIBUTING.md` | Module rules removed |
| `SECURITY.md` | `SECURITY.md` | Dictation commitments; no email |
| `scripts/verify-ci-toolchain.sh` | `scripts/verify-ci-toolchain.sh` | None |
| `scripts/run-ci-swiftlint.sh` | `scripts/run-ci-swiftlint.sh` | Scratch prefix |
| `scripts/install-ci-xcodegen.sh` | `scripts/install-ci-xcodegen.sh` | None |
| `scripts/check-repository-hygiene.sh` | `scripts/check-repository-hygiene.sh` | Keeps tracked-file, ticket and action-pin checks; adds identifier ratchet, license, attribution, accent-bar and Node checks |

## Shell

| Secreteo path | Source | Change |
|---|---|---|
| `scripts/fetch-sparkle.sh` | `johnny4young/gancho`, `scripts/fetch-sparkle.sh` (MIT, same author) | Comments |

## Spikes

| Secreteo path | Source | Change |
|---|---|---|
| `spikes/tcc-adhoc/grant.py` | `johnny4young/gancho`, `scripts/prepare-hosted-handoff-permissions.py` (MIT, same author) | One app, `cdhash` requirements only |

## Other projects compared

Portavoz's dictation sources were compared with [Megaphone](https://github.com/Kuberwastaken/megaphone) (MIT, Copyright Kuber Mehta and Zach Latta) at `5a9136b3`. None of its distinctive types appear in Portavoz, and the 77 long lines the two share are generic SwiftUI, AppKit and Foundation calls. This comparison cannot detect a rewrite. No Megaphone code is knowingly imported, so its notices are not included. If any derivation is found, both copyright lines go in the derived file and in the notices.

## Ownership protocol peers

The [ownership protocol](specs/ownership-protocol.md) has to recognize Portavoz builds that do not cooperate, so it needs these values:

| Value | Portavoz |
|---|---|
| Release identifier | `app.portavoz.mac` |
| Dev identifier | `app.portavoz.mac.dev` |
| Preference key | `globalDictationEnabled`, off when absent |

## Identifier ratchet

These source-app identifiers are rejected everywhere except this file and the notices:

`app.portavoz`, `PORTAVOZ_`, `PVDesign`, `"PVOZ"`, `0x5056_4F5A`, `Apuntador`, `CloudKit`, `PortavozSourceCommit`, `portavozLocalized`, `portavoz-ui-tests`, `Application Support/Portavoz`.

## Release tooling

Adapted from `johnny4young/gancho@d747c028ffb5af4a9430bc43d63f581520a03458`.

| Secreteo path | Gancho path | Change |
|---|---|---|
| `.github/workflows/release.yml` | `.github/workflows/release.yml` | Separates signing from write access; creates a draft; no provisioning profile |
| `.github/workflows/update-cask.yml` | `.github/workflows/update-cask.yml` | Runs on publish and refuses a draft |
| `.github/workflows/pages.yml` | `.github/workflows/pages.yml` | Node from `.nvmrc`; no site script |
| `scripts/package-release.sh`, `scripts/sign-app.sh` | `scripts/package-macos-dmg.sh` | Adds the dry-run mode; signs before notarizing with no ignored failures |
| `scripts/generate-appcast.sh` | `scripts/generate-appcast.sh` | Embeds notes; the requirement checks moved to `scripts/verify_appcast.py` |
| `scripts/update-homebrew-tap.sh` | `scripts/update-homebrew-tap.sh` | Cask only; fails without a key; pins GitHub's host key |
