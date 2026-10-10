#!/usr/bin/env bash
#
# Build the distributable artifacts into dist/:  an ad-hoc signed .app, a dmg, a zip, and checksums.
#
# Why ad-hoc rather than this machine's self-signed certificate
# ------------------------------------------------------------
# For a downloader the two are equivalent — neither satisfies Gatekeeper's "Developer ID signed and
# notarised" requirement — and ad-hoc needs no certificate at all, so the build is reproducible on
# any machine. Only this script overrides the signing identity; `project.yml` keeps the local
# certificate as the default so that day-to-day Debug builds keep their stable Accessibility grant.
#
# Three things this script gets right that are easy to get wrong. All three were found by actually
# running the Release path rather than by reasoning about it (see docs/ROADMAP.md §17):
#
#   1. `project.yml`'s Release config sets DEPLOYMENT_POSTPROCESSING=YES (strip before signing)
#      and CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO. Without the former the shipped binary carries the
#      builder's home directory 133 times — `.swift` source paths and `.o` object paths from the
#      linker's debug map — and without the latter it carries com.apple.security.get-task-allow,
#      which lets anyone attach a debugger. Both are asserted below rather than assumed.
#   2. `diskutil image create from` rather than `hdiutil create -srcfolder`: hdiutil's form is
#      deprecated on macOS 27 and fails outright. diskutil's form mounts a volume, so it cannot run
#      inside a restricted sandbox — run this from a normal terminal.
#   3. The assets are uploaded twice on purpose: once under a versioned name, and once under a fixed
#      name, because the download button points at `releases/latest/download/<fixed name>`.
#
# The dmg holds the app plus a symlink to /Applications and nothing else — no custom background
# image or icon positions, deliberately: that is cosmetic and is the part most likely to break
# silently on an OS update.
#
# Usage:  scripts/make-dist.sh     (or `make dist`)
#
# Products (dist/):
#   zWGestures-<version>-arm64.dmg    versioned, for the checksums and the release assets
#   zWGestures-<version>-arm64.zip
#   zWGestures-arm64.dmg              fixed names: the download button points at
#   zWGestures-arm64.zip              releases/latest/download/<fixed name>, so they must not change
#   SHA256SUMS
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO_ROOT="$PWD"
DIST="$REPO_ROOT/dist"
DERIVED="$REPO_ROOT/build-release"
APP="$DERIVED/Build/Products/Release/zWGestures.app"

note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }

# MARK: - 打包前安全扫描（硬性，docs/OPEN-SOURCE-PLAN.md §5.5）

note "安全扫描"

tracked=$(git -C "$REPO_ROOT" ls-files | grep -iE 'license\.json|\.p12$|\.pem$|\.key$' || true)
[ -z "$tracked" ] || fail "版本库里出现了不该提交的文件：$tracked"
ok "版本库里没有 license.json / 证书 / 私钥"

# MARK: - 版本号

note "读取版本号"
VERSION=$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\(.*\)".*/\1/p' \
  "$REPO_ROOT/project.yml" | head -1)
[ -n "$VERSION" ] || fail "project.yml 里读不到 MARKETING_VERSION"
ok "MARKETING_VERSION = $VERSION"

# MARK: - 构建

note "生成工程（project.yml 是源）"
command -v xcodegen >/dev/null || fail "没有 xcodegen，先 brew install xcodegen"
xcodegen generate >/dev/null

note "构建 Release（ad-hoc 签名）"
mkdir -p "$DERIVED"
LOG="$DERIVED/xcodebuild.log"
xcodebuild -project zWGestures.xcodeproj -scheme zWGestures \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO \
  build > "$LOG" 2>&1 \
  || { tail -40 "$LOG" >&2; fail "xcodebuild 失败，完整日志：$LOG"; }
ok "构建完成"

# MARK: - 校验

note "校验产物"
[ -d "$APP" ] || fail "没有产物：$APP"

signature=$(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^Signature=//p')
[ "$signature" = "adhoc" ] || fail "签名是「$signature」，应为 adhoc —— 下载者拿到的会是另一个身份"
ok "签名 adhoc"

archs=$(lipo -archs "$APP/Contents/MacOS/zWGestures")
[ "$archs" = "arm64" ] || fail "架构是 $archs，应为 arm64"
ok "架构 arm64"

built=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$built" = "$VERSION" ] || fail "产物版本 $built 与 project.yml 的 $VERSION 不一致"
ok "版本 $built"

# 出厂默认手势包（两份语言包 + 译名表 + 目录结构）的断言在共用脚本里 —— CI 的 App target job
# 查的是同一件事，抄两份就会漂（2026-10-06 就是这么红了一次）。
note "校验出厂默认手势包"
bash "$REPO_ROOT/scripts/check-defaults-in-bundle.sh" "$APP"

if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "get-task-allow"; then
  fail "产物带着 com.apple.security.get-task-allow（调试用 entitlement），不该分发"
fi
ok "没有调试 entitlement"

if grep -rqF "$HOME" "$APP" 2>/dev/null; then
  fail "产物里出现了构建者主目录（$HOME），它会随下载包一起公开 —— 见脚本头部第 3 条"
fi
ok "产物里没有构建者主目录"

if find "$APP" \( -name 'license.json' -o -name '*.p12' -o -name '*.pem' -o -name '*.key' \) \
    | grep -q .; then
  fail "产物里出现了不该有的文件"
fi
ok "产物里没有敏感文件"

# MARK: - 打包

note "打包"
rm -rf "$DIST"
mkdir -p "$DIST/staging"
ditto "$APP" "$DIST/staging/zWGestures.app"
ln -s /Applications "$DIST/staging/Applications"

ZIP="$DIST/zWGestures-$VERSION-arm64.zip"
DMG="$DIST/zWGestures-$VERSION-arm64.dmg"

ditto -c -k --keepParent "$APP" "$ZIP"
ok "zip  $(basename "$ZIP")"

DMG_LOG="$DERIVED/diskutil.log"
diskutil image create from --format UDZO --volumeName zWGestures \
  "$DIST/staging" "$DMG" > "$DMG_LOG" 2>&1 \
  || { cat "$DMG_LOG" >&2; fail "创建 dmg 失败（这个命令需要挂载卷，不能在受限沙箱里跑）"; }
ok "dmg  $(basename "$DMG")"

rm -rf "$DIST/staging"
cp "$ZIP" "$DIST/zWGestures-arm64.zip"
cp "$DMG" "$DIST/zWGestures-arm64.dmg"
ok "固定文件名别名（下载按钮指向 releases/latest/download/，文件名不能变）"

( cd "$DIST" && shasum -a 256 ./*.dmg ./*.zip > SHA256SUMS )
ok "SHA256SUMS"

note "完成，产物在 dist/"
ls -la "$DIST"
echo
cat "$DIST/SHA256SUMS"
echo
echo "下一步（发版，需另行确认）："
echo "  gh release create v$VERSION --notes-file docs/release-notes/$VERSION.md \\"
echo "    dist/zWGestures-$VERSION-arm64.dmg dist/zWGestures-$VERSION-arm64.zip \\"
echo "    dist/zWGestures-arm64.dmg dist/zWGestures-arm64.zip dist/SHA256SUMS"
