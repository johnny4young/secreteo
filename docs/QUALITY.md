# Quality

## A finished PR

Hosted CI is green on the final head, no mechanical review threads are open, and the description matches that head. Tests, budgets and thresholds are never loosened to reach green.

## CI

`gate` is the only required check. `scripts/ci_gate.py` decides it: a job may be skipped only when the validated scope from `scripts/ci_changes.py` says so, and never because of who authored a change. A docs-only change skips the macOS jobs. The handoff lane runs only when delivery or triggers change, and the release dry run only when packaging changes. `nightly.yml` runs both, plus the Full UI plan in two parallel halves, every night. `scripts/ui_test_shards.mjs` splits the UI test classes by test count, so a new class needs no list; keep one test class per file. For PR evidence from tests outside the smoke plan, dispatch only the UI lanes, because the macOS runners are shared across repositories: `gh workflow run nightly.yml --ref <branch> -f ui_only=true`.

`unit` restores the `.build` that `build-cache.yml` saves on `main` after each push that touches code, and daily, so it fetches no packages and rebuilds only what the pull request changed. That job restores its last cache first and builds default products and test bundles with one `swift build --build-tests` invocation. Pull requests only restore; their caches would evict main's. A stalled download counts as a miss, and a changed `Package.swift` builds cold, because products of a removed target would still satisfy its imports. `Tests/Tooling/test_build_cache.mjs` checks that both jobs agree on key, toolchain and compiler arguments, and rejects missing test products or weaker diagnostics.

`main` requires branches to be up to date, so a merge lands the tree its pull request proved. A push to `main` skips the macOS jobs only when `scripts/ci_reuse_gate.py` finds that merged pull request, the same tree at its head, and a passing `gate` in that head's newest CI run. Any doubt or API error runs every job.

The UI launcher uses Node from `.nvmrc` to select shards and process xcresult summaries and screenshot attachments. `node --test Tests/Tooling/test_ui_shards.mjs Tests/Tooling/test_ui_results.mjs` runs in hygiene; CI, nightly and release verification provision that runtime explicitly. The shard CLI accepts safe ASCII decimal integers for the internal `index/count` arguments. Other tooling still uses Python.

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
| Release | `make release-dryrun` | Packaging or the updater change |
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
- Tests that build session dependencies by hand choose their stop tail; fixture dependencies skip the real one.
- Logs carry no dictated text: no value is logged as public, crash messages are plain literals, and only the MCP command prints, to stdout.
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
