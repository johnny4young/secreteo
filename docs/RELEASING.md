# Releasing

A `v*` tag runs `release.yml`. The owner approves the `release` Environment and publishes.

## Flow

1. Tag equals `MARKETING_VERSION`, and `CHANGELOG.md` has an entry.
2. Hygiene and tests.
3. Release build with the pinned toolchain: `macos-26`, Xcode 26.6.
4. Sign nested helpers and the app with no ignored failures.
5. Notarize and staple the app.
6. Build the DMG, then notarize and staple it.
7. Verify distribution and the app payload.
8. `generate_appcast --ed-key-file - --download-url-prefix .../releases/download/v<version>/ --embed-release-notes`.
9. Verify the appcast.
10. Publish, then update the Homebrew tap.

The feed stays at `releases/latest/download/appcast.xml`. Enclosures are versioned.

## Dry run

`scripts/release-dryrun.sh` packages versions 9.0.0 and 9.0.1 through `scripts/package-release.sh` with ad-hoc signing and a throwaway key, and builds a feed that holds both. On a hosted runner it then installs 9.0.0, serves the feed locally, and waits for the real updater to replace the app with 9.0.1. CI runs it when packaging changes, and `nightly.yml` runs it every night. `make release-dryrun` runs the packaging half on any Mac.

It cannot prove what needs the secrets: hardened runtime, notarization, stapling and Gatekeeper. Those stay in the real release.

## Secrets

Scoped to the `release` Environment:

| Secret | Use |
|---|---|
| `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD` | Developer ID certificate |
| `MACOS_CODE_SIGN_IDENTITY`, `MACOS_SIGN_TEAM_ID` | Signing identity |
| `MACOS_NOTARY_KEY_ID`, `MACOS_NOTARY_KEY_ISSUER_ID`, `MACOS_NOTARY_KEY_P8` | App Store Connect API key |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Appcast signature |
| `TAP_DEPLOY_KEY` | Homebrew tap |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | Site, in `pages.yml` |

No provisioning profile is needed: the app uses neither iCloud nor Push.

## Sparkle

- The EdDSA key belongs to this app. Back it up with `generate_keys -x` before the first public build. Losing it leaves users without automatic updates.
- Framework and tools come from one checksum-pinned fetch at one version.
- The public key goes in `SPARKLE_PUBLIC_ED_KEY` in `project.yml`. With it empty, the updater stays off.

## Homebrew

Same tap as the other apps, with its own deploy key. The cask has `depends_on arch: :arm64` and no `conflicts_with`. The shared model folder is never in `zap`.

## Manual gates on the release Mac

| Gate | When |
|---|---|
| `make test-model-gated` | Each release |
| Real voice in native, Electron and browser targets | Each release |
| Microphone and Fn across processes | Each release |
| Permissions on a clean account | Onboarding or permission changes, and always for 0.1.0 |
| Real Sparkle update from the previous version | Each release, and before announcing 0.1.1 |
| Clean Homebrew install | Each release |
| VoiceOver checklist | Each minor release |
| Controller matrix and field corpus | Model or FluidAudio changes |

## Rollback

Delete the release and its tag, then revert the tap commit. With a `latest` feed, deleting the release restores the previous feed.
