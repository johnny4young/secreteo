#!/usr/bin/env bash
# Usage: run-ui-tests.sh <smoke|full> [screenshot-dir]
# Builds once, runs the plan, and exports `pr-*` attachments for PR evidence.
set -euo pipefail

plan="${1:?smoke or full}"
screenshots="${2:-build/pr-screenshots}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

xcodegen generate --quiet
results="build/ui-$plan.xcresult"
rm -rf "$results" "$screenshots"
mkdir -p build "$screenshots"

selection=()
if [[ "$plan" == "smoke" ]]; then
  while IFS= read -r test; do
    [[ -n "$test" ]] && selection+=("-only-testing:$test")
  done < Tests/Plans/Smoke.txt
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
    | python3 -c 'import json,sys; [print(f"{t[\"testName\"]}: {t[\"failureText\"]}") for t in json.load(sys.stdin).get("testFailures", [])]' || true
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
if xcrun xcresulttool export attachments --path "$results" --output-path "$scratch" >/dev/null 2>&1; then
  python3 - "$scratch" "$screenshots" <<'PY'
import json
import shutil
import sys
from pathlib import Path

source, target = Path(sys.argv[1]), Path(sys.argv[2])
for test in json.loads((source / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        if name.startswith("pr-"):
            shutil.copy(source / attachment["exportedFileName"], target / f"{name.split('_')[0]}.png")
PY
fi
exit "$status"
