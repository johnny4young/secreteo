#!/usr/bin/env bash
# Usage: run-signed-handoff.sh
# Proves that an ad-hoc build can be granted TCC by cdhash and deliver across processes.
# It edits the runner's TCC database, so verify.py refuses to run off a hosted VM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]] || { echo "error: hosted runners only" >&2; exit 1; }

bash spikes/tcc-adhoc/build.sh build one
for app in build/SpikeSender.app build/SpikeReceiver.app; do
  details="$(codesign -dvvv -r- "$app" 2>&1)"
  grep -q 'Signature=adhoc' <<<"$details" || { echo "error: $app is not ad-hoc" >&2; exit 1; }
  grep -q 'designated => cdhash H"' <<<"$details" || { echo "error: $app is not pinned by cdhash" >&2; exit 1; }
  if grep -q '^Authority=' <<<"$details"; then
    echo "error: $app has a signing authority" >&2
    exit 1
  fi
done

python3 spikes/tcc-adhoc/verify.py "$PWD/build" "$PWD/build/handoff-result.json"
