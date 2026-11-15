# Releasing

A `v*` tag runs `release.yml`. The owner approves the `release` Environment, and that is the only step that waits for a person ([D30](DECISIONS.md#d30-one-owner-decision-per-release)). Nothing reaches users before it. The release then publishes itself, and `update-cask.yml` checks what users get.

## Flow

1. `scripts/check_release.py` refuses a tag that differs from `MARKETING_VERSION`, has no `## <version>` section in `CHANGELOG.md`, is not on `main`, is not newer than every earlier `v*` tag, or has no Sparkle key.
2. Hygiene and tests.
3. Release build with the pinned toolchain: `macos-26`, Xcode 26.6.
4. Sign nested helpers and the app with no ignored failures.
5. Notarize and staple the app.
6. Build the DMG, then notarize and staple it.
7. Verify distribution and the app payload.
8. Launch the packaged app, since only a launch proves hardened runtime can load Sparkle.
9. `generate_appcast --ed-key-file - --download-url-prefix .../releases/download/v<version>/ --embed-release-notes`.
10. Verify the appcast, including its signature against the shipped key.
11. After the owner approves the `release` Environment for steps 3 to 10, publish the release and start `update-cask.yml`. A release published with the job's token raises no event of its own.
12. `update-cask.yml` updates the tap. Then `scripts/verify-published-release.sh` runs on a hosted Mac and checks four things: the live feed against the shipped key, the tap's version and sha256, a Homebrew install that Gatekeeper accepts, and a Sparkle update from the previous release through the live feed.

The feed stays at `releases/latest/download/appcast.xml`. Enclosures are versioned.

## Cutting a release

An agent does every step except the approval:

1. Open `chore: prepare <version>`. It sets `MARKETING_VERSION` in `project.yml` and moves the `## Unreleased` entries under `## <version>` in `CHANGELOG.md`. Use a patch version for fixes and a minor version for features.
2. Merge it when every check is green.
3. Check the merge commit, then tag it with the owner's account. A personal repository cannot let Actions bypass the tag ruleset.

   ```sh
   git fetch origin --tags && git checkout --detach <merge-sha>
   python3 scripts/check_release.py check v<version>
   git tag v<version> <merge-sha> && git push origin v<version>
   ```

4. Tell the owner the run is waiting for the `release` approval.
5. Watch `release.yml` publish, and `update-cask.yml` update the tap and pass `verify`. Report the release URL.

Rerunning a failed job finishes the same release. A fix to the code needs the next patch version. If something is wrong after publishing, see [Rollback](#rollback).

## Dry run

`scripts/release-dryrun.sh` packages versions 9.0.0 and 9.0.1 through `scripts/package-release.sh` with ad-hoc signing and a throwaway key, and builds a feed that holds both. These two are exactly what a tag builds. It then packages a third, instrumented 9.0.0 (`package-release.sh 9.0.0 instrumented`), which compiles `SECRETEO_UPDATE_DRYRUN` in its own derived data. That condition adds two things only: a launch argument that holds a practice lease until a file is deleted, and an immediate install, so Sparkle takes its relaunch path. `scripts/verify_release.py` refuses the argument in production and exact dry-run artifacts and requires it in the instrumented one.

On a hosted runner the update stage runs two scenarios against the same local feed:

1. It installs the exact 9.0.0 and waits for the real updater to replace it with 9.0.1 when the app quits.
2. It installs the instrumented 9.0.0 with the lease held. Sparkle must log a postponed relaunch, and the old process must stay up with 9.0.0 installed for 20 seconds. Once the file is deleted, Sparkle must install 9.0.1 and relaunch it with no `open` from the script.

CI runs it when packaging changes, and `nightly.yml` runs it every night. The instrumented build is not in the derived-data cache, so it compiles cold and adds its build time to every run. `make release-dryrun` runs the exact packaging on any Mac, and `scripts/release-dryrun.sh instrumented` adds the third DMG after it.

It cannot prove what needs the secrets: hardened runtime, notarization, stapling and Gatekeeper. Those stay in the real release.

## Secrets

Each set lives in its own Environment, so a job can read only what it needs.

| Environment | Secret | Use |
|---|---|---|
| `release` | `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD` | Developer ID certificate, base64 |
| `release` | `MACOS_CODE_SIGN_IDENTITY` | Signing identity. `scripts/verify_release.py` pins the team |
| `release` | `MACOS_NOTARY_KEY_ID`, `MACOS_NOTARY_KEY_ISSUER_ID`, `MACOS_NOTARY_KEY_P8` | App Store Connect API key, base64 |
| `release` | `SPARKLE_EDDSA_PRIVATE_KEY` | Appcast signature |
| `homebrew` | `TAP_DEPLOY_KEY` | Homebrew tap |
| `site` | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | Site, in `pages.yml` |

`release` requires the owner's approval and accepts only `v*` tags. `homebrew` accepts `v*` tags and `main`, and `site` accepts only `main`. A ruleset limits creating `v*` tags to the owner.

No provisioning profile is needed: the app uses neither iCloud nor Push.

## First-time setup

Run these once, in this order.

1. Create the key under its own account, or `generate_keys` returns another app's key from the Keychain, then back it up:

   ```sh
   make project
   Vendor/bin/generate_keys --account com.johnny4young.secreteo
   Vendor/bin/generate_keys --account com.johnny4young.secreteo -x ~/secreteo-sparkle.key
   ```

2. Open a PR that sets the printed public key in `SPARKLE_PUBLIC_ED_KEY` in `project.yml`. Done for 0.1.0.
3. Set the secrets. The P12 and the App Store Connect key go in as base64:

   ```sh
   gh secret set SPARKLE_EDDSA_PRIVATE_KEY --env release < ~/secreteo-sparkle.key
   base64 -i developer-id.p12 | gh secret set MACOS_CERTIFICATE_P12 --env release
   gh secret set MACOS_CERTIFICATE_PASSWORD --env release
   gh secret set MACOS_CODE_SIGN_IDENTITY --env release --body "Developer ID Application: Johnny IV Young (JGWX5ZT2N2)"
   gh secret set MACOS_NOTARY_KEY_ID --env release
   gh secret set MACOS_NOTARY_KEY_ISSUER_ID --env release
   base64 -i AuthKey.p8 | gh secret set MACOS_NOTARY_KEY_P8 --env release
   ```

4. Create a deploy key with write access on `johnny4young/homebrew-tap`, and set its private half:

   ```sh
   gh secret set TAP_DEPLOY_KEY --env homebrew < tap-deploy-key
   ```

5. For the site, create the project once, then set its two secrets with `--env site`:

   ```sh
   npx wrangler@4.151.0 pages project create secreteo --production-branch=main
   ```

Delete the local copies of the private keys once they are stored safely.

## Sparkle

- The EdDSA key belongs to this app. Back it up with `generate_keys -x` before the first public build. Losing it leaves users without automatic updates.
- Framework and tools come from one checksum-pinned fetch at one version.
- The public key is `SPARKLE_PUBLIC_ED_KEY` in `project.yml`. Debug builds and `make install` blank it, so only a release build checks the real feed. With it empty, the updater stays off.

## Homebrew

Same tap as the other apps, with its own deploy key. `packaging/Casks/secreteo.rb` is the template. The cask has `depends_on arch: :arm64` and no `conflicts_with`. The shared model folder is never in `zap`.

## Manual gates on the release Mac

None of these blocks a tag yet ([D29](DECISIONS.md#d29-manual-gates-do-not-block-a-release-yet)). The exact steps and what each should show are in the [runbook](RUNBOOK.md). `update-cask.yml` already runs a Sparkle update and a Homebrew install on a hosted Mac after every release.

| Gate | When |
|---|---|
| `make test-model-gated` | Each release |
| Real voice in native, Electron and browser targets | Each release |
| Microphone and Fn across processes | Each release |
| Permissions on a clean account | Onboarding or permission changes, and always for 0.1.0 |
| VoiceOver checklist | Each minor release |
| Controller matrix and field corpus | Model or FluidAudio changes |

## Model gate

`make test-model-gated` builds the test bundle in Release and runs four lanes against a scratch store you name: Parakeet v3 and Ultra on four public cells, Silero's speech gate on every cell, and the controller on the same four cells, whose resting footprint must stay within the [memory budget](DECISIONS.md#d26-total-memory-has-a-budget-written-before-it-was-measured). It exits nonzero unless each lane leaves a valid observation, and refuses any path inside an installed app's store or cache. It never downloads. Fill the store once with direct runs that set `SECRETEO_DICTATION_BASELINE_INSTALL=1`, `SECRETEO_ASR_COMPARE_INSTALL=1` and `SECRETEO_SPEECH_GATE_INSTALL=1`, as in [the corpus README](../Fixtures/DictationValidation/README.md#observe-the-installed-parakeet-adapter).

```sh
SECRETEO_MODEL_GATED_AUDIO=/absolute/scratch/dictation-audio \
SECRETEO_MODEL_GATED_MODELS=/absolute/scratch/models \
SECRETEO_MODEL_GATED_OUTPUT=/absolute/scratch/new-model-gate \
make test-model-gated
```

`summary.json` in the output says which lane failed. `observed` means a lane completed, not that a quality threshold passed.

## Rollback

The owner decides on a rollback. Delete the release and its tag, then revert the tap commit. With a `latest` feed, deleting the release restores the previous feed.

```sh
gh release delete v<version> --yes --cleanup-tag
```
