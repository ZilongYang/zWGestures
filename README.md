# zWGestures

[![CI](https://github.com/ZilongYang/zWGestures/actions/workflows/ci.yml/badge.svg)](https://github.com/ZilongYang/zWGestures/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20Apple%20silicon-blue)

**原生的 Apple Silicon 鼠标手势工具。** 按住鼠标右键画一个形状，就执行你为它配置的动作。

用 Swift 从头写成，不依赖 Rosetta；兼容 [WGestures 2](https://www.yingdev.com/projects/wgestures2)
的配置文件格式，可以直接导入你已有的手势（见[为什么会有 zWGestures](#为什么会有-zwgestures)）。

> **想直接下载使用？** 见 [`docs/INSTALL.md`](docs/INSTALL.md) —— 没签名的应用首次打开需要放行一次，
> 那里写清了每一步、系统给出的原文，以及这些结论是怎么实测出来的。

![按住右键画一个手势：轨迹与手势名实时显示，一旦识别出来立刻变绿](site/assets/shot-overlay.png)

<details>
<summary><b>界面截图</b>（设置界面 / 菜单栏）</summary>

![设置界面：手势集、手势列表与搜索](site/assets/shot-settings.png)

![菜单栏](site/assets/shot-menu.png)

> 两条说明：轨迹那张的深色背景是**衬底**，轨迹与手势名本身是实时截取的
> （见 [`docs/ROADMAP.md`](docs/ROADMAP.md) §18）；截图用的是随 App 发布的**出厂默认手势**，
> 也就是你下载后真正看到的那一份，不是你本机配置的样子。

</details>

## 功能特性

- **右键手势，形状随意。** 不只是上下左右 —— 任意折线、圆圈、L 形都能识别，靠形状归一化距离匹配。
- **一条手势 = 笔画 + 动作。** 动作可以是按键序列（含录制的组合键与多步序列）、系统功能键、
  Web 搜索地址或 Shell 脚本，也可以勾选「识别后立即执行」。
- **按应用分手势集，并且有继承。** 应用自己的手势优先，没定义的继续用全局的 —— 给某个应用只加
  一条手势，不会让那个应用里的拷贝粘贴失效。不想要继承也可以整组关掉。
- **每条手势可以单独启用/禁用。** 保留在列表里、形状和命令都不变，只是画它没反应；整行变淡以示区别。
  这是本项目对原版格式的扩展（原版只能按触发方式启停，无法禁用单条手势）。
- **轨迹与手势名实时可视化。** 画的过程中就显示轨迹，一旦识别出来立刻变绿并显示手势名，松手后淡出。
- **形状冲突会提示，优先级由列表顺序决定。** 相同形状靠手势修饰键区分是合法的（`拷贝` 与 `剪切`
  都是向上，后者多按一个左键），这种不会被误报。真冲突会标橙，拖拽或右键菜单即可调顺序。
- **界面里能改一切，保存前自动备份。** 浏览/搜索/改名/删除/重画形状/改动作/排队/禁用，都不用再手改
  JSON；每次覆盖 `config.json` / `prefs.json` 之前，旧版本会存进 `Backups/`（各留最近 10 份）。
- **兼容 WGestures 配置，一键导入。** 首次启动自动导入，也可以随时从菜单栏手动重新导入；
  **原版目录只读，绝不改写**。

## 环境要求

- **Apple Silicon（arm64）** —— 工程的 `ARCHS` 就是 `arm64`，Intel 机器构建不了 App
- macOS 14 Sonoma 或更高（开发机为 macOS 27 + Xcode 26.6）
- Xcode 26.x
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## 快速开始

```bash
git clone https://github.com/ZilongYang/zWGestures.git
cd zWGestures

make bootstrap  # 首次克隆后跑一次：创建本机自签名证书（见下方「签名」）
make build      # xcodegen generate + xcodebuild，产物在 build/Build/Products/Debug/zWGestures.app
make run        # 先退出已运行的实例，再构建并启动
make test       # ZWGCore 单元测试（244 项；其中 1 项读本机原版安装，没装时会被明确跳过）
make install    # 构建并把 .app 拷到 /Applications（开机自启需要固定路径）
make clean
```

`make bootstrap` 不能省。工程用一把**本机自签名证书**签名，没有它 `make build` 会直接失败；
而这把证书又是「辅助功能授权在重新编译之后依然有效」的前提。

启动后需要在**系统设置 › 隐私与安全性 › 辅助功能**里勾选 zWGestures ——
没有这个权限，全局事件拦截器和合成按键都无法工作。菜单栏图标 →「辅助功能权限」可以直接跳转过去。

> ⚠️ **`make run` 会先退出正在运行的实例，这一步不能省。** `open` 对一个**已在运行**的 App
> 只做前台激活、**不会**启动新构建的二进制；macOS 上覆盖二进制文件也不影响已运行的进程。
> 所以「改了代码 → 直接 `open` → 没变化」几乎总是这个原因，而不是改动没生效。
> 设置窗口标题里带 `构建 MM-dd HH:mm:ss`，用它确认进程到底是哪次编译。

<details>
<summary><b>签名与构建细节</b>（为什么需要一把本机自签名证书）</summary>

zWGestures 用一把本机自签名证书 `zWGestures Local Signing` 签名，由
`scripts/create-signing-cert.sh` 创建并放进**独立钥匙串**
`~/Library/Keychains/zWGestures.keychain-db`（密码 `zwgestures`）。这样它的
**指定代码要求（designated requirement）** 是稳定的：

```
designated => identifier "io.github.zilongyang.zwgestures" and certificate root = H"85d71af4…"
```

因此「辅助功能」授权在重新编译之后依然有效。ad-hoc 签名（`codesign -s -`）的要求基于 CDHash，
每次编译都会变，会导致每次构建后都要重新授权。

之所以用独立钥匙串而不是登录钥匙串：登录钥匙串里的私钥需要 SecurityAgent 弹窗授权，在 `xcodebuild`
这种无人值守进程里弹窗不会被应答，签名会随机失败并报 `errSecInternalComponent`。独立钥匙串的密码
由构建脚本掌握，配合 key partition list 就可以免弹窗签名。`make build` 会先自动解锁该钥匙串
（`unlock-signing` 目标）；如果钥匙串被删除，构建仍会继续，只是签名会失败，重新运行
`scripts/create-signing-cert.sh` 即可。

`make info` 打印产物的架构与代码签名，用来确认这三件事。

</details>

## 工程结构

```
zWGestures/             App target（生命周期、菜单栏、UI、资源）
  App/                  启动、菜单栏、配置装载、开机自启（LoginItem）
  Input/                EventTap、手势状态机、急停
  Action/               命令执行（按键 / Shell / Web 搜索）
  Overlay/              轨迹与手势名可视化
  Target/               前台应用探测与目标解析
  UI/                   调试面板
ZWGCore/                SwiftPM 包：可测试的核心逻辑
  Sources/ZWGCore/      Config（模型/编解码/导入）、Recog（识别）、
                        Input（引擎）、Action（命令规划）、Target、Overlay
  Tests/ZWGCoreTests/   单元测试（用 `swift test` 运行）
project.yml             XcodeGen 工程定义（zWGestures.xcodeproj 由它生成）
```

### 为什么核心逻辑放在 SwiftPM 包里

`ZWGCore` 的源码既被 `swift test` 独立编译测试，也被 Xcode 的 App target 直接编译
（见 `project.yml` 里的第二条 `sources`），而不是作为 package product 链接。原因有两个：

1. Xcode 26 无法解析 XcodeGen 生成的工程中对本地包的引用（报 `Missing package product 'ZWGCore'`）。
2. 纯逻辑的单元测试不应该需要启动 App 宿主进程。

`swift test` 在受限 shell 中需要额外的参数，已封装在 `Makefile` 的 `test` 目标里。

## 配置与迁移

zWGestures 把自己的配置放在 `~/Library/Application Support/zWGestures/`：

```
config.json    手势配置，与原版 gestures.json 格式完全一致
prefs.json     偏好项，与原版 prefs.json 格式完全一致
```

首次启动时，如果还没有 `config.json`，会自动从原版目录
`~/Library/Application Support/com.yingdev.wgestures/<版本>/` 迁移一次，并在弹窗里报告迁移了哪些
内容。**原版目录只读，绝不改写**；菜单栏里可以随时重新导入。

格式兼容性有回归测试兜底：测试会读取仓库里提交的**参考配置 fixture**（原版 WGestures 2.3.3 的一份
脱敏样本），重新编码后要求 JSON **逐键完全相等**。这条测试已经抓出过两个真实缺陷 —— 偏好键名写成了
`LabelExecuted`（正确是 `LabelColorExecuted`），以及 `SkipVersion: null` 被 `encodeIfPresent` 整条省略。

### 没装过 WGestures 的人拿到的是什么

**开箱就有 48 条中文手势**，取自原版自己的出厂手势集，名字用的是原版自带的中文译名表：

| 手势集 | 条数 |
|---|---|
| 全局 | 45 |
| Finder | 3 |

常用的都在里面：画「上」是拷贝、画「下」是粘贴、向左后退、向右前进、`L` 形关闭窗口、
`C` 形切换 App……可以直接用，也可以在设置里随便改。

这份默认包是**原版的配置数据**（`gestures.json` + `prefs.json` + 它自带的中文译名表），不含原版的
任何二进制、字体、图标或激活码。它是**随仓库提交的生成物**，用 `make default-gestures` 从本机安装的
原版重新生成；**不挂进 `make build`**，因为没有原版的机器生成不出来。出处在
[`docs/ROADMAP.md`](docs/ROADMAP.md) §16。

首启的顺序是：**已有的配置 → 原版的安装 → 内置默认**。所以装过原版的人看到的是自己已有的手势，
而不是默认包。

## 为什么会有 zWGestures

WGestures 2 是一款出色的鼠标手势工具。它的「手势＝操作步骤之和」「手势修饰键」「继承与重载」等设计
是 zWGestures 的直接灵感来源；zWGestures 也刻意保持了与它配置文件格式的兼容，好让你已有的手势能
直接搬过来。

原版 macOS 版最后一个版本是 2021 年 12 月的 2.3.3。它是基于 Mono / Xamarin.Mac 的 x86_64 应用，
在 Apple 芯片 Mac 上依赖 Rosetta 运行。而 Apple 已宣布：
[macOS 26.4 起](https://developer.apple.com/news/?id=w5ngl9k2)，启动依赖 Rosetta 的应用会收到系统
提示；**macOS 27 是最后一个支持 Rosetta 的版本**，之后 Intel-only 应用在 Apple 芯片 Mac 上将不再能
运行（少数老游戏除外）。

为了让这套用了多年的鼠标手势能继续在新系统上用下去，我用 Swift 从头写了一个原生版本。它是
**独立的重新实现，不是官方版本，与原项目及作者 yingdev（Ying Yuandong）没有隶属关系**，
不包含原版的任何二进制、字体、图标或激活码。

如果你还在用原版并且觉得它好用，请去
[yingdev.com/projects/wgestures2](https://www.yingdev.com/projects/wgestures2) 支持原作者。

## 已知限制

- **界面中英双语。** 设置里可切换或跟随系统；日志与调试面板仍只有中文。
- **仅支持 Apple Silicon。** 不做 Intel / Universal 支持，`ARCHS=arm64` 保持不变。
- **未做 Developer ID 签名与公证**，首次打开需要按 [`docs/INSTALL.md`](docs/INSTALL.md) 放行一次；
  而且**每更新一版都要重新授权一次辅助功能**。
- **触发矩阵编辑、边角与滚轮触发尚未实现。** 这类手势在列表里默认隐藏。
- **手势分组、动画回放尚未实现。**

## 开发约定

三条**必须遵守**的规则。前两条来自已经发生过的崩溃，第三条来自已经发生过的整机输入冻结 ——
都不是理论风险。

**① AppKit 覆写不要带 actor 隔离。** `NSView`/`NSWindow` 在本 SDK 上是 `@MainActor`，覆写它们的成员
会继承隔离，Swift 便会在入口插入主 actor 运行时检查；而 AppKit 的**跟踪区域 / 命中测试**路径会在那个
检查上崩（崩溃报告 `zWGestures-2026-09-28-211050.ips`）。纯几何/谓词覆写（`isFlipped`、`hitTest`、
`acceptsFirstResponder`、`canBecomeKeyView`、`canBecomeKey`、`canBecomeMain`、`menu(for:)`）一律写
`nonisolated`。`make test` 会先跑 `scripts/check-appkit-isolation.py` 拦下漏标的；单独跑用 `make lint`。

**② 不要在 `Timer` 的 block 里碰 actor 隔离的状态。** `Timer.scheduledTimer` 的 block 是 `@Sendable`
闭包，从里面访问 `@MainActor` 的状态会迫使编译器插入 `MainActor.assumeIsolated`。这个运行时断言在本
工程的 debug dylib 布局下**直接崩掉**（SIGBUS，栈顶落在 `SerialExecutor.isMainExecutor`）。需要周期性
刷新时用 `Task` 循环：

```swift
refreshTask = Task { @MainActor [weak self] in
    while !Task.isCancelled {
        guard let self else { return }
        self.refresh()
        try? await Task.sleep(for: .milliseconds(100))
    }
}
```

**③ 事件拦截器绝不捕获键盘事件。** 事件 tap 的回调是**同步**的：系统必须等回调返回才投递该事件。
鼠标移动可以被窗口服务器合并，回调慢只会让轨迹变粗；**键盘事件无法合并**，所以只要把 `.keyDown` 放进
掩码，回调一旦错过系统的截止时间，打字就会整机失效。这条规则有自己的单元测试（`EventTapMaskTests`）
守着。另外：超时后必须**退避**再启用，并在一段窗口内超时过多时**主动拆除**，而不是无限重新启用 ——
相关策略在 `ZWGCore` 的 `EventTapHealthPolicy` 里，也有单测。经过与完整证据见
[`docs/ROADMAP.md`](docs/ROADMAP.md) §13。

崩溃报告在 `~/Library/Logs/DiagnosticReports/zWGestures-*.ips`，是 `.ips` 格式（首行是一条 JSON 头，
第二行才是正文），可以直接用 Python 解析出 `exception`、崩溃线程和调用栈。

<details>
<summary><b>开机自启的实现细节</b>（<code>SMAppService</code> + LaunchAgent 兜底）</summary>

菜单栏图标 →「开机自动启动」（`zWGestures/App/LoginItem.swift`，用 `SMAppService.mainApp` 注册登录项，
不需要额外 entitlement）。

几点值得记住：

- **状态以系统为准。** 菜单每次都读 `SMAppService.mainApp.status`，因为用户可以在
  「系统设置 → 通用 → 登录项」里绕过应用把开关关掉；`prefs.json` 的 `AutoStart` 只在注册成功后回写。
  应用**不会**在启动时擅自注册（原版偏好默认是 `true`，但那是导入来的意图，不等于要写进系统）。
- **登录项记录的是应用路径。** 从 `build/Build/Products/Debug` 里注册也能成功，但 `make clean` 或移动
  应用之后登录项就失效了。所以要用 `make install` 把应用放到 `/Applications/zWGestures.app` 这个固定
  路径，再从那里注册。
- **本机自签名、无 Team ID，但 `SMAppService` 确实能注册**：一度从 `/Applications` 启动时报
  `.notFound`、`sfltool dumpbtm` 里毫无记录，改用**原地覆盖**方式重装（`make install` 不再 `rm -rf`）
  并重新启动后就注册成功了（底账里出现 `Disposition: [enabled, allowed, notified]`）。
  为了不让「注册失败就彻底没有开机自启」，开关仍然**先试系统登录项，失败才写
  `~/Library/LaunchAgents/io.github.zilongyang.zwgestures.plist`**（`RunAtLoad` + `open -a`），关闭时
  两处都清；菜单标题会写出实际生效的是哪一个。细节与归因上的保留见
  [`docs/ROADMAP.md`](docs/ROADMAP.md) §10。
- 如果系统提示需要确认（`requiresApproval`），菜单会显示「等待系统设置里确认」，点一下会直接打开登录项
  面板。
- **重新导入配置不会覆盖登录项状态。** 原版的 `AutoStart` 只是原版的意图，导入时若它与系统实际状态
  不一致，以系统为准。

</details>

<details>
<summary><b>应用图标是怎么生成的</b></summary>

图标由脚本生成，不手工维护。产出是 **asset catalog**（`Assets.xcassets/AppIcon.appiconset`）——
macOS 26+ 的 AppKit 只认它（老的 `CFBundleIconFile` + 独立 `.icns` 会让「关于」面板空白，Finder 却
正常，因为两者走不同的路）。

```bash
make icon                    # 默认折线「下→右」（配置里真实存在的 Close 手势）
make icon VARIANT=swoosh     # 换成斜向弧线（备选，见 docs/icon/alternative-swoosh.png）
```

`scripts/make-app-icon.swift` 用 CoreGraphics 按 macOS 图标网格（1024 画布上 824×824、圆角 185）画出底
与轨迹，再用 `iconutil` 打包成 .icns；1024 的母版图落在 `docs/icon/` 供评审。轨迹用的是「已识别」轨迹色
`#20D697`（与 `prefs.json` 的 `PathColorRecognized` 一致），形状取自配置里真实存在的手势。

</details>

## 贡献

欢迎 issue 与 PR。动手之前请先读 [`CONTRIBUTING.md`](CONTRIBUTING.md) —— 里面有构建方式、
提交前清单，以及上面那三条必须遵守的约定。

提交前至少跑一遍：

```bash
make lint && make test
```

## 文档

| 文件 | 内容 |
|---|---|
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | **计划与进度**，接手开发从这里开始读 |
| [`docs/PLAN-2026-10-06.md`](docs/PLAN-2026-10-06.md) | 2026-10-06 批准的那份实施方案**原样存档**（识别结构度量 + 慢半拍），文末附「与计划的差异」 |
| [`docs/PLAN-2026-10-06-i18n.md`](docs/PLAN-2026-10-06-i18n.md) | 界面多语言（中/英）+ 手势名中文化的批准方案**原样存档**，分四期实施 |
| [`docs/RELEASE-CHECKLIST-0.2.0.md`](docs/RELEASE-CHECKLIST-0.2.0.md) | 0.2.0 发版的打勾清单：发版前回归测试 + 发版步骤（做完即归档） |
| [`docs/RELEASE-CHECKLIST-0.3.0.md`](docs/RELEASE-CHECKLIST-0.3.0.md) | 0.3.0 发版的打勾清单：双语/改名回归 + 发版步骤（做完即归档） |
| [`docs/INSTALL.md`](docs/INSTALL.md) | **安装说明**：Gatekeeper 放行、授权辅助功能、卸载、常见问题 |
| [`CHANGELOG.md`](CHANGELOG.md) | 每个版本值得用户知道的变化 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | 构建方式、提交前清单、必须遵守的约定 |
| [`docs/PLAN.md`](docs/PLAN.md) | 2026-09-28 批准的那份实施方案**原样存档**（只作历史参考，不再更新） |
| [`docs/OPEN-SOURCE-PLAN.md`](docs/OPEN-SOURCE-PLAN.md) | 2026-09-29 批准的开源 + 发布计划**原样存档**（只作历史参考，不再更新） |
| `README.md` | 本文件：构建命令、工程结构、开发约定 |

## 许可证与商标

以 [MIT 许可证](LICENSE) 发布，版权归 © 2026 Zilong Yang。

zWGestures 是**独立的重新实现，不是官方版本**，与 WGestures / WGestures 2 及其作者 yingdev
（Ying Yuandong）没有任何隶属关系，也未获其背书。项目不包含原版的任何二进制、字体、图标或激活码；
兼容性仅限于**配置文件格式**，目的是让用户能导入自己已有的手势。

「WGestures」及相关名称归其各自所有者。
