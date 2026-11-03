#!/usr/bin/env bash
# Usage: release-dryrun.sh [package|update], both by default.
# package is safe on any Mac. update lets the real updater replace an installed copy, which
# writes to /Applications and the real bundle's defaults, so it runs on hosted runners only.
set -euo pipefail

stage="${1:-all}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

old_version="9.0.0"
new_version="9.0.1"
port=8765
prefix="http://127.0.0.1:$port/"
work="build/dryrun"
bundle_id="com.johnny4young.secreteo"
installed="/Applications/Secreteo.app"

package() {
  rm -rf "$work"
  mkdir -p "$work/feed"
  local keys private public
  keys="$(swift scripts/throwaway-sparkle-key.swift)"
  private="${keys% *}"
  public="${keys#* }"

  for version in "$old_version" "$new_version"; do
    DRYRUN_SPARKLE_PUBLIC_KEY="$public" scripts/package-release.sh "$version" dryrun
    printf -- '- Dry run of %s.\n' "$version" > "$work/notes-$version.md"
    SPARKLE_EDDSA_PRIVATE_KEY="$private" scripts/generate-appcast.sh "$version" "dist/Secreteo-$version.dmg" \
      "$work/notes-$version.md" "$prefix" "$work/feed/appcast.xml"
    cp "dist/Secreteo-$version.dmg" "$work/feed/"
  done
}

wait_for() {
  local what="$1" seconds="$2"
  shift 2
  for _ in $(seq "$seconds"); do
    if "$@"; then
      echo "Saw: $what"
      return 0
    fi
    sleep 1
  done
  echo "error: timed out waiting for $what" >&2
  return 1
}

served() {
  grep -q "\"GET /$1 HTTP" "$work/server.log"
}

installed_version_is() {
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed/Contents/Info.plist" 2>/dev/null)" == "$1" ]]
}

diagnose() {
  echo "--- server log"
  cat "$work/server.log"
  echo "--- updater log"
  log show --last 10m --style compact \
    --predicate 'process == "Secreteo" OR process == "Autoupdate" OR process == "Updater"' | tail -60
}

update() {
  if [[ "${RUNNER_ENVIRONMENT:-}" != "github-hosted" ]]; then
    echo "error: the update stage changes /Applications and runs on hosted runners only" >&2
    exit 1
  fi

  (cd "$work/feed" && exec python3 -u -m http.server "$port" --bind 127.0.0.1) > "$work/server.log" 2>&1 &
  local server=$!
  trap 'status=$?; [[ $status -eq 0 ]] || diagnose; kill '"$server"' 2>/dev/null; pkill -x Secreteo; exit $status' EXIT

  hdiutil attach -quiet -nobrowse -mountpoint "$work/mount" "dist/Secreteo-$old_version.dmg"
  rm -rf "$installed"
  ditto "$work/mount/Secreteo.app" "$installed"
  hdiutil detach -quiet "$work/mount"

  defaults write "$bundle_id" SUFeedURL "http://127.0.0.1:$port/appcast.xml"
  defaults write "$bundle_id" SUEnableAutomaticChecks -bool true
  defaults write "$bundle_id" SUAutomaticallyUpdate -bool true
  defaults write "$bundle_id" SUHasLaunchedBefore -bool true

  open "$installed"
  wait_for "the app running" 30 pgrep -x Secreteo
  wait_for "the feed request" 120 served appcast.xml
  wait_for "the update download" 120 served "Secreteo-$new_version.dmg"
  wait_for "the installer waiting for the app to quit" 120 pgrep -x Autoupdate

  pkill -TERM -x Secreteo
  wait_for "version $new_version installed" 180 installed_version_is "$new_version"
  codesign --verify --deep --strict "$installed"

  pkill -x Secreteo || [[ $? -eq 1 ]]
  open "$installed"
  wait_for "the updated app running" 30 pgrep -x Secreteo
  sleep 5
  pgrep -x Secreteo >/dev/null || { echo "error: the updated app did not stay up" >&2; exit 1; }
  echo "Sparkle updated $old_version to $new_version from a signed feed."
}

case "$stage" in
  package) package ;;
  update) update ;;
  all) package; update ;;
  *) echo "Unknown stage: $stage" >&2; exit 64 ;;
esac
