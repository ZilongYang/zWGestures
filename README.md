# zWGestures

原生的 Apple Silicon 鼠标手势工具，复刻 [WGestures 2](https://www.yingdev.com/projects/wgestures2)
(macOS 2.3.3) 的功能。原版是基于 Mono / Xamarin.Mac 的 x86_64 应用，只能在 Rosetta 下运行。

## 当前状态

右键基本手势已经可以日常使用：识别、执行命令、轨迹与手势名实时显示、命中变绿、
按应用切换手势集（应用手势集叠加在全局之上）、急停快捷键、**开机自动启动**（已重启验证）。

**设置界面**：菜单栏「打开设置…」（⌘,）可以浏览每个手势集的手势、按名称/方向/命令搜索、
重命名或删除。

一条手势 = **笔画 + 它触发的动作**，所以双击一条手势（或右键 →「编辑手势…」）打开的是：
**1. 手势形状**（两栏：左边是现在的手势，右边点击后**在全屏幕上画一个新手势**，画完立刻
显示在右栏；「重画」重新录，「不改了」保留原形状）→ **2. 名称** → **3. 动作**
（按键序列（可录制组合键与多步序列）/ Web 搜索地址 / Shell 脚本 / 系统功能键），
外加「识别手势后立即执行」。列表头部的「+ 新建手势」用同一套流程新增一条。

窗口顶部可以切到**偏好设置**：手势起始超时、按哪个窗口选手势集、轨迹与手势名的显示开关、
四个颜色、线宽、手势名位置 —— 改完点「保存」立刻生效（以前这些只能手改 `prefs.json`）。

**保存前会自动备份**：每次覆盖 `config.json` / `prefs.json` 之前，旧版本都会存进
`~/Library/Application Support/zWGestures/Backups/`（各留最近 10 份）。底部状态栏的文件夹按钮
可以打开配置目录。

左栏底部可以**新增应用手势集**：从正在运行的应用里选，或直接选一个 `.app` 文件；右键左侧的
手势集（或用「−」按钮）可以整体移除。新目标一开始是空的，用「+ 新建手势」往里加。

应用手势集默认**叠加**在全局之上：**应用自己的手势优先，没定义的继续用全局的** ——
所以给某个应用只加一条手势，不会让那个应用里的拷贝粘贴失效。列表里继承来的手势会变淡并标注
「继承自全局」，它们是只读的（双击跳到全局去改）。不想叠加时，可以在列表上方**取消勾选
「继承全局手势」**，那个应用就只用自己这几条。

⚠️ 同一个应用**只能有一个**目标，有重复的话第二个永远不会生效，所以新增时会直接拒绝并指出
已有的那一个。全局手势集不能移除（它是一切的后备）。

每条手势左边的复选框可以**单独禁用**它：禁用后手势保留在列表里（形状、命令、位置都不变），
只是画那个形状不会有任何反应 —— 想临时停用而不想删掉时用它。整行会变淡以示区别。

就是说：**换一个手势来触发同一个动作**，现在不用再手改 JSON。改动点「保存」后写入
`config.json` 并立刻生效。

两条手势形状相同时（且触发键、手势修饰键都一样）只有一条能生效，**由列表顺序决定：
靠前的优先**。**直接拖动列表里的行**就能改变优先级（行首有拖拽手柄；搜索框为空时可用）。
手势多的时候拖拽不便，右键菜单提供「上移 / 下移 / 移到最前 / 移到最后」四个入口。编辑器会提示与哪一条相同，列表里这类重复会显示橙色 ⚠️。注意**形状相同本身是合法的** —— 靠手势修饰键区分
（例如 `Copy` 与 `Cut` 都是向上，`Cut` 多按一个左键），这种不会被误报。

> 这里刻意偏离了原版的「靠后的优先」：顺序是可见、可调的，比「文件里最后一条赢」好理解。
> 触发矩阵编辑尚未实现。

后续阶段见 [`docs/ROADMAP.md`](docs/ROADMAP.md)。

## 文档

| 文件 | 内容 |
|---|---|
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | **计划与进度**，接手开发从这里开始读 |
| [`docs/PLAN.md`](docs/PLAN.md) | 2026-09-28 批准的那份实施方案**原样存档**（只作历史参考，不再更新） |
| `README.md` | 本文件：构建命令、工程结构、开发约定 |

## 环境要求

- macOS 14 Sonoma 或更高（开发机为 macOS 27 + Xcode 26.6）
- Xcode 26.x
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## 构建与运行

```bash
make build   # xcodegen generate + xcodebuild，产物在 build/Build/Products/Debug/zWGestures.app
make run     # 先退出已运行的实例，再构建并启动
make test    # 运行 ZWGCore 的单元测试（223 项）
make install # 构建并把 .app 拷到 /Applications（开机自启需要固定路径）
make clean
```

> ⚠️ **`make run` 会先退出正在运行的实例，这一步不能省。** `open` 对一个**已在运行**的 App
> 只做前台激活、**不会**启动新构建的二进制；macOS 上覆盖二进制文件也不影响已运行的进程。
> 所以「改了代码 → 直接 `open` → 没变化」几乎总是这个原因，而不是改动没生效。
> 设置窗口标题里带 `构建 MM-dd HH:mm:ss`，用它确认进程到底是哪次编译。

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

1. Xcode 26 无法解析 XcodeGen 生成的工程中对本地包的引用（报
   `Missing package product 'ZWGCore'`）。
2. 纯逻辑的单元测试不应该需要启动 App 宿主进程。

`swift test` 在受限 shell 中需要额外的参数，已封装在 `Makefile` 的 `test` 目标里。

## 配置与迁移

zWGestures 把自己的配置放在 `~/Library/Application Support/zWGestures/`：

```
config.json    手势配置，与原版 gestures.json 格式完全一致
prefs.json     偏好项，与原版 prefs.json 格式完全一致
```

首次启动时，如果还没有 `config.json`，会自动从原版目录
`~/Library/Application Support/com.yingdev.wgestures/<版本>/` 迁移一次，
并在弹窗里报告迁移了哪些内容。**原版目录只读，绝不改写**；菜单栏里可以随时重新导入。

格式兼容性有回归测试兜底：测试会读取真实配置文件，重新编码后要求 JSON **逐键完全相等**。
这条测试已经抓出过两个真实缺陷 —— 偏好键名写成了 `LabelExecuted`（正确是
`LabelColorExecuted`），以及 `SkipVersion: null` 被 `encodeIfPresent` 整条省略。

## 应用图标

`zWGestures/Resources/AppIcon.icns` 由脚本生成，不手工维护：

```bash
make icon                  # 默认斜向弧线（VARIANT=swoosh）
make icon VARIANT=corner   # 折线「下→右」（配置里真实存在的 Close 手势）
```

`scripts/make-app-icon.swift` 用 CoreGraphics 按 macOS 图标网格（1024 画布上 824×824、
圆角 185）画出底与轨迹，再用 `iconutil` 打包成 .icns；1024 的母版图落在 `docs/icon/`
供评审。轨迹用的是「已识别」轨迹色 `#20D697`（与 `prefs.json` 的 `PathColorRecognized` 一致），
形状取自用户配置里真实存在的手势。

## 权限

zWGestures 需要「辅助功能」权限才能安装全局事件拦截器和发送合成按键事件。
首次运行时在菜单栏图标 →「辅助功能权限」里点击前往系统设置授权。

## 开机自启

菜单栏图标 →「开机自动启动」（`zWGestures/App/LoginItem.swift`，用
`SMAppService.mainApp` 注册登录项，不需要额外 entitlement）。

几点值得记住：

- **状态以系统为准。** 菜单每次都读 `SMAppService.mainApp.status`，因为用户可以在
  「系统设置 → 通用 → 登录项」里绕过应用把开关关掉；`prefs.json` 的 `AutoStart`
  只在注册成功后回写。应用**不会**在启动时擅自注册（原版偏好默认是 `true`，
  但那是导入来的意图，不等于要写进系统）。
- **登录项记录的是应用路径。** 从 `build/Build/Products/Debug` 里注册也能成功，
  但 `make clean` 或移动应用之后登录项就失效了。所以要用 `make install` 把应用放到
  `/Applications/zWGestures.app` 这个固定路径，再从那里注册。
- **本机自签名、无 Team ID，但 `SMAppService` 确实能注册**：一度从 `/Applications` 启动时报
  `.notFound`、`sfltool dumpbtm` 里毫无记录，改用**原地覆盖**方式重装（`make install` 不再
  `rm -rf`）并重新启动后就注册成功了（底账里出现 `Disposition: [enabled, allowed, notified]`）。
  为了不让「注册失败就彻底没有开机自启」，开关仍然**先试系统登录项，失败才写
  `~/Library/LaunchAgents/com.zilong.zwgestures.plist`**（`RunAtLoad` + `open -a`），
  关闭时两处都清；菜单标题会写出实际生效的是哪一个。
  细节与归因上的保留见 [`docs/ROADMAP.md`](docs/ROADMAP.md) §10。
- 如果系统提示需要确认（`requiresApproval`），菜单会显示「等待系统设置里确认」，
  点一下会直接打开登录项面板。
- **重新导入配置不会覆盖登录项状态。** 原版的 `AutoStart` 只是原版的意图，导入时若
  它与系统实际状态不一致，以系统为准。

## 签名

zWGestures 用一把本机自签名证书 `zWGestures Local Signing` 签名，由
`scripts/create-signing-cert.sh` 创建并放进**独立钥匙串**
`~/Library/Keychains/zWGestures.keychain-db`（密码 `zwgestures`）。这样它的
**指定代码要求（designated requirement）** 是稳定的：

```
designated => identifier "com.zilong.zwgestures" and certificate root = H"85d71af4…"
```

因此「辅助功能」授权在重新编译之后依然有效。ad-hoc 签名（`codesign -s -`）的要求基于
CDHash，每次编译都会变，会导致每次构建后都要重新授权。

之所以用独立钥匙串而不是登录钥匙串：登录钥匙串里的私钥需要 SecurityAgent 弹窗授权，
在 `xcodebuild` 这种无人值守进程里弹窗不会被应答，签名会随机失败并报
`errSecInternalComponent`。独立钥匙串的密码由构建脚本掌握，配合 key partition list
就可以免弹窗签名。`make build` 会先自动解锁该钥匙串。

`make build` 里的 `unlock-signing` 目标负责解锁；如果钥匙串被删除，构建仍会继续，
只是签名会失败，此时重新运行 `scripts/create-signing-cert.sh` 即可。

## 开发约定

**AppKit 覆写不要带 actor 隔离。** `NSView`/`NSWindow` 在本 SDK 上是 `@MainActor`，
覆写它们的成员会继承隔离，Swift 便会在入口插入主 actor 运行时检查；而 AppKit 的
**跟踪区域 / 命中测试**路径会在那个检查上崩（崩溃报告 `zWGestures-2026-09-28-211050.ips`）。
纯几何/谓词覆写（`isFlipped`、`hitTest`、`acceptsFirstResponder`、`canBecomeKeyView`、
`canBecomeKey`、`canBecomeMain`、`menu(for:)`）一律写 `nonisolated`。
`make test` 会先跑 `scripts/check-appkit-isolation.py` 拦下漏标的；单独跑用 `make lint`。

**不要在 `Timer` 的 block 里碰 actor 隔离的状态。** `Timer.scheduledTimer` 的 block 是
`@Sendable` 闭包，从里面访问 `@MainActor` 的状态会迫使编译器插入
`MainActor.assumeIsolated`。这个运行时断言在本工程的 debug dylib 布局下**直接崩掉**
（SIGBUS，栈顶落在 `SerialExecutor.isMainExecutor`）。需要周期性刷新时用 `Task` 循环：

```swift
refreshTask = Task { @MainActor [weak self] in
    while !Task.isCancelled {
        guard let self else { return }
        self.refresh()
        try? await Task.sleep(for: .milliseconds(100))
    }
}
```

崩溃报告在 `~/Library/Logs/DiagnosticReports/zWGestures-*.ips`，是 `.ips` 格式（首行是
一条 JSON 头，第二行才是正文），可以直接用 Python 解析出 `exception`、崩溃线程和调用栈。

## 与 WGestures 的关系

本项目是独立的重新实现，不包含原版的任何二进制、字体、图标或激活码。
兼容性仅限于**配置文件格式**，以便导入已有的手势配置。
