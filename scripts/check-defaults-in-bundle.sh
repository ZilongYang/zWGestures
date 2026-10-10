#!/usr/bin/env bash
#
# 校验一个**已经构建好的** zWGestures.app 里有没有出厂默认手势包，以及目录结构对不对。
#
# 为什么单独拆成一个脚本
# ----------------------
# 这条断言原来在 `.github/workflows/ci.yml` 和 `scripts/make-dist.sh` 里**各有一份拷贝**。
# 第 3 期把出厂默认包改成按界面语言分目录（`Defaults/<zh-Hans|en>/`）之后，只有 make-dist 那份
# 跟上了（见 commit 1313e73），CI 那份还在检查旧的平铺路径 `Defaults/gestures.json`，于是
# 2026-10-06 起 `App target 编译` job 一直红 —— 而 App 本身一直是编译通过的。断言抄两份就会漂，
# 所以合成一份：任何改动只改这里。
#
# 这里**不**断言条数与中文名。那些是「仓库里的包」的内容属性，ZWGCore 的
# `DefaultGesturePackTests` 已经把它们钉死（48 条、确切的中文名册、两份包除名字外逐键一致），
# 并且由另一个 job 的 `make test` 真跑。本脚本只管仓库测试**看不到**的那件事：
# 目录结构有没有真的进 bundle —— XcodeGen 会把普通的 .json 资源平铺到 Resources 根目录，
# 少了 folder reference，新装用户打开 app 就是一条手势都没有。
#
# Usage: scripts/check-defaults-in-bundle.sh <path/to/zWGestures.app>
set -euo pipefail

APP="${1:-}"

fail() { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }

[ -n "$APP" ] || fail "用法：$0 <zWGestures.app 路径>"
[ -d "$APP" ] || fail "产物不存在：$APP"

DEFAULTS="$APP/Contents/Resources/Defaults"

# 1) 两份语言包（各有手势包与偏好）与译名表都要在，且必须保持 `Defaults/<语言>/` 这层结构。
#    变量一律写成 ${x}：后面紧跟全角括号时，bash 在 UTF-8 locale 下会把多字节字符的首字节
#    当成变量名的一部分，报成「unbound variable」而不是这里想报的那句话。
for pack in zh-Hans en; do
  for file in gestures.json prefs.json; do
    [ -f "$DEFAULTS/${pack}/${file}" ] \
      || fail "产物里没有 ${pack} 的出厂默认包文件：Defaults/${pack}/${file}（目录结构被平铺了？）"
  done
done
[ -f "$DEFAULTS/name-translations.json" ] \
  || fail "产物里没有手势名译名表：Defaults/name-translations.json"
ok "两份出厂默认手势包（zh-Hans / en）与译名表都在，且保持了目录结构"

# 2) 两份包除手势名（Name）外必须逐键一致 —— 否则中英文用户的手势行为会不一样。
#    这里只比「把名字抹掉后是否完全相同」，够挡住「只改了名字」之外的任何漂移。
python3 - "$DEFAULTS" <<'PY_CHECK' || fail "两份默认包的笔画或命令不一致"
import json, pathlib, sys

root = pathlib.Path(sys.argv[1])


def intents(language):
    data = json.loads((root / language / "gestures.json").read_text(encoding="utf-8"))
    out = []

    def walk(target):
        for intent in target.get("Intents") or []:
            copy = dict(intent)
            copy.pop("Name", None)
            out.append(copy)

    general = data.get("General")
    if isinstance(general, dict):
        walk(general)
    for key in ("Apps", "Specials"):
        for target in data.get(key) or []:
            walk(target)
    for group in data.get("Groups") or []:
        for target in group.get("Targets") or []:
            walk(target)
    return out


zh, en = intents("zh-Hans"), intents("en")
sys.exit(0 if zh and zh == en else 1)
PY_CHECK
ok "两份默认包除手势名外逐键一致"
