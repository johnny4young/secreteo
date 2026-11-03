#!/usr/bin/env bash
# Usage: render-cask.sh <version> <sha256>. Prints the cask for the tap, without the template header.
set -euo pipefail

version="${1:?version}"
sha256="${2:?sha256}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: $version is not x.y.z" >&2; exit 1; }
[[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "error: the checksum is not a sha256" >&2; exit 1; }

sed -e '/^#/d' -e "s/__VERSION__/$version/" -e "s/__SHA256__/$sha256/" "$ROOT/packaging/Casks/secreteo.rb"
