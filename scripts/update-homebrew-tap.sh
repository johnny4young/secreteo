#!/usr/bin/env bash
# Usage: update-homebrew-tap.sh <version> <sha256>, with TAP_DEPLOY_KEY in the environment.
set -euo pipefail

version="${1:?version}"
sha256="${2:?sha256}"
: "${TAP_DEPLOY_KEY:?TAP_DEPLOY_KEY is required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
printf '%s\n' "$TAP_DEPLOY_KEY" > "$scratch/key"
chmod 600 "$scratch/key"
# GitHub's published host key, so a first connection cannot be intercepted.
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" > "$scratch/known_hosts"
export GIT_SSH_COMMAND="ssh -i $scratch/key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$scratch/known_hosts"

git clone --depth 1 git@github.com:johnny4young/homebrew-tap.git "$scratch/tap"
"$ROOT/scripts/render-cask.sh" "$version" "$sha256" > "$scratch/tap/Casks/secreteo.rb"
ruby -c "$scratch/tap/Casks/secreteo.rb"

cd "$scratch/tap"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add Casks/secreteo.rb
if git diff --cached --quiet; then
  echo "The tap already serves secreteo $version."
  exit 0
fi
git commit -q -m "chore(secreteo): publish cask v$version"
git push -q origin HEAD:main
echo "The tap now serves secreteo $version."
