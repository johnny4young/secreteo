# Contributing to Secreteo

By participating, you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). Report security problems through the process in [SECURITY.md](SECURITY.md), never in a public issue.

## Ground rules

- **Privacy is non-negotiable.** No feature may send audio or dictated text off the device without explicit, visible opt-in.
- **Swift 6 strict concurrency.** No `@unchecked Sendable` without a comment justifying it.
- **License hygiene.** The project is MIT. Do not copy code from GPL projects: ideas are fine, code is not. MIT and Apache sources are fine with attribution.
- **Controls are testable.** Every interactive control gets an `accessibilityIdentifier` and an XCUITest assertion.
- **Explain the code, not the ticket.** No private tracker keys, sprint names or agent-session names in identifiers, comments or docs.
- **Keep local work local.** Scratch plans, result bundles and ad-hoc screenshots are ignored. Durable behavior and decisions belong in `docs/`.

## Workflow

1. Open an issue before a large PR.
2. Branch from `main` and use [Conventional Commits](https://www.conventionalcommits.org).
3. Run the gates before pushing:

   ```sh
   swift build -Xswiftc -warnings-as-errors
   swift test --parallel -Xswiftc -warnings-as-errors
   swiftlint lint --strict --no-cache
   scripts/check-repository-hygiene.sh
   python3 -I -m unittest discover -s Tests/Tooling -p 'test_*.py'
   ```

4. Fill in the PR template, including how to test the change.

The full definition of a finished PR is in [docs/QUALITY.md](docs/QUALITY.md).
