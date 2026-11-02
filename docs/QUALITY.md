# Quality

## A finished PR

Hosted CI is green on the final head, no mechanical review threads are open, and the description matches that head. Tests, budgets and thresholds are never loosened to reach green.

## Local gates

Run in series.

| Gate | Command | When |
|---|---|---|
| Strict build | `swift build -Xswiftc -warnings-as-errors` | Any Swift change |
| Strict tests | `swift test --parallel -Xswiftc -warnings-as-errors` | Any Swift change |
| Lint | `swiftlint lint --strict --no-cache` | Any Swift change |
| Hygiene | `scripts/check-repository-hygiene.sh` | Always |
| UI | Smoke plan | UI or its owners change |
| Install | `make install`, to the Dev identity | UI changes |
| Models | `make test-model-gated` | Engines, catalog or FluidAudio change |
| Regression | The test fails without the fix: revert, run, restore | Every bug fix |
| Negative | Combinations that must fail, in `Tests/Tooling` | CI, `gate`, or hygiene changes |

## What hygiene enforces

- No local, generated or ignored files are tracked. No conflict markers.
- No private ticket references.
- No identifiers from the source app outside `docs/PROVENANCE.md` and the notices.
- No GPL license markers outside the notices.
- No AI attribution in commit messages.
- Actions pinned to full commit SHAs.
- No left accent bars in web styles.
- Test files stay under 2,400 lines.
- `.nvmrc` and `engines.node` agree.

## Ported code

A port PR holds the copy and the renames, with no mixed refactor. A diff normalized against the export of the frozen commit shows only renames and the seams declared in the description.

## Screenshots

Synthetic data only, from seed fixtures. Each image is opened and checked before it is published.

## Release contract

No 1.0 without all of these, even if smoke is green:

- Strict unit tests in full.
- Full UI plan in English, Spanish catalogs complete.
- Physical delivery and TCC.
- Total memory within budget.
- No audio or dictated text in logs.
- Database upgrade and rollback in scratch.
- A real Sparkle update.
- Signature, notarization and permissions.
