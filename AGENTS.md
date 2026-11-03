# AGENTS.md

Secreteo: a menu bar app for global, local, private dictation on macOS, built with Swift 6 and SwiftUI. This is the operating guide; project knowledge lives in `docs/`.

## Where things live

| Topic | File |
|---|---|
| Implemented structure and dependency rules | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Binding decisions | [docs/DECISIONS.md](docs/DECISIONS.md) |
| Known limits and unresolved work | [docs/GAPS.md](docs/GAPS.md) |
| Gates and the definition of a finished PR | [docs/QUALITY.md](docs/QUALITY.md) |
| Release recipe | [docs/RELEASING.md](docs/RELEASING.md) |
| Runtime contracts | [docs/specs/](docs/specs/README.md) |
| Origin of copied code | [docs/PROVENANCE.md](docs/PROVENANCE.md) |

Update the document whose truth changed in the same commit. Tracked docs are written in English.

## Commands

```sh
swift build -Xswiftc -warnings-as-errors
swift test --parallel -Xswiftc -warnings-as-errors
swiftlint lint --strict --no-cache
scripts/check-repository-hygiene.sh
make project        # generate Secreteo.xcodeproj from project.yml; never edit it by hand
make test-ui-smoke  # takes over the screen; CI runs it on every PR
make release-dryrun  # packages two versions and a feed with a throwaway key
make install        # installs the Dev identity to /Applications/Secreteo Dev.app
```

## Rules for every change

- **Privacy:** audio and text stay on the device unless the user explicitly opts in. No audio or dictated text in logs.
- **Swift 6 strict concurrency**, warnings as errors. No `@unchecked Sendable` without a comment saying why it is safe.
- **License:** MIT. Never copy code from GPL projects. Mechanisms are fine, code is not. MIT and Apache sources need attribution in `THIRD-PARTY-NOTICES.md`.
- **Ported code:** copy from an export of the frozen source commit, rename, and record every file in `docs/PROVENANCE.md`. Refactors go in a separate PR so the diff stays comparable.
- **Commits:** Conventional Commits in English. Never add AI co-authorship or generated-by lines to commits, PRs, tags or releases.
- **Comments:** short, and only for the why. No ticket keys, PR numbers or incident stories in source.
- **UI:** every control gets an `accessibilityIdentifier` and an XCUITest assertion in the same change. No left accent bars on any surface. No taglines or helper copy; fix the layout instead.
- **Verify UI with XCUITest first.** Use computer-use only when XCUITest cannot reach the surface, and say why.
- **Tests use scratch roots** and synthetic data, and never a real library or a production install of another app.
- **Changelog:** every user-visible change adds one short English entry to `CHANGELOG.md`. Internal work gets none.
- **Node:** the current LTS line in `.nvmrc`, with `engines.node` at its newest patch.
- **Never loosen a test, budget or threshold** to reach green.
- **Keep local work local:** plans, tickets, result bundles and ad-hoc screenshots are ignored. `scripts/check-repository-hygiene.sh` enforces this.
