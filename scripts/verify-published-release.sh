#!/usr/bin/env bash
# Usage: verify-published-release.sh <tag>. Proves what users get: the live feed, the tap's cask, a Homebrew
# install Gatekeeper accepts, and a Sparkle update from the previous release. Hosted runners only.
set -euo pipefail

tag="${1:-}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: verify-published-release.sh vX.Y.Z" >&2; exit 64; }
if [[ "${RUNNER_ENVIRONMENT:-}" != "github-hosted" ]]; then
  echo "error: this replaces /Applications/Secreteo.app and runs on hosted runners only" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
version="${tag#v}"
repo="${GITHUB_REPOSITORY:-johnny4young/secreteo}"
bundle_id="com.johnny4young.secreteo"
installed="/Applications/Secreteo.app"
work="$(mktemp -d)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ANALYTICS=1

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

version_of() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null
}

installed_version_is() {
  [[ "$(version_of "$installed")" == "$1" ]]
}

accepted() {
  codesign --verify --deep --strict "$1"
  xcrun stapler validate -q "$1"
  spctl -a -t exec "$1"
}

finish() {
  local status=$?
  set +e
  if [[ "$status" -ne 0 ]]; then
    log show --last 15m --style compact \
      --predicate 'process == "Secreteo" OR process == "Autoupdate" OR process == "Updater"' | tail -80
  fi
  pkill -x Secreteo
  exit "$status"
}
trap finish EXIT

scripts/enable-gatekeeper.sh

gh release download "$tag" --repo "$repo" --pattern "Secreteo-$version.dmg*" --dir "$work"
(cd "$work" && shasum -a 256 -c "Secreteo-$version.dmg.sha256")
sha256="$(cut -d' ' -f1 "$work/Secreteo-$version.dmg.sha256")"

curl -fsSL --retry 5 "https://github.com/$repo/releases/latest/download/appcast.xml" -o "$work/appcast.xml"
python3 scripts/verify_appcast.py "$work/appcast.xml" "$version" \
  "https://github.com/$repo/releases/download/$tag/" "$work/Secreteo-$version.dmg"
echo "The live feed offers $version with a valid signature."

gh api repos/johnny4young/homebrew-tap/contents/Casks/secreteo.rb --jq .content | base64 --decode > "$work/secreteo.rb"
grep -qx "  version \"$version\"" "$work/secreteo.rb" || { echo "error: the tap does not serve $version" >&2; exit 1; }
grep -qx "  sha256 \"$sha256\"" "$work/secreteo.rb" || { echo "error: the tap's sha256 is not the DMG's" >&2; exit 1; }

mkdir "$work/apps"
brew install --cask --appdir="$work/apps" johnny4young/tap/secreteo
[[ "$(version_of "$work/apps/Secreteo.app")" == "$version" ]] || { echo "error: Homebrew installed another version" >&2; exit 1; }
accepted "$work/apps/Secreteo.app"
brew uninstall --cask --force secreteo
echo "Homebrew installs $version and Gatekeeper accepts it."

previous="$(gh release list --repo "$repo" --exclude-drafts --exclude-pre-releases --limit 100 --json tagName --jq '.[].tagName' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | awk -v tag="$tag" '$0 == tag { print last; exit } { last = $0 }')"
if [[ -z "$previous" ]]; then
  echo "No earlier release to update from."
  exit 0
fi

gh release download "$previous" --repo "$repo" --pattern "Secreteo-${previous#v}.dmg" --dir "$work"
hdiutil attach -quiet -nobrowse -mountpoint "$work/mount" "$work/Secreteo-${previous#v}.dmg"
rm -rf "$installed"
ditto "$work/mount/Secreteo.app" "$installed"
hdiutil detach -quiet "$work/mount"

# The feed stays the one compiled into the previous release.
defaults delete "$bundle_id" SUFeedURL 2>/dev/null || true
defaults write "$bundle_id" SUEnableAutomaticChecks -bool true
defaults write "$bundle_id" SUAutomaticallyUpdate -bool true
defaults write "$bundle_id" SUHasLaunchedBefore -bool true

open "$installed"
wait_for "${previous#v} running" 30 pgrep -x Secreteo
wait_for "the installer" 300 pgrep -x Autoupdate
# It appears before it finishes preparing, and quitting then would abort the install.
sleep 10
pkill -TERM -x Secreteo
wait_for "version $version installed" 300 installed_version_is "$version"
accepted "$installed"

pkill -x Secreteo || [[ $? -eq 1 ]]
open "$installed"
wait_for "the updated app running" 30 pgrep -x Secreteo
sleep 5
pgrep -x Secreteo >/dev/null || { echo "error: the updated app did not stay up" >&2; exit 1; }
echo "Sparkle updated ${previous#v} to $version from the live feed."
