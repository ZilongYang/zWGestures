# zWGestures

原生的 Apple Silicon 鼠标手势工具，复刻 [WGestures 2](https://www.yingdev.com/projects/wgestures2)
(macOS 2.3.3) 的功能。原版是基于 Mono / Xamarin.Mac 的 x86_64 应用，只能在 Rosetta 下运行。

## 当前状态

**P0（工程骨架）已完成**：菜单栏 App 可编译、可启动、纯 arm64、可被授予辅助功能权限。

后续阶段见 `docs/ROADMAP.md`。

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

## 权限

zWGestures 需要「辅助功能」权限才能安装全局事件拦截器和发送合成按键事件。
首次运行时在菜单栏图标 →「辅助功能权限」里点击前往系统设置授权。

## 签名

开发期使用 ad-hoc 签名。注意：**ad-hoc 签名的 CDHash 每次重新编译都会变化，
导致 macOS 每次都要求重新授权辅助功能**。P0b 会切换到一把稳定的本机证书。

## 与 WGestures 的关系

本项目是独立的重新实现，不包含原版的任何二进制、字体、图标或激活码。
兼容性仅限于**配置文件格式**，以便导入已有的手势配置。
