#!/usr/bin/env bash
# Usage: setup-release-signing.sh. Hosted runners only, from the release Environment's secrets.
# Imports the certificate into a throwaway keychain and writes the notary key to a file.
set -euo pipefail

[[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]] || { echo "error: hosted runners only" >&2; exit 1; }
: "${MACOS_CERTIFICATE_P12:?MACOS_CERTIFICATE_P12 is required}"
: "${MACOS_CERTIFICATE_PASSWORD:?MACOS_CERTIFICATE_PASSWORD is required}"
: "${MACOS_NOTARY_KEY_P8:?MACOS_NOTARY_KEY_P8 is required}"

umask 077
"$(dirname "${BASH_SOURCE[0]}")/enable-gatekeeper.sh"

keychain="$RUNNER_TEMP/signing.keychain-db"
keychain_password="$(openssl rand -base64 24)"
certificate="$RUNNER_TEMP/certificate.p12"
trap 'rm -f "$certificate"' EXIT

printf '%s' "$MACOS_CERTIFICATE_P12" | base64 --decode > "$certificate"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -k "$keychain" -f pkcs12 -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
identities="$(security find-identity -v -p codesigning "$keychain")"
echo "$identities"
grep -q 'Developer ID Application' <<<"$identities" || { echo "error: no valid Developer ID identity" >&2; exit 1; }

notary_key="$RUNNER_TEMP/notary-key.p8"
printf '%s' "$MACOS_NOTARY_KEY_P8" | base64 --decode > "$notary_key"
echo "MACOS_NOTARY_KEY_FILE=$notary_key" >> "$GITHUB_ENV"
