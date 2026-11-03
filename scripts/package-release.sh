#!/usr/bin/env bash
# Usage: package-release.sh <version> <production|dryrun>
# Builds, signs inside out, notarizes and packages one DMG into dist/. The dry run takes
# this same path with ad-hoc signing and a throwaway key, so it proves what a tag runs.
set -euo pipefail

version="${1:?version}"
mode="${2:?production or dryrun}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

project_setting() {
  sed -nE "s/^[[:space:]]*$1:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/p" project.yml | head -1
}

settings=("MARKETING_VERSION=$version")
case "$mode" in
  production)
    identity="${MACOS_CODE_SIGN_IDENTITY:?MACOS_CODE_SIGN_IDENTITY is required}"
    : "${MACOS_NOTARY_KEY_ID:?MACOS_NOTARY_KEY_ID is required}"
    : "${MACOS_NOTARY_KEY_ISSUER_ID:?MACOS_NOTARY_KEY_ISSUER_ID is required}"
    : "${MACOS_NOTARY_KEY_P8:?MACOS_NOTARY_KEY_P8 must be the path of the key file}"
    [[ "$identity" != "-" ]] || { echo "error: production cannot sign ad-hoc" >&2; exit 1; }
    [[ "$(project_setting MARKETING_VERSION)" == "$version" ]] \
      || { echo "error: $version is not MARKETING_VERSION in project.yml" >&2; exit 1; }
    [[ -n "$(project_setting SPARKLE_PUBLIC_ED_KEY)" ]] \
      || { echo "error: SPARKLE_PUBLIC_ED_KEY is empty, so this build could never update" >&2; exit 1; }
    # Hardened runtime needs a team: an ad-hoc binary with it could not load Sparkle.
    sign_flags=(--options runtime --timestamp)
    ;;
  dryrun)
    identity="-"
    settings+=("SPARKLE_PUBLIC_ED_KEY=${DRYRUN_SPARKLE_PUBLIC_KEY:?DRYRUN_SPARKLE_PUBLIC_KEY is required}")
    sign_flags=(--timestamp=none)
    ;;
  *)
    echo "Unknown mode: $mode" >&2
    exit 64
    ;;
esac

output="dist"
derived="build/release"
stage="build/release-stage/$version"
app="$stage/Secreteo.app"
dmg="$output/Secreteo-$version.dmg"

sign() {
  codesign --force "${sign_flags[@]}" --sign "$identity" "$@"
}

notarize() {
  local submit="$1" staple="$2" plist status=0
  plist="$(mktemp)"
  xcrun notarytool submit "$submit" --key "$MACOS_NOTARY_KEY_P8" --key-id "$MACOS_NOTARY_KEY_ID" \
    --issuer "$MACOS_NOTARY_KEY_ISSUER_ID" --wait --timeout 45m --output-format plist > "$plist" || status=$?
  if [[ "$status" -ne 0 || "$(plutil -extract status raw -o - "$plist")" != "Accepted" ]]; then
    echo "error: notarization of $staple was not accepted" >&2
    cat "$plist" >&2
    xcrun notarytool log "$(plutil -extract id raw -o - "$plist")" --key "$MACOS_NOTARY_KEY_P8" \
      --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_KEY_ISSUER_ID" >&2
    exit 1
  fi
  rm -f "$plist"
  xcrun stapler staple "$staple"
}

scripts/fetch-sparkle.sh
xcodegen generate --quiet

mkdir -p "$output"
rm -rf "$stage" "$dmg" "$dmg.sha256"
mkdir -p "$stage"
xcodebuild -project Secreteo.xcodeproj -scheme Secreteo -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" \
  -skipPackagePluginValidation -quiet "${settings[@]}" build
ditto "$derived/Build/Products/Release/Secreteo.app" "$app"

# Inside out: signing a container seals what it holds.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
current="$sparkle/Versions/Current"
sign "$current/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$current/XPCServices/Downloader.xpc"
sign "$current/Autoupdate"
sign "$current/Updater.app"
sign "$sparkle"
sign --entitlements Apps/Secreteo/Secreteo.entitlements "$app"
codesign --verify --deep --strict "$app"

if [[ "$mode" == "production" ]]; then
  archive="$stage/Secreteo.zip"
  ditto -c -k --keepParent "$app" "$archive"
  notarize "$archive" "$app"
  rm -f "$archive"
fi

volume="$stage/volume"
mkdir -p "$volume"
ditto "$app" "$volume/Secreteo.app"
ln -s /Applications "$volume/Applications"
# hdiutil can lose a race with Spotlight on a busy disk.
for attempt in 1 2 3; do
  if hdiutil create -quiet -volname Secreteo -srcfolder "$volume" -ov -format UDZO "$dmg"; then
    break
  fi
  [[ "$attempt" -lt 3 ]] || { echo "error: could not create $dmg" >&2; exit 1; }
  sleep 10
done
rm -rf "$volume"
sign "$dmg"

if [[ "$mode" == "production" ]]; then
  notarize "$dmg" "$dmg"
fi

python3 scripts/verify_release.py "$app" "$dmg" "$version" "$mode"
(cd "$output" && shasum -a 256 "Secreteo-$version.dmg" > "Secreteo-$version.dmg.sha256")
echo "Packaged $dmg"
