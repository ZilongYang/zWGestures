#!/usr/bin/env python3
"""Fail if an AppKit override or AppKit protocol callback is actor-isolated.

Why this exists
---------------
`NSView` and `NSWindow` are `@MainActor` on the SDK this project builds against, so every override
of their members inherits that isolation. The same is true for **any** AppKit protocol a
`@MainActor` type conforms to — `NSMenuDelegate` included. Swift then inserts a runtime "am I
actually on the main actor?" check at the top of the member, and AppKit reaches some of them from
paths where that check has already faulted and killed the app:

    crash report zWGestures-2026-09-28-211050.ips
    EXC_BAD_ACCESS / SIGSEGV in swift_task_isMainExecutorImpl
      _checkExpectedExecutor
      zWGestures  @objc TrailView.isFlipped.getter
      AppKit      _convertPoint_fromAncestor
      AppKit      ___nonOverridableViewHitTest_block_invoke
      AppKit      -[_NSTrackingAreaAKManager _mouseMoved:]

    crash report zWGestures-2026-10-06-024535.ips
    EXC_BAD_ACCESS / SIGBUS in swift_task_isMainExecutorImpl
      _checkExpectedExecutor
      zWGestures  @objc StatusItemController.menuWillOpen(_:)
      AppKit      -[NSMenu _sendMenuOpeningNotification:]
      FrontBoardServices -[FBSSceneObserver scene:handlePrivateActions:]

Marking an override `nonisolated` removes the check; none of them read actor state, so the opt-out
is free. A protocol callback is usually better off not being implemented at all. This script stops
either from being dropped again, because the symptom is a rare crash that unit tests cannot reach.

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

# AppKit callbacks that are **not** `override`s — protocol implementations inherit the isolation of
# the conforming type and get the very same runtime check inserted at their entry.
#
# This was a real blind spot: the check above only matched `override var/func`, so
# `@MainActor final class StatusItemController: NSObject, NSMenuDelegate` passed lint and then
# crashed the app from AppKit's status-item scene path:
#
#     crash report zWGestures-2026-10-06-024535.ips
#     EXC_BAD_ACCESS / SIGBUS in swift_task_isMainExecutorImpl
#       _checkExpectedExecutor
#       zWGestures  @objc StatusItemController.menuWillOpen(_:)
#       AppKit      -[NSMenu _sendMenuOpeningNotification:]
#       AppKit      -[NSSceneStatusItem _beginExpandedInterfaceSession:]
#       FrontBoardServices -[FBSSceneObserver scene:handlePrivateActions:]
#
# `NSApplicationDelegate`'s launch/terminate methods are deliberately **not** listed: they run on
# the normal application-lifecycle path, where this check has never faulted in daily use. If one of
# them ever crashes, add it here and make it nonisolated.
DELEGATE_CALLBACKS = (
    "menuWillOpen",
    "menuNeedsUpdate",
    "menuWillClose",
    "validateMenuItem",
)

CALLBACK = re.compile(
    r"func\s+(" + "|".join(DELEGATE_CALLBACKS) + r")\s*\("
)

# Callbacks that must be handed a **function reference**, never a closure literal written in a
# main-actor context. The same isolation inference bites here: a closure literal formed inside a
# `@MainActor` method inherits that isolation, and passing it to a plain (non-`@Sendable`) callback
# makes the compiler emit an `assumeIsolated` thunk.
#
# This is exactly how the 2026-10-06 crash happened (`zWGestures-2026-10-06-030632.ips`):
#
#     closure #1 in EngineController.startPanicMonitors()
#     → swift_task_isMainExecutorImpl → SIGSEGV (0x0)
#     ← AppKit GlobalObserverHandler ← HIToolbox DispatchEventToHandlers
#
# The fix is to pass a file-scope / `nonisolated` function that only reads non-isolated state.
NEEDS_FUNCTION_REFERENCE = (
    "addGlobalMonitorForEvents",
    "addLocalMonitorForEvents",
)

# GCD/Timer entry points that swallow a closure which then inherits main-actor isolation. The
# documented remedy is a `Task` loop (`Task { @MainActor in … }` / `try await Task.sleep`), which
# hops properly instead of asserting that it is already on the main actor.
FORBIDDEN_ASYNC_HOSTS = (
    "DispatchQueue.main.async",
    "DispatchQueue.main.sync",
    "Timer.scheduledTimer",
    "Timer(timeInterval",
)


def code_only(line: str) -> str:
    """把行内注释去掉：注释里提到这些写法（本节就在反复提）不该被误报。"""
    index = line.find("//")
    return line if index < 0 else line[:index]


def check(root: pathlib.Path) -> list[str]:
    problems: list[str] = []
    for path in sorted(root.rglob("*.swift")):
        lines = [code_only(line) for line in path.read_text().splitlines()]
        for number, line in enumerate(lines, start=1):
            if any(host in line for host in FORBIDDEN_ASYNC_HOSTS):
                problems.append(
                    f"{path}:{number}: {line.strip()}  ← 改用 Task 循环（见 ROADMAP 第 8、23 节）"
                )
                continue

            if any(host in line for host in NEEDS_FUNCTION_REFERENCE):
                window = "\n".join(lines[number - 1:number + 4])
                if "handler:" not in window:
                    problems.append(
                        f"{path}:{number}: {line.strip()}"
                        "  ← 必须传函数引用（不能写闭包字面量，见 ROADMAP 第 23 节）"
                    )
                continue

            if not (OVERRIDE.search(line) or CALLBACK.search(line)):
                continue
            # The marker may sit on the same line or just above it (long declarations wrap).
            if "nonisolated" in line:
                continue
            above = lines[max(0, number - 3):number - 1]
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
        print("AppKit 覆写/协议回调/异步回调写法检查未通过（都会插入运行时主 actor 检查，已知会崩）：")
        for problem in problems:
            print(f"  {problem}")
        print()
        print("修法：")
        print("  · 覆写：加 nonisolated，例如 `nonisolated override var isFlipped: Bool { true }`")
        print("  · 协议回调（如 NSMenuDelegate.menuWillOpen）：更稳的做法是干脆不实现它，改成推送式刷新")
        print("  · NSEvent 监听：把处理器写成文件作用域 / nonisolated 函数，用 `handler:` 传函数引用")
        print("  · 周期性或延后执行：用 `Task { @MainActor in … }` + `try await Task.sleep`")
        print("理由与三份崩溃报告见 docs/ROADMAP.md 第 8、22、23 节。")
        return 1

    print("AppKit 覆写/协议回调/异步回调写法检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
