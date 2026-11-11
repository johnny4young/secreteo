# Quality

## A finished PR

Hosted CI is green on the final head, no mechanical review threads are open, and the description matches that head. Tests, budgets and thresholds are never loosened to reach green.

## CI

`gate` is the only required check. `scripts/ci_gate.mjs` decides it: a job may be skipped only when the validated scope from `scripts/ci_changes.mjs` says so, and never because of who authored a change. A docs-only change skips the macOS jobs. The handoff lane runs only when delivery or triggers change, and the release dry run only when packaging changes. `nightly.yml` runs both, plus the Full UI plan in two parallel halves, every night. `scripts/ui_test_shards.mjs` splits the UI test classes by test count, so a new class needs no list; keep one test class per file. For PR evidence from tests outside the smoke plan, dispatch only the UI lanes, because the macOS runners are shared across repositories: `gh workflow run nightly.yml --ref <branch> -f ui_only=true`.

`unit` restores the `.build` that `build-cache.yml` saves on `main` after each push that touches code, and daily, so it fetches no packages and rebuilds only what the pull request changed. `build-cache.yml` restores its last cache first and builds default products and test bundles with one `swift build --build-tests` invocation. Pull requests only restore; their caches would evict main's. A stalled download counts as a miss, and a changed `Package.swift` builds cold, because products of a removed target would still satisfy its imports. `Tests/Tooling/test_build_cache.mjs` checks that both jobs agree on key, toolchain and compiler arguments, and rejects missing test products or weaker diagnostics.

A push to `main` skips macOS jobs only when `scripts/ci_reuse_gate.mjs` proves that exactly one merged pull request has the same valid tree and a successful `gate` in the latest attempt of its newest CI run, which must itself be complete and successful. Bounded API pages must be complete, and the proof gives up after 45 seconds of API calls; the job run, attempt and head must match. The helper rechecks the latest run/attempt after reading jobs, so a new run or rerun invalidates reuse. Missing, malformed, truncated, failed or changing evidence runs every job. The proof, scope classifier and required gate use Node; remaining legacy tooling stays mandatory in CI. The scope pipeline fails if classification fails, even when writing GitHub outputs through `tee`.

The UI launcher uses Node from `.nvmrc` to select shards and process xcresult summaries and screenshot attachments. `node --test Tests/Tooling/test_ui_shards.mjs Tests/Tooling/test_ui_results.mjs Tests/Tooling/test_build_cache.mjs Tests/Tooling/test_ui_inventory.mjs` runs in hygiene; CI, nightly and release verification provision that runtime explicitly. The shard CLI accepts safe ASCII decimal integers for the internal `index/count` arguments. Smoke selection preserves its final line without a newline and rejects an empty plan instead of running the full suite. Other tooling still uses Python.

The existing CI and nightly screenshot artifacts also retain `test-results.json` after successful and failed UI test executions. It records the checkout SHA at capture time, Actions run/attempt, exact selection arguments and test exit code, plus the xcresult summary and test tree in schema 0.1.0. Failed exports, invalid counts and malformed test trees remain explicit partial captures. Capturing results alone does not declare tests passed.

Before building, the launcher saves `test-inventory.json` from the selected plan and the same source discovery used for shards. Smoke must name one to ten distinct methods in their actual classes; full plans must select the computed shard or the whole catalog. After capture, `test-validation.json` records whether there is exactly one Passed case for every expected method, without skips, expected failures, missing or extra cases, and with matching summary counts. Nested `Test Case Run` records are not counted twice. Invalid plans fail before the native build; failed capture or qualification fails an otherwise successful lane. Capture and qualification preserve a nonzero UI test exit. Raw receipts remain intact for diagnosis. These artifacts do not certify a clean build tree or physical acceptance; reviewers still verify run, head and artifact provenance.

The settings activation smoke checks its required controls from one accessibility snapshot. Each identifier absent from that snapshot still gets its original five-second existence wait; a failed snapshot falls back to those individual waits. The identifier inventory, absence checks and interaction assertions are unchanged.

The Settings scroll helper ends each directional search when its control is hittable, rather than querying it for the rest of that loop's iterations. It retains the foreground guard, directional scroll limits and final existence/hittability wait. This does not change the selected tests or their assertions.

Packaging logs `PackageTiming` records for preparation, build, copy, signing, disk-image creation and verification, plus a successful total. Records contain elapsed whole seconds from Bash and the exit status, without command arguments. An exit trap reports nonzero exits from an active stage while preserving the status; an unsuccessful package has no success total. Interrupted runs can lack stage completion records. Dry-run builds use Xcode's full build log with its command timing summary; production keeps quiet build output. These records distinguish packaging stages from the full release dry-run and its runner setup; compiler task times can overlap and must not be summed as elapsed time. Production notarization remains part of the total, outside these individual stages. Timings alone do not establish a speedup or certify the CI budget.

## Local gates

Run in series.

Repository hygiene runs with Bash and Node, including its scratch-repository negative tests. In CI, `hygiene` and `legacy-tooling` run concurrently on separate Linux runners; `gate` requires both to succeed, including on docs-only changes. The legacy job retains the complete `python3 -I -m unittest discover -s Tests/Tooling -p 'test_*.py'` command. Release verification still runs that command immediately after hygiene in its mandatory `verify` job. A local hygiene pass does not claim those legacy suites ran; their hosted coverage remains required while they are migrated. Evaluate the combined hygiene budget using both branches, including runner setup, rather than the shorter job alone; parallel jobs may add total runner time.

The serial legacy runner, controller and comparison tests generate one process-local synthetic 480-cell audio template and copy it into a new owned directory for each fixture. Copies preserve bytes and modes without hardlinks, so mutation/deletion tests remain isolated, and the template is removed explicitly at exit. The producer's own tests still materialize fresh corpora; this fixture reuse is not audio quality evidence.

| Gate | Command | When |
|---|---|---|
| Strict build | `swift build -Xswiftc -warnings-as-errors` | Any Swift change |
| Strict tests | `swift test --parallel -Xswiftc -warnings-as-errors` | Any Swift change |
| Lint | `swiftlint lint --strict --no-cache` | Any Swift change |
| Hygiene | `scripts/check-repository-hygiene.sh` | Always |
| Legacy tooling | `python3 -I -m unittest discover -s Tests/Tooling -p 'test_*.py'` | Swift, script or tooling changes |
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
- `.nvmrc` and `engines.node` agree.
- Tests that build session dependencies by hand choose their stop tail; fixture dependencies skip the real one. This check and the log checks run in Node during local hygiene and CI. Their shared Git discovery reads NUL-delimited tracked/untracked paths, including spaces, Unicode and embedded newlines, and rejects malformed UTF-8 source.
- Logs carry no dictated text: no value is logged as public, crash messages are plain literals, and only the MCP command prints, to stdout.

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
