#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0

report() {
  echo "$1" >&2
  echo "$2" >&2
  failures=1
}

for required in LICENSE README.md AGENTS.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md \
  CHANGELOG.md THIRD-PARTY-NOTICES.md docs/PROVENANCE.md; do
  if [[ ! -f "$required" ]]; then
    report "Required file is missing:" "$required"
  fi
done

if [[ "$(readlink CLAUDE.md || true)" != "AGENTS.md" ]]; then
  report "CLAUDE.md must be a symlink to AGENTS.md:" "$(ls -l CLAUDE.md 2>&1 || true)"
fi

forbidden_tracked='^(\.agents|\.claude|\.codex|\.planning|\.tickets|plans|tickets|docs/plans|docs/tickets|artifacts|screenshots|test-results)/|^docs/ROADMAP\.md$|^planning_.*\.md$|(^|/)(DerivedData|xcuserdata)/|\.xcodeproj/|\.xcresult/|\.profraw$|\.profdata$|\.xcactivitylog$'
tracked_forbidden="$(git ls-files | grep -E "$forbidden_tracked" || true)"
if [[ -n "$tracked_forbidden" ]]; then
  report "Ephemeral or generated files must not be tracked:" "$tracked_forbidden"
fi

tracked_ignored="$(git ls-files -ci --exclude-standard || true)"
if [[ -n "$tracked_ignored" ]]; then
  report "Tracked files also match .gitignore:" "$tracked_ignored"
fi

conflict_markers="$(git grep --untracked -nEI '^(<{7}|\|{7}|>{7})( |$)' -- . || true)"
if [[ -n "$conflict_markers" ]]; then
  report "Unresolved merge-conflict markers:" "$conflict_markers"
fi

private_ref_pattern='(^|[^[:alnum:]_])(ENG|JIRA|TICKET|TASK|STORY|EPIC|SPIKE|PORTAVOZ|SECRETEO|PV|APT|APUN)-[0-9]{1,6}([^[:alnum:]_]|$)'
ticket_refs="$(git grep --untracked -nEI "$private_ref_pattern" -- . || true)"
if [[ -n "$ticket_refs" ]]; then
  report "Private ticket references:" "$ticket_refs"
fi

# Bracketed so the patterns do not match this file.
source_app_identifiers='app[.]portavoz|PORTAVOZ[_]|PV[D]esign|"PV[O]Z"|0x5056_?4F5[A]|A[p]untador|Cloud[K]it|PortavozSource[C]ommit|portavozLocal[i]zed|portavoz-ui-test[s]|Application Support/Portavo[z]'
leaked_identifiers="$(
  git grep --untracked -nEI "$source_app_identifiers" -- . \
    ':(exclude)docs/PROVENANCE.md' ':(exclude)THIRD-PARTY-NOTICES.md' \
    ':(exclude)Sources/DictationSession/KnownDictationPeers.swift' || true
)"
if [[ -n "$leaked_identifiers" ]]; then
  report "Source-app identifiers belong only in docs/PROVENANCE.md, the notices and the peer list:" "$leaked_identifiers"
fi

# The hosted runner's home is public and appears in VM-only guards.
private_paths="$(git grep --untracked -nEI '/Users/[a-z0-9]|PortavozFiel[d]' -- . | grep -v '/Users/runner/' || true)"
if [[ -n "$private_paths" ]]; then
  report "Private local paths:" "$private_paths"
fi

gpl_markers="$(
  git grep --untracked -nEIi 'SPDX-License-Identifier:[[:space:]]*(A|L)?GPL|GNU (Affero |Lesser )?General Public License' -- . \
    ':(exclude)THIRD-PARTY-NOTICES.md' || true
)"
if [[ -n "$gpl_markers" ]]; then
  report "GPL license markers:" "$gpl_markers"
fi

if git rev-parse --verify --quiet HEAD >/dev/null; then
  attributed_commits="$(
    git log --format='%h %B' | grep -EIi \
      'co-authored-by:.*(claude|anthropic|copilot|codex|openai|chatgpt|gemini|cursor)|generated (with|by) .*(claude|copilot|codex|chatgpt|gemini|cursor)' || true
  )"
  if [[ -n "$attributed_commits" ]]; then
    report "Commit messages must not carry AI attribution:" "$attributed_commits"
  fi
fi

if compgen -G '.github/workflows/*.yml' >/dev/null; then
  mutable_actions="$(
    grep -nE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]+[^[:space:]]+@' .github/workflows/*.yml \
      | grep -Ev '@[0-9a-f]{40}([[:space:]]|#|$)' || true
  )"
  if [[ -n "$mutable_actions" ]]; then
    report "GitHub Actions must use full-length commit SHAs:" "$mutable_actions"
  fi
fi

accent_bars="$(
  git grep --untracked -nEI 'border-(left|inline-start)[[:space:]]*:|(^|[^[:alnum:]-])border-(l|s)-[0-9]' -- \
    '*.css' '*.html' '*.jsx' '*.tsx' || true
)"
if [[ -n "$accent_bars" ]]; then
  report "Left accent bars are not allowed:" "$accent_bars"
fi

if [[ -d Tests ]]; then
  oversized_tests="$(
    find Tests -name '*.swift' -exec wc -l {} + \
      | awk '$2 != "total" && $1 > 2400 { print $1 " " $2 }' || true
  )"
  if [[ -n "$oversized_tests" ]]; then
    report "Test files must stay under 2400 lines:" "$oversized_tests"
  fi
fi

node_line="$(tr -d '[:space:]' < .nvmrc 2>/dev/null || true)"
engines_line="$(
  node -e '
    const fs = require("node:fs");
    const input = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(fs.readFileSync("package.json"));
    const value = JSON.parse(input).engines.node;
    const match = typeof value === "string" && /^>=([\p{Nd}]+)\.[\p{Nd}]+\.[\p{Nd}]+(?:\n)?$(?![\s\S])/u.exec(value);
    if (match) console.log(match[1]);
  ' \
    2>/dev/null || true
)"
if [[ -z "$node_line" || "$node_line" != "$engines_line" ]]; then
  report "engines.node must be >=<line>.<minor>.<patch> on the .nvmrc line:" ".nvmrc='$node_line' engines='$engines_line'"
fi

ignore_probes=(
  .agents/session.md
  .claude/worktrees/x/file.md
  .codex/plan.md
  .planning/next-slice.md
  .tickets/LOCAL.md
  plans/local-plan.md
  tickets/LOCAL.md
  docs/plans/local-plan.md
  docs/tickets/LOCAL.md
  docs/ROADMAP.md
  planning_voice_20260911.md
  PLAN.md
  TODO.md
  HANDOFF.md
  reports/local-audit.md
  scratch/notes.md
  private-evidence/pack.json
  artifacts/ui/result.txt
  screenshots/local-smoke.png
  test-results/run.json
  Vendor/Sparkle.framework/Sparkle
  dist/Secreteo-1.0.0.dmg
  sparkle-private.key
  developer-id.p12
  AuthKey.p8
  local-ui.xcresult/Info.plist
  Secreteo.xcodeproj/project.pbxproj
)

for probe in "${ignore_probes[@]}"; do
  if ! git check-ignore --quiet --no-index "$probe"; then
    report "Expected local artifact is not ignored:" "$probe"
  fi
done

if [[ -d Tests/Tooling ]]; then
  bash Tests/Tooling/test_repository_hygiene.sh
  node --test Tests/Tooling/test_ui_shards.mjs Tests/Tooling/test_ui_results.mjs Tests/Tooling/test_ui_inventory.mjs \
    Tests/Tooling/test_build_cache.mjs Tests/Tooling/test_hygiene_coverage.mjs \
    Tests/Tooling/test_ci_decisions.mjs Tests/Tooling/test_ci_reuse.mjs \
    Tests/Tooling/test_log_privacy.mjs Tests/Tooling/test_stop_tail_in_tests.mjs \
    Tests/Tooling/test_swift_sources.mjs Tests/Tooling/test_release_timings.mjs
fi

exit "$failures"
