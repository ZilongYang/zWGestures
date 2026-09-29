# 贡献指南

感谢愿意帮忙。这份文档只讲**怎么把改动做对**：项目结构与构建细节见 [`README.md`](README.md)，
计划与进度见 [`docs/ROADMAP.md`](docs/ROADMAP.md)。

> [English README](README.en.md) · 中文

## 环境与构建

- Apple Silicon Mac（工程的 `ARCHS` 就是 `arm64`，Intel 机器构建不了 App）
- macOS 14+、Xcode 26.x
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

```bash
git clone https://github.com/ZilongYang/zWGestures.git
cd zWGestures

make bootstrap   # 只需一次：创建本机自签名证书
make build
make test
```

`make build` 用一把本机自签名证书签名，没有它构建会直接失败，`make bootstrap` 负责创建并放进独立
钥匙串。为什么要这么做（以及为什么不用登录钥匙串）见 README 的「签名与构建细节」。

## 提交前清单

```bash
make lint && make test
```

- `make lint` 跑 `scripts/check-appkit-isolation.py`，拦下漏标 `nonisolated` 的 AppKit 覆写。
- `make test` 先跑 lint，再跑 `ZWGCore` 的全部单元测试。**要求 0 failed。**
  在没装过原版 WGestures 的机器上会有 **1 项哨兵测试被跳过**，这是预期行为，不是问题。

新增的逻辑应该有测试。**可测试的纯逻辑请放进 `ZWGCore`**，不要留在 App target 里 ——
App target 的代码 `swift test` 够不着，放进 ZWGCore 才能被 CI 覆盖。安全关键的部分尤其如此：
事件掩码（`EventTapMask`）和「超时到什么程度就放弃」的策略（`EventTapHealthPolicy`）都有各自的
单测守着，请照这个标准来。

如果改了 `project.yml`，记得跑 `xcodegen generate`，并把生成的 `zWGestures.xcodeproj` 一起提交 ——
它是**有意提交进仓库**的生成物（为了让克隆下来就能直接打开）。

## 三条必须遵守的约定

这三条都来自真实发生过的事故，不是风格偏好。违反它们会以**崩溃**或**整机卡死**的形式表现出来。

### ① AppKit 覆写不要带 actor 隔离

`NSView` / `NSWindow` 在本 SDK 上是 `@MainActor`，覆写它们的成员会继承隔离，Swift 便会在入口插入
主 actor 运行时检查。而 AppKit 的**跟踪区域 / 命中测试**路径（`_NSTrackingAreaAKManager _mouseMoved:`
→ `hitTest` → `_convertPoint_fromAncestor` → `isFlipped`）会在那个检查上崩 ——
崩溃报告 `zWGestures-2026-09-28-211050.ips`，崩在 `@objc TrailView.isFlipped.getter`。

纯几何 / 谓词覆写一律写 `nonisolated`：

```
isFlipped   hitTest   acceptsFirstResponder   canBecomeKeyView   canBecomeKey   canBecomeMain   menu(for:)
```

`draw(_:)` 与鼠标事件处理**故意保持隔离**（走正常事件派发，且要读实例状态），不要顺手改成
`nonisolated`。

### ② 不要在 `Timer` 的 block 里碰 actor 隔离的状态

`Timer.scheduledTimer` 的 block 是 `@Sendable` 闭包，从里面访问 `@MainActor` 的状态会迫使编译器插入
`MainActor.assumeIsolated`。这个运行时断言在本工程的 debug dylib 布局下**直接崩掉**（SIGBUS，栈顶落在
`SerialExecutor.isMainExecutor`；崩溃报告 `zWGestures-2026-09-28-025040.ips`）。

需要周期性刷新时用 `Task` 循环：

```swift
refreshTask = Task { @MainActor [weak self] in
    while !Task.isCancelled {
        guard let self else { return }
        self.refresh()
        try? await Task.sleep(for: .milliseconds(100))
    }
}
```

同理，`NSWorkspace` 通知这类回调要 `Task { @MainActor in ... }` 跳进去，**不要**用
`MainActor.assumeIsolated` 断言「反正已经在主线程了」。

### ③ 事件拦截器绝不捕获键盘事件；超时后必须退避，最终必须放弃

事件 tap 的回调是**同步**的：系统必须等回调返回才投递该事件。鼠标移动可以被窗口服务器合并，回调慢
只会让轨迹变粗；**键盘事件无法合并**，所以只要把 `.keyDown` 放进掩码，回调一旦错过系统截止时间，
打字就会**整机失效** —— 鼠标手势还能识别、视频照常播放，用户只能强制关机。

2026-09-29 实测发生过：事件 tap 在 10 分钟内被系统以 `kCGEventTapDisabledByTimeout` 摘掉 42 次，
App 日志静默 7 分钟，最终强制断电。完整经过与证据见 [`docs/ROADMAP.md`](docs/ROADMAP.md) §13。

因此：

- 想捕获键盘 **必须**用 listen-only 的方式（`NSEvent` 监听），绝不能用 `.defaultTap` 的事件掩码。
  急停快捷键就是这么实现的。
- 超时后**必须退避**再启用，不能立即重新启用 —— 那等于把系统反复拖回一个跟不上的 tap。
- 一段窗口内超时过多**必须主动拆除自己**并告诉用户，而不是无限重试。恢复要是用户的显式操作。

这三条都有自动化守卫：`EventTapMaskTests`（掩码里绝不含键盘类型）与
`EventTapHealthPolicyTests`（放弃策略）。改这两块时先读它们的断言。

## 代码风格

- **注释写「为什么」，不写「是什么」。** 这个仓库注释密度偏高，是因为每一处反直觉的写法背后都有
  一个踩过的坑。请保持这个习惯：踩到新坑时，把原因写进注释，而不是只把代码改对。
- 用户可见的文案用中文（**界面目前仅中文**）。
- 提交信息用中文，首行 `type: 概述`，`type` 取 `feat` / `fix` / `docs` / `test` / `ci` / `refactor` /
  `chore`。正文说清「为什么」，有破坏性变更时显式写出影响。

## 报告缺陷

请用 issue 模板，并尽量带上**崩溃报告**：`~/Library/Logs/DiagnosticReports/zWGestures-*.ips`。
`.ips` 是文本文件（首行 JSON 头、第二行才是正文），可以直接拖进 issue。

运行日志：

```bash
log show --last 10m --predicate 'subsystem == "io.github.zilongyang.zwgestures"' --info --debug
```

界面相关的现象，菜单栏 →「显示调试面板」的 `state` / `tap` / `events` / `replays` 四行是主要判据。

## 界面多语言

**界面目前仅中文，英文化排在 v0.2.0。** 现在请不要提交零散的英文字符串改动 —— 那会让后续把字符串
抽进 String Catalog 更麻烦。如果你就是想推动这件事，请在 issue 里讨论，而不是先提 PR。

## 请不要做的事

- 不要提交 `build/`、`dist/`、`docs/icon/AppIcon.icns` 等产物（`.gitignore` 已覆盖）。
- **不要提交 Assets.xcassets 之外的图标变体，也不要手改 asset catalog**：图标由
  `make icon` 生成。
- **不要把个人标识写进代码或文档**（邮箱、主目录绝对路径、激活码）。特别是：任何从
  `~/Library/Application Support/com.yingdev.wgestures/` 拷数据的步骤，**只允许拷版本子目录**
  （如 `2.3.3/`），绝不能拷含 `license.json` 的上一级；拷完立刻扫一遍。
- 不要为了「顺手」改掉按手势禁用 `Enabled` 扩展字段的现有行为 —— 原版格式要求「只在禁用时才写出
  这个键」，`ConfigTests` 有逐键往返相等的守卫，改了会立刻失败。
- 不要改 `LegacyConfigImporter` / `ConfigStore` 现有的旧路径行为。
