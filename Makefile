SHELL := /bin/bash
CONFIG ?= Debug
DERIVED := build
APP := $(DERIVED)/Build/Products/$(CONFIG)/zWGestures.app

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

.PHONY: all gen build test run clean reset-tcc

all: build

## Regenerate zWGestures.xcodeproj from project.yml
gen:
	xcodegen generate

## Build the app bundle
build: gen
	$(XCODEBUILD) build

## Run the SwiftPM unit tests for the ZWGCore package
test:
	$(SWIFT_TEST)

## Launch the built app
run: build
	open "$(APP)"

clean:
	rm -rf $(DERIVED) ZWGCore/.build

## Show the codesign/TCC status of the built app
info: build
	@file "$(APP)/Contents/MacOS/zWGestures"
	@codesign -dv --verbose=2 "$(APP)" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier" || true
