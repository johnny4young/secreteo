# Dev shortcuts. project.yml is the source of truth for the Xcode project.
SIGN_IDENTITY ?= Developer ID Application: Johnny IV Young (JGWX5ZT2N2)
DEV_APP := /Applications/Secreteo Dev.app

.PHONY: project build test lint hygiene test-ui-smoke test-ui-full install

project:
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

# Installs the Dev identity only, signed for real so permissions survive reinstalls.
install: project
	-osascript -e 'tell application "Secreteo Dev" to quit' 2>/dev/null
	xcodebuild -project Secreteo.xcodeproj -scheme Secreteo -configuration Release -quiet \
		-derivedDataPath build/install -destination 'platform=macOS,arch=arm64' \
		PRODUCT_NAME="Secreteo Dev" PRODUCT_BUNDLE_IDENTIFIER=com.johnny4young.secreteo.dev build
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" \
		"build/install/Build/Products/Release/Secreteo Dev.app"
	codesign --verify --deep --strict "build/install/Build/Products/Release/Secreteo Dev.app"
	rm -rf "$(DEV_APP)"
	cp -R "build/install/Build/Products/Release/Secreteo Dev.app" "$(DEV_APP)"
