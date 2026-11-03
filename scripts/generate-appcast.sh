#!/usr/bin/env bash
# Usage: generate-appcast.sh <version> <dmg> <notes.md> <download-url-prefix> <feed.xml>
# Signs the exact DMG bytes and adds its item to the feed. An existing feed keeps its items.
# The key comes on stdin from the environment, so it never touches disk or the log.
set -euo pipefail

version="${1:?version}"
dmg="${2:?dmg}"
notes="${3:?release notes}"
prefix="${4:?download url prefix}"
feed="${5:?feed path}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${SPARKLE_EDDSA_PRIVATE_KEY:?SPARKLE_EDDSA_PRIVATE_KEY is required}"
"$ROOT/scripts/fetch-sparkle.sh" >/dev/null

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
archive="$(basename "$dmg")"
cp "$dmg" "$work/$archive"
cp "$notes" "$work/${archive%.dmg}.md"
[[ ! -f "$feed" ]] || cp "$feed" "$work/appcast.xml"

printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" | "$ROOT/Vendor/bin/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "$prefix" \
  --embed-release-notes \
  --link "https://github.com/johnny4young/secreteo" \
  -o "$work/appcast.xml" \
  "$work"

python3 "$ROOT/scripts/verify_appcast.py" "$work/appcast.xml" "$version" "$prefix" "$dmg"
cp "$work/appcast.xml" "$feed"
echo "Appcast for $version written to $feed"
