# Dev shortcuts. project.yml is the source of truth for the Xcode project.
SIGN_IDENTITY ?= Developer ID Application: Johnny IV Young (JGWX5ZT2N2)
DEV_APP := /Applications/Secreteo Dev.app

.PHONY: project build test lint hygiene test-ui-smoke test-ui-full test-model-gated release-dryrun install

project:
	scripts/fetch-sparkle.sh
	xcodegen generate --quiet

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test --parallel -Xswiftc -warnings-as-errors

lint:
	swiftlint lint --strict --no-cache

hygiene:
	scripts/check-repository-hygiene.sh

test-ui-smoke:
	scripts/run-ui-tests.sh smoke

test-ui-full:
	scripts/run-ui-tests.sh full

# Real models from a named scratch store, never an installed app's. See docs/RELEASING.md.
test-model-gated:
	node scripts/model_gated.mjs

# Packages two versions and a feed with a throwaway key. The update itself runs in CI.
release-dryrun:
	scripts/release-dryrun.sh package

# Installs the Dev identity only, signed for real so permissions survive reinstalls.
install: project
	-osascript -e 'tell application "Secreteo Dev" to quit' 2>/dev/null
	xcodebuild -project Secreteo.xcodeproj -scheme Secreteo -configuration Release -quiet \
		-derivedDataPath build/install -destination 'platform=macOS,arch=arm64' \
		APP_PRODUCT_NAME="Secreteo Dev" APP_BUNDLE_IDENTIFIER=com.johnny4young.secreteo.dev \
		SECRETEO_GLOBAL_DICTATION=YES SPARKLE_PUBLIC_ED_KEY= build
	scripts/sign-app.sh "build/install/Build/Products/Release/Secreteo Dev.app" "$(SIGN_IDENTITY)"
	rm -rf "$(DEV_APP)"
	cp -R "build/install/Build/Products/Release/Secreteo Dev.app" "$(DEV_APP)"
