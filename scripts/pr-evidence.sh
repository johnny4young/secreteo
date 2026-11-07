#!/usr/bin/env bash
# Usage: pr-evidence.sh <PR> <run-id>
# Publishes a run's screenshots to the orphan pr-evidence branch and prints the markdown.
set -euo pipefail

pr="${1:?PR number}"
run="${2:?run id}"
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A sharded nightly uploads one artifact per shard, each in its own folder.
gh run download "$run" --repo "$repo" --pattern 'pr-screenshots*' --dir "$work/downloaded"
# A run can come from a fork, and `cp` would follow a link to a local file.
if [[ -n "$(find "$work/downloaded" ! -type f ! -type d)" ]]; then
  echo "The artifact has something other than files." >&2
  exit 1
fi
mkdir -p "$work/shots"
find "$work/downloaded" -type f -name '*.png' -exec cp {} "$work/shots/" \;
git clone --quiet --depth 1 --branch pr-evidence "https://github.com/$repo.git" "$work/evidence" 2>/dev/null || {
  git init --quiet --initial-branch pr-evidence "$work/evidence"
  git -C "$work/evidence" remote add origin "https://github.com/$repo.git"
}
mkdir -p "$work/evidence/pr-$pr"
cp "$work"/shots/*.png "$work/evidence/pr-$pr/"
git -C "$work/evidence" add -A
if ! git -C "$work/evidence" diff --cached --quiet; then
  git -C "$work/evidence" commit --quiet -m "docs: add evidence for PR $pr"
  git -C "$work/evidence" push --quiet origin pr-evidence
fi

for image in "$work"/shots/*.png; do
  name="$(basename "$image")"
  echo "![${name%.png}](https://raw.githubusercontent.com/$repo/pr-evidence/pr-$pr/$name)"
done
