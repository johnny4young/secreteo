#!/usr/bin/env bash
# Usage: smoke-launch.sh <dmg>. Hosted runners only, because it replaces /Applications/Secreteo.app.
# Only a launch proves that hardened runtime lets the signed app load Sparkle.
set -euo pipefail

dmg="${1:?dmg}"
installed="/Applications/Secreteo.app"
[[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]] || { echo "error: hosted runners only" >&2; exit 1; }

mount="$(mktemp -d)/mount"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dmg"
rm -rf "$installed"
ditto "$mount/Secreteo.app" "$installed"
hdiutil detach -quiet -force "$mount"

open "$installed"
sleep 10
pgrep -x Secreteo >/dev/null || { echo "error: the app did not stay up" >&2; exit 1; }
pkill -x Secreteo
echo "The packaged app launched and stayed up."
