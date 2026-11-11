#!/usr/bin/env bash
# Usage: run-ui-tests.sh <smoke|full> [screenshot-dir] [shard, as index/count]
# Builds once, runs the plan, and exports `pr-*` attachments for PR evidence.
set -euo pipefail

plan="${1:?smoke or full}"
screenshots="${2:-build/pr-screenshots}"
shard="${3:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Requires the repository Node LTS runtime (.nvmrc / engines.node).
command -v node >/dev/null 2>&1 || { echo "Node is required for UI result processing." >&2; exit 127; }

scripts/fetch-sparkle.sh
xcodegen generate --quiet
results="build/ui-$plan${shard:+-${shard%%/*}}.xcresult"
rm -rf "$results" "$screenshots"
mkdir -p build "$screenshots"

selection=()
if [[ "$plan" == "smoke" ]]; then
  while IFS= read -r test || [[ -n "$test" ]]; do
    [[ -n "$test" ]] && selection+=("-only-testing:$test")
  done < Tests/Plans/Smoke.txt
  if [[ ${#selection[@]} -eq 0 ]]; then
    echo "Smoke plan has no tests." >&2
    exit 64
  fi
elif [[ "$plan" == "full" && -n "$shard" ]]; then
  # A plain assignment, so a failing helper stops the run instead of leaving the selection empty.
  classes="$(node scripts/ui_test_shards.mjs "${shard%%/*}" "${shard##*/}")"
  while IFS= read -r test_class; do
    [[ -n "$test_class" ]] && selection+=("-only-testing:SecreteoUITests/$test_class")
  done <<< "$classes"
  # An empty selection would run the whole plan.
  if [[ ${#selection[@]} -eq 0 ]]; then
    echo "Shard $shard has no test classes." >&2
    exit 64
  fi
elif [[ "$plan" != "full" ]]; then
  echo "Unknown plan: $plan" >&2
  exit 64
fi

common=(-project Secreteo.xcodeproj -scheme Secreteo -destination 'platform=macOS,arch=arm64'
  -derivedDataPath build/ui -skipPackagePluginValidation)
xcodebuild "${common[@]}" build-for-testing -quiet

status=0
xcodebuild "${common[@]}" test-without-building -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -resultBundlePath "$results" ${selection[@]+"${selection[@]}"} -quiet || status=$?

# `-quiet` names failing tests but not why, so print the reasons.
if [[ "$status" -ne 0 ]]; then
  xcrun xcresulttool get test-results summary --path "$results" --compact \
    | node scripts/ui_test_results.mjs summary || true
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
if xcrun xcresulttool export attachments --path "$results" --output-path "$scratch" >/dev/null 2>&1; then
  node scripts/ui_test_results.mjs attachments "$scratch" "$screenshots"
fi
exit "$status"
