#!/usr/bin/env bash
# Usage: sign-app.sh <app> <identity>, where "-" signs ad-hoc.
# Inside out, because signing a container seals what it holds. Hardened runtime needs a team:
# an ad-hoc binary with it could not load Sparkle, and neither could a real one over ad-hoc helpers.
set -euo pipefail

app="${1:?app}"
identity="${2:?identity}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$identity" == "-" ]]; then
  flags=(--timestamp=none)
else
  flags=(--options runtime --timestamp)
fi

sign() {
  codesign --force "${flags[@]}" --sign "$identity" "$@"
}

sparkle="$app/Contents/Frameworks/Sparkle.framework"
current="$sparkle/Versions/Current"
sign "$current/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$current/XPCServices/Downloader.xpc"
sign "$current/Autoupdate"
sign "$current/Updater.app"
sign "$sparkle"
sign "$app/Contents/Helpers/secreteo-mcp"
sign --entitlements "$ROOT/Apps/Secreteo/Secreteo.entitlements" "$app"
codesign --verify --deep --strict "$app"
