#!/usr/bin/env bash
# Usage: package-release.sh <version> <production|dryrun>
# Builds, signs inside out, notarizes and packages one DMG into dist/. The dry run takes
# this same path with ad-hoc signing and a throwaway key, so it proves what a tag runs.
set -euo pipefail

version="${1:?version}"
mode="${2:?production or dryrun}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# It names paths that get deleted, and CFBundleVersion takes only three integers.
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: $version is not x.y.z" >&2; exit 64; }
package_started=$SECONDS

begin_phase() {
  current_phase="$1"
  phase_started=$SECONDS
}

report_timing() {
  printf 'PackageTiming version=%s phase=%s real=%d status=%d\n' "$version" "$1" "$((SECONDS - $2))" "$3" >&2
}

finish_phase() {
  [[ -n "${current_phase:-}" ]] || return 0
  report_timing "$current_phase" "$phase_started" "$1"
  current_phase=""
}

# Report a failed stage without changing errexit or running the next command.
trap 'status=$?; if [[ "$status" -ne 0 ]]; then finish_phase "$status"; fi; exit "$status"' EXIT

project_setting() {
  sed -nE "s/^[[:space:]]*$1:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/p" project.yml | head -1
}

settings=("MARKETING_VERSION=$version")
build_output=(-quiet)
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
    ;;
  dryrun)
    identity="-"
    settings+=("SPARKLE_PUBLIC_ED_KEY=${DRYRUN_SPARKLE_PUBLIC_KEY:?DRYRUN_SPARKLE_PUBLIC_KEY is required}")
    # Quiet output also suppresses Xcode's timing summary.
    build_output=(-showBuildTimingSummary)
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

notarize() {
  local submit="$1" staple="$2" plist status=0 id
  plist="$(mktemp)"
  xcrun notarytool submit "$submit" --key "$MACOS_NOTARY_KEY_P8" --key-id "$MACOS_NOTARY_KEY_ID" \
    --issuer "$MACOS_NOTARY_KEY_ISSUER_ID" --wait --timeout 45m --output-format plist > "$plist" || status=$?
  if [[ "$status" -ne 0 || "$(plutil -extract status raw -o - "$plist" 2>/dev/null)" != "Accepted" ]]; then
    echo "error: notarization of $staple was not accepted" >&2
    cat "$plist" >&2
    # A request Apple refuses outright gets no submission, so there is no log to fetch.
    if id="$(plutil -extract id raw -o - "$plist" 2>/dev/null)" && [[ -n "$id" ]]; then
      xcrun notarytool log "$id" --key "$MACOS_NOTARY_KEY_P8" \
        --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_KEY_ISSUER_ID" >&2
    fi
    exit 1
  fi
  rm -f "$plist"
  xcrun stapler staple "$staple"
}

begin_phase prepare
scripts/fetch-sparkle.sh
xcodegen generate --quiet
finish_phase 0

mkdir -p "$output"
rm -rf "$stage" "$dmg" "$dmg.sha256"
mkdir -p "$stage"
begin_phase build
# A restored build would otherwise keep resources this commit deleted.
rm -rf "$derived/Build/Products/Release/Secreteo.app"
# Project-level ARCHS does not constrain the package targets.
xcodebuild -project Secreteo.xcodeproj -scheme Secreteo -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" \
  -skipPackagePluginValidation "${build_output[@]}" ARCHS=arm64 "${settings[@]}" build
finish_phase 0
begin_phase copy
ditto "$derived/Build/Products/Release/Secreteo.app" "$app"
finish_phase 0

begin_phase sign
scripts/sign-app.sh "$app" "$identity"
finish_phase 0

if [[ "$mode" == "production" ]]; then
  archive="$stage/Secreteo.zip"
  ditto -c -k --keepParent "$app" "$archive"
  notarize "$archive" "$app"
  rm -f "$archive"
fi

begin_phase dmg
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
finish_phase 0

if [[ "$mode" == "production" ]]; then
  codesign --force --timestamp --sign "$identity" "$dmg"
  notarize "$dmg" "$dmg"
fi

begin_phase verify
python3 scripts/verify_release.py "$dmg" "$version" "$mode"
finish_phase 0
(cd "$output" && shasum -a 256 "Secreteo-$version.dmg" > "Secreteo-$version.dmg.sha256")
echo "Packaged $dmg"
report_timing total "$package_started" 0
