#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Each case has a fresh repository and runs in a separate process.
if [[ "${1:-}" != "--case" ]]; then
  cases=(
    clean_repository_passes
    passes_before_the_first_commit
    rejects_missing_required_file
    rejects_claude_md_that_is_not_a_symlink
    rejects_tracked_planning_file
    rejects_conflict_markers
    rejects_ticket_reference
    rejects_source_app_identifiers
    allows_source_app_identifiers_in_provenance_and_notices
    allows_source_app_identifiers_only_in_the_exact_peer_list
    the_word_portavoz_alone_is_allowed
    rejects_private_local_paths
    allows_the_hosted_runner_home
    rejects_gpl_markers
    rejects_ai_attribution_in_commit_messages
    accepts_human_co_author
    rejects_mutable_action
    accepts_pinned_action
    rejects_left_accent_bars
    rejects_oversized_test_file
    rejects_node_line_mismatch
    rejects_ignore_rule_regression
    validates_node_engine_input
  )
  failed=0
  for test_case in "${cases[@]}"; do
    if bash "${BASH_SOURCE[0]}" --case "$test_case"; then
      printf 'PASS %s\n' "$test_case"
    else
      printf 'FAIL %s\n' "$test_case" >&2
      failed=1
    fi
  done
  if [[ "$failed" -ne 0 ]]; then
    exit 1
  fi
  printf 'All %s repository hygiene tests passed.\n' "${#cases[@]}"
  exit 0
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/repository-hygiene.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT
FIXTURE="$TEMP_ROOT/repo"
mkdir -p "$FIXTURE/scripts"
node_path="$(command -v node)" || { printf 'Node is required on PATH.\n' >&2; exit 1; }
NODE_DIR="$(dirname "$node_path")"
mkdir -p "$TEMP_ROOT/bin"
cat > "$TEMP_ROOT/bin/python3" <<'STUB'
#!/bin/bash
printf 'Unexpected Python invocation\n' > "$HYGIENE_PYTHON_SENTINEL"
exit 99
STUB
chmod +x "$TEMP_ROOT/bin/python3"
SAFE_PATH="$TEMP_ROOT/bin:$NODE_DIR:/usr/bin:/bin:/usr/sbin:/sbin"

# Do not inherit the owner's Git configuration, hooks, or environment.
fixture_git() {
  env -i PATH="$SAFE_PATH" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    git -C "$FIXTURE" -c core.hooksPath=/dev/null "$@" >/dev/null
}
write_file() {
  mkdir -p "$(dirname "$FIXTURE/$1")"
  printf '%s' "$2" > "$FIXTURE/$1"
}
commit_fixture() {
  fixture_git add -A -f
  fixture_git commit -q -m "${1:-chore: fixture}"
}
run_gate() {
  (cd "$FIXTURE" && env -i PATH="$SAFE_PATH" HYGIENE_PYTHON_SENTINEL="$TEMP_ROOT/python-invoked" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
    bash scripts/check-repository-hygiene.sh) > "$TEMP_ROOT/stdout" 2> "$TEMP_ROOT/stderr"
}
assert_no_python() {
  if [[ -e "$TEMP_ROOT/python-invoked" ]]; then
    printf 'The repository gate must not invoke Python.\n' >&2
    return 1
  fi
}
assert_pass() {
  if ! run_gate; then
    printf 'Expected the hygiene gate to pass.\n' >&2
    cat "$TEMP_ROOT/stderr" >&2
    return 1
  fi
  assert_no_python
}
assert_rejected() {
  if run_gate; then
    printf 'Expected rejection containing: %s\n' "$1" >&2
    return 1
  fi
  assert_no_python || return 1
  if ! grep -Fq -- "$1" "$TEMP_ROOT/stderr"; then
    printf 'Missing expected rejection: %s\n' "$1" >&2
    cat "$TEMP_ROOT/stderr" >&2
    return 1
  fi
}

fixture_git init -q -b main --template=
fixture_git config user.email test@example.com
fixture_git config user.name Test
cp "$REPO/scripts/check-repository-hygiene.sh" "$FIXTURE/scripts/"
cp "$REPO/.gitignore" "$FIXTURE/"
for required in LICENSE README.md AGENTS.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md \
  CHANGELOG.md THIRD-PARTY-NOTICES.md docs/PROVENANCE.md; do
  write_file "$required" $'x\n'
done
ln -s AGENTS.md "$FIXTURE/CLAUDE.md"
write_file .nvmrc $'26\n'
write_file package.json '{"engines":{"node":">=26.13.0"}}'

# Construct literals that the hygiene gate itself forbids.
bundle_prefix='app.'"portavoz"
toolkit='Cloud'"Kit"

case "${2:-}" in
  clean_repository_passes)
    commit_fixture
    assert_pass
    ;;
  passes_before_the_first_commit)
    assert_pass
    ;;
  rejects_missing_required_file)
    rm "$FIXTURE/LICENSE"
    assert_rejected 'Required file is missing'
    ;;
  rejects_claude_md_that_is_not_a_symlink)
    rm "$FIXTURE/CLAUDE.md"
    write_file CLAUDE.md $'copy\n'
    assert_rejected 'must be a symlink'
    ;;
  rejects_tracked_planning_file)
    write_file planning_secret.md $'x\n'
    commit_fixture
    assert_rejected 'must not be tracked'
    ;;
  rejects_conflict_markers)
    write_file a.txt '<''<<<<<< HEAD'$'\n'
    assert_rejected 'merge-conflict markers'
    ;;
  rejects_ticket_reference)
    write_file a.txt $'see '"APUN"$'-12\n'
    assert_rejected 'Private ticket references'
    ;;
  rejects_source_app_identifiers)
    for token in "$bundle_prefix.mac" 'PORTAVOZ'_'UI_TEST_DEFAULTS' 'PV'"Design" \
      '"PV'"OZ\"" '0x5056'_'4F5A' 'Apun'"tador" "$toolkit" \
      'Application Support/'"Portavoz"; do
      write_file Sources/a.swift "let x = $token"$'\n'
      assert_rejected 'Source-app identifiers'
    done
    ;;
  allows_source_app_identifiers_in_provenance_and_notices)
    write_file docs/PROVENANCE.md "$bundle_prefix $toolkit"$'\n'
    write_file THIRD-PARTY-NOTICES.md "$bundle_prefix"$'\n'
    commit_fixture
    assert_pass
    ;;
  allows_source_app_identifiers_only_in_the_exact_peer_list)
    identifier="$bundle_prefix.mac"
    write_file Sources/DictationSession/KnownDictationPeers.swift "let peer = \"$identifier\""$'\n'
    assert_pass
    write_file Sources/DictationSession/KnownDictationPeersCopy.swift "let peer = \"$identifier\""$'\n'
    assert_rejected 'Source-app identifiers'
    ;;
  the_word_portavoz_alone_is_allowed)
    write_file docs/DECISIONS.md $'Portavoz D516\n'
    assert_pass
    ;;
  rejects_private_local_paths)
    write_file a.txt '/Users/'$'someone/file\n'
    assert_rejected 'Private local paths'
    ;;
  allows_the_hosted_runner_home)
    write_file a.py 'path.startswith("/Users/'$'runner/")\n'
    assert_pass
    ;;
  rejects_gpl_markers)
    write_file a.swift '// SPDX-License-Identifier: '"GPL-3.0"$'\n'
    assert_rejected 'GPL license markers'
    ;;
  rejects_ai_attribution_in_commit_messages)
    for message in $'feat: x\n\nCo-Authored-By: '"Claude <noreply@anthropic.com>" \
      $'feat: x\n\nGenerated with '"Claude Code"; do
      commit_fixture "$message"
      assert_rejected 'AI attribution'
      fixture_git update-ref -d HEAD
    done
    ;;
  accepts_human_co_author)
    commit_fixture $'feat: x\n\nCo-Authored-By: Ada <ada@example.com>'
    assert_pass
    ;;
  rejects_mutable_action)
    write_file .github/workflows/ci.yml $'steps:\n  - uses: actions/checkout@v7\n'
    assert_rejected 'full-length commit SHAs'
    ;;
  accepts_pinned_action)
    write_file .github/workflows/ci.yml $'steps:\n  - uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v7\n'
    assert_pass
    ;;
  rejects_left_accent_bars)
    write_file site/a.css '.card { '"border"$'-left: 3px solid red; }\n'
    assert_rejected 'Left accent bars'
    rm "$FIXTURE/site/a.css"
    write_file site/b.html '<div class="'"border"$'-l-4"></div>\n'
    assert_rejected 'Left accent bars'
    rm "$FIXTURE/site/b.html"
    ;;
  rejects_oversized_test_file)
    mkdir -p "$FIXTURE/Tests"
    awk 'BEGIN { for (i = 0; i < 2401; i++) print "// x" }' > "$FIXTURE/Tests/Big.swift"
    assert_rejected 'under 2400 lines'
    ;;
  rejects_node_line_mismatch)
    write_file .nvmrc $'24\n'
    assert_rejected 'engines.node'
    ;;
  rejects_ignore_rule_regression)
    sed '/^\/planning_\*\.md$/d' "$FIXTURE/.gitignore" > "$TEMP_ROOT/gitignore"
    cp "$TEMP_ROOT/gitignore" "$FIXTURE/.gitignore"
    assert_rejected 'not ignored'
    ;;
  validates_node_engine_input)
    for input in '{' '{}' '{"engines":{}}' '{"engines":{"node":42}}' \
      '{"engines":{"node":">=26.13"}}' '{"engines":{"node":">=26.13.0 extra"}}' \
      '{"engines":{"node":">=26.13.0\r"}}' '{"engines":{"node":">=26.13.0\n\n"}}'; do
      write_file package.json "$input"
      assert_rejected "engines.node"
      grep -Fq "engines=''" "$TEMP_ROOT/stderr"
    done
    write_file package.json '{"engines":{"node":">=26.13.0\n"}}'
    assert_pass
    printf '{"engines":{"node":">=26.13.0"},"unused":"\377"}' > "$FIXTURE/package.json"
    assert_rejected 'engines.node'
    printf '\357\273\277{"engines":{"node":">=26.13.0"}}' > "$FIXTURE/package.json"
    assert_rejected 'engines.node'
    ;;
  *)
    printf 'Unknown test case: %s\n' "${2:-}" >&2
    exit 1
    ;;
esac
