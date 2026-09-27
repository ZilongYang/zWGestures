SHELL := /bin/bash
CONFIG ?= Debug
DERIVED := build
APP := $(DERIVED)/Build/Products/$(CONFIG)/zWGestures.app

SIGNING_KEYCHAIN := $(HOME)/Library/Keychains/zWGestures.keychain-db
SIGNING_KEYCHAIN_PASSWORD := zwgestures

# `swift test` needs an isolated module cache and --disable-sandbox when run inside a
# restricted (sandboxed) shell; both are harmless in a normal terminal.
SWIFT_TEST := cd ZWGCore && SWIFTPM_MODULECACHE_OVERRIDE="$$PWD/.build/modulecache" \
	CLANG_MODULE_CACHE_PATH="$$PWD/.build/modulecache" \
	swift test --disable-sandbox --cache-path .build/cache --config-path .build/config \
	--security-path .build/security --scratch-path .build --manifest-cache none

XCODEBUILD := xcodebuild -project zWGestures.xcodeproj -scheme zWGestures -configuration $(CONFIG) \
	-derivedDataPath $(DERIVED) \
	-clonedSourcePackagesDirPath $(DERIVED)/SourcePackages \
	-packageCachePath $(DERIVED)/PackageCache

.PHONY: all gen unlock-signing build test run clean info

all: build

## Regenerate zWGestures.xcodeproj from project.yml
gen:
	xcodegen generate

## Unlock the dedicated signing keychain so xcodebuild can sign unattended
unlock-signing:
	@security unlock-keychain -p "$(SIGNING_KEYCHAIN_PASSWORD)" "$(SIGNING_KEYCHAIN)" 2>/dev/null \
		|| echo "提示：签名钥匙串尚未创建，请先运行 scripts/create-signing-cert.sh"

## Build the app bundle
build: gen unlock-signing
	$(XCODEBUILD) build

## Run the SwiftPM unit tests for the ZWGCore package
test:
	$(SWIFT_TEST)

## Launch the built app
run: build
	open "$(APP)"

clean:
	rm -rf $(DERIVED) ZWGCore/.build

## Show the architecture and code signature of the built app
info: build
	@file "$(APP)/Contents/MacOS/zWGestures"
	@codesign -dv --verbose=4 "$(APP)" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" || true
	@codesign -d -r- "$(APP)" 2>&1 | tail -1
