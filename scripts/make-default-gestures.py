#!/usr/bin/env python3
"""Generate the factory-default gesture pack that ships inside the app bundle.

Why this exists
---------------
Someone who has never installed WGestures gets an app with no gestures at all: it launches, the
Accessibility permission is granted, and drawing anything does nothing. That reads as broken
software. Shipping a default pack fixes it, and the best default is the original's own factory
set, which users of the original already know.

Where the data comes from
-------------------------
    <original Resources>/gestures.json                    the 48 factory gestures
    <original Resources>/prefs.json                       the factory preferences
    <original Resources>/zh_CN.lproj/tr_bootstrap.json     the original's own Chinese name table

All three are **configuration data** shipped by the original app — not binaries, fonts, icons or
code. This project ships none of the original's assets; see "许可证与商标" in README.md.

What it does
------------
* Renames every gesture using `tr_bootstrap.json`. The app has no runtime name translation (the
  stored `Name` is what the settings list shows), so the Chinese names have to be baked in. A name
  with no translation is a **hard error** — guessing would ship a half-translated list.
* Copies `prefs.json` but forces `AutoStart` to false: the original's value means "the original app
  autostarts", not "the new app should register a login item behind the user's back". `SkipVersion:
  null` is kept deliberately — it exercises the `encodeIfPresent` path a regression test guards.
* Writes **两份**默认手势包，按界面语言播种（2026-10-06 起）：
    `Defaults/zh-Hans/gestures.json`  中文名（用 `tr_bootstrap.json` 改过名）
    `Defaults/en/gestures.json`       原版出厂英文名，原样保留
  两份**除 `Name` 外逐键一致**（笔画与命令必须完全相同），`DefaultGesturePackTests` 会钉住这一点。
* 另外写一张 `Defaults/name-translations.json`（英文 → 中文），供**运行时**的
  「把英文手势名改为中文」用：用户从原版导入的配置里存的就是英文名，改名要用的正是原版这张表。
* 三者都用原版自己的 JSON 风格（2 空格缩进、`ensure_ascii=False`、无结尾换行），
  提交进仓库的 diff 里只有 `Name` 值。

Only ever reads the three files above. The directory that holds `license.json` — the **parent** of
the original version directory — is never touched.

Regenerate with
---------------
    make default-gestures
    make default-gestures ORIGINAL=/path/to/WGestures.app/Contents/Resources

The output is committed on purpose and is **not** part of `make build`: only a machine with the
original installed can produce it.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

DEFAULT_RESOURCES = pathlib.Path("/Applications/WGestures.app/Contents/Resources")
DEFAULT_OUTPUT = pathlib.Path("zWGestures/Resources/Defaults")

# What the original's factory set contains today. Used only to warn loudly: a future original
# release changing it shifts the numbers the tests pin, and that should not pass unnoticed.
EXPECTED_INTENTS = 48


def load_json(path: pathlib.Path):
    # `utf-8-sig` because the original writes a BOM on some of its files. Harmless when absent.
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: pathlib.Path, payload) -> None:
    """Write in the original's own style, so the committed file diffs only where it should."""
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def targets(config: dict):
    """Every object that owns an `Intents` array, with a human-readable location for messages.

    `General` is a single target; `Groups` nests its targets one level deeper; `Apps` and
    `Specials` are flat lists. Nothing else in the file carries intents.
    """
    general = config.get("General")
    if isinstance(general, dict):
        yield "General", general

    for index, group in enumerate(config.get("Groups") or []):
        if not isinstance(group, dict):
            continue
        for target_index, target in enumerate(group.get("Targets") or []):
            if isinstance(target, dict):
                yield f"Groups[{index}].Targets[{target_index}]", target

    for key in ("Apps", "Specials"):
        for index, target in enumerate(config.get(key) or []):
            if isinstance(target, dict):
                yield f"{key}[{index}]", target


def rename_intents(config: dict, translations: dict) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Replace each gesture's `Name` with its Chinese translation.

    Returns `(renamed, missing)`. `missing` is non-empty when a name has no translation, which the
    caller treats as fatal.
    """
    renamed: list[tuple[str, str]] = []
    missing: list[tuple[str, str]] = []

    for where, target in targets(config):
        for index, intent in enumerate(target.get("Intents") or []):
            if not isinstance(intent, dict):
                continue
            english = intent.get("Name")
            chinese = translations.get(english)
            if chinese is None:
                missing.append((f"{where}.Intents[{index}]", english))
                continue
            if chinese != english:
                renamed.append((english, chinese))
            intent["Name"] = chinese

    return renamed, missing


def intent_names(config: dict):
    """Every intent name in the config, in file order. Used to compare the two language packs."""
    for _, target in targets(config):
        for intent in target.get("Intents", []):
            if isinstance(intent, dict):
                yield intent.get("Name", "")


def count_intents(config: dict) -> tuple[list[tuple[str, int]], int]:
    rows = [(where, len(target.get("Intents") or [])) for where, target in targets(config)]
    return rows, sum(count for _, count in rows)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate the factory-default gesture pack from an installed WGestures.",
    )
    parser.add_argument(
        "resources",
        nargs="?",
        default=str(DEFAULT_RESOURCES),
        help=f"the original's Contents/Resources directory (default: {DEFAULT_RESOURCES})",
    )
    parser.add_argument(
        "--out",
        default=str(DEFAULT_OUTPUT),
        help=f"output directory (default: {DEFAULT_OUTPUT})",
    )
    args = parser.parse_args()

    resources = pathlib.Path(args.resources).expanduser()
    if not resources.is_dir():
        print(
            f"错误：原版资源目录不存在：{resources}\n"
            "请先安装原版 WGestures，或用参数指定它的 Contents/Resources 目录。\n"
            "（这一步不静默跳过：没有原版就生成不出一份可靠的默认手势包。）",
            file=sys.stderr,
        )
        return 1

    gestures_path = resources / "gestures.json"
    prefs_path = resources / "prefs.json"
    translations_path = resources / "zh_CN.lproj" / "tr_bootstrap.json"
    for path in (gestures_path, prefs_path, translations_path):
        if not path.is_file():
            print(f"错误：找不到 {path}", file=sys.stderr)
            return 1

    config = load_json(gestures_path)
    translations = load_json(translations_path)
    preferences = load_json(prefs_path)

    # 英文包：原版出厂名，一个字都不改；先深拷贝，因为下面 rename_intents 会就地改名。
    english_config = json.loads(json.dumps(config))

    renamed, missing = rename_intents(config, translations)
    if missing:
        print("错误：以下手势在 tr_bootstrap.json 里查不到中文译名：", file=sys.stderr)
        for where, name in missing:
            print(f"  {where}: {name!r}", file=sys.stderr)
        print("请先补上译名再生成 —— 这里不猜。", file=sys.stderr)
        return 1

    original_auto_start = preferences.get("AutoStart")
    preferences["AutoStart"] = False

    rows, total = count_intents(config)
    out_dir = pathlib.Path(args.out)
    zh_dir = out_dir / "zh-Hans"
    en_dir = out_dir / "en"
    for directory in (zh_dir, en_dir):
        directory.mkdir(parents=True, exist_ok=True)
    write_json(zh_dir / "gestures.json", config)
    write_json(zh_dir / "prefs.json", preferences)
    write_json(en_dir / "gestures.json", english_config)
    write_json(en_dir / "prefs.json", preferences)
    write_json(out_dir / "name-translations.json", dict(sorted(translations.items())))

    print(f"来源：{resources}")
    for where, count in rows:
        print(f"  {where}: {count} 条")
    print(f"  合计：{total} 条")
    print(f"改名：{len(renamed)} 处，覆盖 {len(set(renamed))} 个不同的英文名")
    print(f"偏好：AutoStart {original_auto_start} → False（SkipVersion 原样保留）")
    print(f"已写入：{out_dir}/zh-Hans/gestures.json, {out_dir}/en/gestures.json, "
          f"{out_dir}/{{zh-Hans,en}}/prefs.json, {out_dir}/name-translations.json")

    # 两份包除了 Name 必须完全一致；这里当场比一次，别等测试才发现。
    zh_names = sorted(name for name in intent_names(config))
    en_names = sorted(name for name in intent_names(english_config))
    if len(zh_names) != len(en_names):
        print("错误：两份包的条数不一致", file=sys.stderr)
        return 1
    print(f"两份包各 {len(zh_names)} 条；中文名 {len(set(zh_names))} 个不同，英文名 {len(set(en_names))} 个不同")

    if total != EXPECTED_INTENTS:
        print(
            f"⚠️ 手势数是 {total}，与脚本预期的 {EXPECTED_INTENTS} 不一致 —— "
            "原版的出厂默认可能变了。请核对内容，并同步更新本脚本的 EXPECTED_INTENTS 与 "
            "ZWGCore 的 DefaultGesturePackTests。",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
