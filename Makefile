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

## First run after a fresh clone: create the local self-signed certificate.
##
## `make build` signs with a **stable local identity** on purpose. Ad-hoc signing would derive its
## designated requirement from the CDHash, which changes on every compile, so macOS would treat
## each build as a brand-new app and the Accessibility grant would have to be re-issued every time.
## The certificate is created once and lives in its own keychain (never in the login keychain).
bootstrap:
	@if security find-certificate -c "zWGestures Local Signing" "$(SIGNING_KEYCHAIN)" >/dev/null 2>&1; then \
		echo "签名证书已就绪：zWGestures Local Signing"; \
	else \
		echo "未找到签名证书，开始创建（只需一次）…"; \
		bash scripts/create-signing-cert.sh; \
	fi
	@echo
	@echo "下一步："
	@echo "  make build   构建（产物在 $(APP)）"
	@echo "  make run     构建并启动"
	@echo
	@echo "首次启动需要在「系统设置 › 隐私与安全性 › 辅助功能」里勾选 zWGestures ——"
	@echo "没有这个权限，全局事件拦截器和合成按键都无法工作。"

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

## Regenerate the factory-default gesture pack that ships inside the app bundle.
##
## Needs the original WGestures installed at /Applications/WGestures.app, or pass its resource
## directory: make default-gestures ORIGINAL=/path/to/WGestures.app/Contents/Resources
##
## The output (zWGestures/Resources/Defaults/) is committed on purpose and is deliberately NOT part
## of `build`: only a machine that has the original installed can produce it. Where the data comes
## from, and why it is safe to ship, is documented in scripts/make-default-gestures.py.
default-gestures:
	python3 scripts/make-default-gestures.py $(ORIGINAL)

## Build the distributable artifacts into dist/: ad-hoc signed app, dmg, zip, SHA256SUMS.
##
## Delegates to scripts/make-dist.sh — read its header for why the signing identity is ad-hoc
## there and what it guards against. Needs a normal terminal: creating the dmg mounts a volume,
## which a restricted sandbox refuses.
dist:
	bash scripts/make-dist.sh

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
	@# 先删干净再复制：`ditto` 是**合并**，上一版留在 bundle 里的旧资源会一直跟着 ——
	@# 2026-10-06 真踩到：/Applications 里同时存在新旧两套默认手势包布局（旧版的
	@# `Defaults/gestures.json` 与新的 `Defaults/{zh-Hans,en}/`），测试时容易被这些陈年文件误导。
	rm -rf "$(INSTALLED_APP)"
	ditto "$(APP)" "$(INSTALLED_APP)"
	@# 目录 mtime 必须刷新：ditto 会保留构建产物里的老时间戳，于是 app 目录看起来「没变过」，
	@# 靠 bundle 日期判断失效的图标缓存（Finder / 系统设置）就不会更新 —— 图片换了却仍显示旧图标。
	@touch "$(INSTALLED_APP)"
	@echo "已安装到 $(INSTALLED_APP)"

## Launch the built app with the settings window open
run-settings: stop build
	open --env ZWG_SETTINGS_PANEL=1 "$(APP)"

## Launch with a throwaway configuration directory — exactly what a fresh download sees.
##
## Exercises the first-run path (no config + no original WGestures → seed the built-in default
## pack) without touching your real configuration. `ZWG_CONFIG_DIR` is the only way to do that on a
## machine that already has one (see ConfigStore.defaultDirectory). The directory is kept so you can
## inspect what was seeded.
run-fresh: stop build
	rm -rf build/fresh-config
	open --env ZWG_CONFIG_DIR="$(CURDIR)/build/fresh-config" "$(APP)"

.PHONY: all gen bootstrap unlock-signing build lint test run run-debug run-settings run-fresh stop install icon default-gestures dist clean info

clean:
	rm -rf $(DERIVED) ZWGCore/.build

## Show the architecture and code signature of the built app
info: build
	@file "$(APP)/Contents/MacOS/zWGestures"
	@codesign -dv --verbose=4 "$(APP)" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" || true
	@codesign -d -r- "$(APP)" 2>&1 | tail -1
