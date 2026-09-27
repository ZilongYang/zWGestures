# zWGestures

原生的 Apple Silicon 鼠标手势工具，复刻 [WGestures 2](https://www.yingdev.com/projects/wgestures2)
(macOS 2.3.3) 的功能。原版是基于 Mono / Xamarin.Mac 的 x86_64 应用，只能在 Rosetta 下运行。

## 当前状态

**P0（工程骨架）已完成**：菜单栏 App 可编译、可启动、纯 arm64、可被授予辅助功能权限。

后续阶段见 `docs/ROADMAP.md`。

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
make run     # 构建并启动
make test    # 运行 ZWGCore 的单元测试
make clean
```

## 工程结构

```
zWGestures/             App target（生命周期、菜单栏、UI、资源）
ZWGCore/                SwiftPM 包：可测试的核心逻辑
  Sources/ZWGCore/      Log、PermissionGate、BuildInfo，后续的手势引擎
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

## 权限

zWGestures 需要「辅助功能」权限才能安装全局事件拦截器和发送合成按键事件。
首次运行时在菜单栏图标 →「辅助功能权限」里点击前往系统设置授权。

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
