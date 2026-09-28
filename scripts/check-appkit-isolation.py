#!/usr/bin/env python3
"""Fail if an AppKit override that AppKit calls from geometry/hit-test paths is actor-isolated.

Why this exists
---------------
`NSView` and `NSWindow` are `@MainActor` on the SDK this project builds against, so every override
of their members inherits that isolation. Swift then inserts a runtime "am I actually on the main
actor?" check at the top of the override — and AppKit reaches some of these members from its
tracking-area and hit-testing machinery, where that check has already faulted and killed the app:

    crash report zWGestures-2026-09-28-211050.ips
    EXC_BAD_ACCESS / SIGSEGV in swift_task_isMainExecutorImpl
      _checkExpectedExecutor
      zWGestures  @objc TrailView.isFlipped.getter
      AppKit      _convertPoint_fromAncestor
      AppKit      ___nonOverridableViewHitTest_block_invoke
      AppKit      -[_NSTrackingAreaAKManager _mouseMoved:]

Marking such an override `nonisolated` removes the check; none of them read actor state, so the
opt-out is free. This script stops the marker from being dropped again, because the symptom is a
rare crash that unit tests cannot reach.

Usage: scripts/check-appkit-isolation.py [directory ...]
"""

import pathlib
import re
import sys

# Members AppKit queries while doing geometry, hit-testing, responder or window-status work.
CHECKED = (
    "isFlipped",
    "hitTest",
    "acceptsFirstResponder",
    "canBecomeKeyView",
    "canBecomeKey",
    "canBecomeMain",
    "menu",
)

OVERRIDE = re.compile(
    r"override\s+(?:var|func)\s+(" + "|".join(CHECKED) + r")\b"
)


def check(root: pathlib.Path) -> list[str]:
    problems: list[str] = []
    for path in sorted(root.rglob("*.swift")):
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            if not OVERRIDE.search(line):
                continue
            # The marker may sit on the same line or just above it (long declarations wrap).
            if "nonisolated" in line:
                continue
            above = path.read_text().splitlines()[max(0, number - 3):number - 1]
            if any("nonisolated" in candidate for candidate in above):
                continue
            problems.append(f"{path}:{number}: {line.strip()}")
    return problems


def main(argv: list[str]) -> int:
    roots = [pathlib.Path(a) for a in argv[1:]] or [pathlib.Path("zWGestures")]
    missing = [r for r in roots if not r.exists()]
    if missing:
        print(f"路径不存在：{', '.join(str(r) for r in missing)}", file=sys.stderr)
        return 2

    problems: list[str] = []
    for root in roots:
        problems.extend(check(root))

    if problems:
        print("AppKit 覆写缺少 nonisolated（会插入运行时主 actor 检查，已知会崩）：")
        for problem in problems:
            print(f"  {problem}")
        print()
        print("修法：加上 nonisolated，例如 `nonisolated override var isFlipped: Bool { true }`")
        print("理由与崩溃报告见 docs/ROADMAP.md §8。")
        return 1

    print("AppKit 覆写检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
