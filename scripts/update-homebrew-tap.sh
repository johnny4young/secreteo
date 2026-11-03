#!/usr/bin/env bash
# Usage: update-homebrew-tap.sh <version> <sha256>, with TAP_DEPLOY_KEY in the environment.
# The tap is shared with other apps, so a rejected push starts again from a fresh clone.
set -euo pipefail

version="${1:?version}"
sha256="${2:?sha256}"
: "${TAP_DEPLOY_KEY:?TAP_DEPLOY_KEY is required}"
tap_url="${TAP_URL:-git@github.com:johnny4young/homebrew-tap.git}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
printf '%s\n' "$TAP_DEPLOY_KEY" > "$scratch/key"
chmod 600 "$scratch/key"
# GitHub's published host key, so a first connection cannot be intercepted.
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" > "$scratch/known_hosts"
export GIT_SSH_COMMAND="ssh -i $scratch/key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$scratch/known_hosts"

cask="Casks/secreteo.rb"
for attempt in 1 2 3; do
  rm -rf "$scratch/tap"
  git clone -q --depth 1 "$tap_url" "$scratch/tap"

  # A delayed run must not take users back to an older version.
  if [[ -f "$scratch/tap/$cask" ]]; then
    current="$(sed -nE 's/^  version "(.*)"$/\1/p' "$scratch/tap/$cask")"
    if [[ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -1)" != "$version" ]]; then
      echo "The tap already serves $current, newer than $version."
      exit 0
    fi
  fi

  "$ROOT/scripts/render-cask.sh" "$version" "$sha256" > "$scratch/tap/$cask"
  ruby -c "$scratch/tap/$cask"
  git -C "$scratch/tap" add "$cask"
  if git -C "$scratch/tap" diff --cached --quiet; then
    echo "The tap already serves secreteo $version."
    exit 0
  fi
  git -C "$scratch/tap" -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -q -m "chore(secreteo): publish cask v$version"
  if git -C "$scratch/tap" push -q origin HEAD:main; then
    echo "The tap now serves secreteo $version."
    exit 0
  fi
  echo "Push $attempt was rejected."
  sleep 2
done
echo "error: the tap kept rejecting the push" >&2
exit 1
