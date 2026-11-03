#!/usr/bin/env bash
# Usage: pr-evidence.sh <PR> <run-id>
# Publishes a run's screenshots to the orphan pr-evidence branch and prints the markdown.
set -euo pipefail

pr="${1:?PR number}"
run="${2:?run id}"
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

gh run download "$run" --repo "$repo" --name pr-screenshots --dir "$work/shots"
git clone --quiet --depth 1 --branch pr-evidence "https://github.com/$repo.git" "$work/evidence" 2>/dev/null || {
  git init --quiet --initial-branch pr-evidence "$work/evidence"
  git -C "$work/evidence" remote add origin "https://github.com/$repo.git"
}
mkdir -p "$work/evidence/pr-$pr"
cp "$work"/shots/*.png "$work/evidence/pr-$pr/"
git -C "$work/evidence" add -A
git -C "$work/evidence" commit --quiet -m "docs: add evidence for PR $pr"
git -C "$work/evidence" push --quiet origin pr-evidence

for image in "$work"/shots/*.png; do
  name="$(basename "$image")"
  echo "![${name%.png}](https://raw.githubusercontent.com/$repo/pr-evidence/pr-$pr/$name)"
done
