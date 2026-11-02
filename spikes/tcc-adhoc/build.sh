#!/usr/bin/env bash
# Usage: build.sh <output-dir> <marker>. Builds and ad-hoc signs the sender and the receiver.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output="$1"
marker="$2"

bundle() {
  local name="$1" identifier="$2" source="$3"
  local app="$output/$name.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  /usr/libexec/PlistBuddy \
    -c "Add :CFBundleIdentifier string $identifier" \
    -c "Add :CFBundleExecutable string $name" \
    -c "Add :CFBundlePackageType string APPL" \
    "$app/Contents/Info.plist" >/dev/null
  swiftc -swift-version 6 "$source" -o "$app/Contents/MacOS/$name"
  codesign --force --sign - --identifier "$identifier" "$app"
  codesign --verify --strict "$app"
}

mkdir -p "$output"
marked="$output/sender-source/main.swift"
mkdir -p "$(dirname "$marked")"
sed "s/BUILD_MARKER/$marker/" "$here/sender.swift" > "$marked"
bundle SpikeSender com.johnny4young.secreteo.spike.sender "$marked"
bundle SpikeReceiver com.johnny4young.secreteo.spike.receiver "$here/receiver.swift"
