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
| `scripts/check-repository-hygiene.sh` | `scripts/check-repository-hygiene.sh` | Keeps tracked-file, ticket and action-pin checks; adds identifier ratchet, license, attribution, accent-bar and Node checks |

## Spikes

| Secreteo path | Source | Change |
|---|---|---|
| `spikes/tcc-adhoc/grant.py` | `johnny4young/gancho`, `scripts/prepare-hosted-handoff-permissions.py` (MIT, same author) | One app, `cdhash` requirements only |

## Other projects compared

Portavoz's dictation sources were compared with [Megaphone](https://github.com/Kuberwastaken/megaphone) (MIT, Copyright Kuber Mehta and Zach Latta) at `5a9136b3`. None of its distinctive types appear in Portavoz, and the 77 long lines the two share are generic SwiftUI, AppKit and Foundation calls. This comparison cannot detect a rewrite. No Megaphone code is knowingly imported, so its notices are not included. If any derivation is found, both copyright lines go in the derived file and in the notices.

## Identifier ratchet

These source-app identifiers are rejected everywhere except this file and the notices:

`app.portavoz`, `PORTAVOZ_`, `PVDesign`, `"PVOZ"`, `0x5056_4F5A`, `Apuntador`, `CloudKit`, `PortavozSourceCommit`, `portavozLocalized`, `portavoz-ui-tests`, `Application Support/Portavoz`.
