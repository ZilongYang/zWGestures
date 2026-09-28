SHELL := /bin/bash
CONFIG ?= Debug
DERIVED := build
APP := $(DERIVED)/Build/Products/$(CONFIG)/zWGestures.app
INSTALLED_APP := /Applications/zWGestures.app

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

## Regenerate the app icon. VARIANT=corner (default) | swoosh picks the subject stroke.
##
## The module cache must live inside the workspace: a restricted shell cannot write the default
## one under /var/folders, and the failure reads like a compiler bug rather than a sandbox denial.
icon:
	CLANG_MODULE_CACHE_PATH="$(CURDIR)/build/swift-module-cache" \
	SWIFT_MODULECACHE_OVERRIDE="$(CURDIR)/build/swift-module-cache" \
	swift scripts/make-app-icon.swift $(or $(VARIANT),corner)

## Source-level guards that unit tests cannot express (see docs/ROADMAP.md §8)
lint:
	@python3 scripts/check-appkit-isolation.py

## Run the SwiftPM unit tests for the ZWGCore package
test: lint
	$(SWIFT_TEST)

## Quit a running instance.
##
## `open` on an app that is already running only brings the existing process forward — it does NOT
## start the freshly built binary. Without this step it is easy to spend a whole test cycle looking
## at the previous build, which has already happened once.
stop:
	@if pgrep -x zWGestures >/dev/null; then \
		echo "先退出正在运行的实例（否则 open 只会把旧进程切到前台）"; \
		osascript -e 'tell application "zWGestures" to quit' >/dev/null 2>&1 || true; \
		for i in 1 2 3 4 5 6; do pgrep -x zWGestures >/dev/null || break; sleep 0.5; done; \
		pgrep -x zWGestures >/dev/null && echo "警告：实例仍未退出，请从菜单栏手动退出" || true; \
	fi

## Launch the built app
run: stop build
	open "$(APP)"

## Launch the built app with the debug HUD open
run-debug: stop build
	open --env ZWG_DEBUG_HUD=1 "$(APP)"

## Copy the built app to /Applications (a stable path is required by the login item)
##
## Overwrites in place instead of deleting first: `SMAppService` associates the login item with
## the bundle, and rebuilding the bundle from scratch is the prime suspect for the `.notFound`
## status recorded in docs/ROADMAP.md §10.
install: stop build
	ditto "$(APP)" "$(INSTALLED_APP)"
	@echo "已安装到 $(INSTALLED_APP)"

## Launch the built app with the settings window open
run-settings: stop build
	open --env ZWG_SETTINGS_PANEL=1 "$(APP)"

.PHONY: all gen unlock-signing build lint test run run-debug run-settings stop install icon clean info

clean:
	rm -rf $(DERIVED) ZWGCore/.build

## Show the architecture and code signature of the built app
info: build
	@file "$(APP)/Contents/MacOS/zWGestures"
	@codesign -dv --verbose=4 "$(APP)" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" || true
	@codesign -d -r- "$(APP)" 2>&1 | tail -1
