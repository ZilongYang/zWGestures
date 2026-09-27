# zWGestures 路线图与接手说明

> **明天继续开发，从这里开始读。** 本文件是唯一的计划与进度来源；
> `README.md` 里是构建命令与开发约定。
> 最初批准的那份实施方案原样存档在 [`PLAN.md`](PLAN.md)（只作历史参考，不再更新）。

## 1. 目标

在 Apple Silicon 上原生复刻 **WGestures 2.3.3 (macOS)** 的可感知功能，不依赖 Rosetta，
并能直接导入已有的手势配置，做到日常无感替换。

原版是 Mono / Xamarin.Mac 的 x86_64 应用，只能在 Rosetta 下运行；下一版 macOS 将移除
Rosetta。

## 2. 已完成（截至本轮结束）

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 工程骨架：git、XcodeGen、Info.plist、菜单栏 App、arm64 验证 | ✅ |
| P0b | 稳定的本机自签名证书（独立钥匙串，免弹窗签名） | ✅ |
| P1 | 输入引擎：EventTap 生命周期、抑制/回放、起始超时、禁用自恢复、急停快捷键 | ✅ 已实机验证 |
| P2 | 配置层：完整 `Codable` 模型、原版配置导入、偏好项 | ✅ 导入与原文件逐键一致 |
| P3 | 识别层：形状归一化匹配、序列匹配、手势修饰键消歧 | ✅ 已实机验证 |
| P4a | 命令执行：按键序列 / 系统功能键 / Shell / Web 搜索 | ✅ |
| P4b | 目标解析：按应用选择手势集（替换语义） | ✅ 已实机验证 |
| P5a | 触发矩阵：启用/禁用与继承 | ✅ |
| P5b | 轨迹可视化：实时轨迹 + 实时手势名 + 识别即变绿 | ✅ 已实机验证 |

**可以日常使用的程度**：右键基本手势全部工作 —— 识别、执行命令、轨迹与手势名实时显示、
命中变绿淡出、未识别不弹菜单、按应用切换手势集、急停快捷键。

## 3. 下一步（按建议优先级）

1. **开机自启**（小，半小时）
   偏好里 `AutoStart: true`，需要 `SMAppService.mainApp.register()`；菜单栏加一个开关项。
2. **P6 设置界面（简版）**（大，这是当前最大的缺口）
   目前改任何手势都必须手改 JSON，无法日常维护。建议顺序：
   目标列表 → 手势列表（含方向缩略图）→ 触发方式矩阵 → 命令编辑器。
   手势方向可以用 `WGStrokeStep.directionDescription` 直接渲染成文字（如 `下→右`）。
3. **P7 验收与加固**：多屏、全屏应用、长时间运行、连续快速手势。
4. **P5 剩余：边角/角落检测 + 滚轮触发**（用户明确暂缓，可随时捡起）
   触发矩阵已经就绪，所以危险手势（睡眠/关机）不会因为做了边角检测而被误触发。
5. P8：完整可视化编辑器、分组、拖放排序、拼音搜索、动画回放。

## 4. 常用命令

```bash
cd /Users/zilong/zWork/ai/zWGestures

make build      # xcodegen generate + xcodebuild（会自动解锁签名钥匙串）
make test       # 运行 ZWGCore 的单元测试（104 项）
make run        # 构建并启动
make run-debug  # 构建并启动，同时打开调试面板（ZWG_DEBUG_HUD=1）
make info       # 打印产物的架构与代码签名
make clean
```

**改完代码后务必 `make test`**，测试里有多条针对真实配置的强回归断言。

## 5. 关键决策（已与用户确认，不要擅自推翻）

| 决策 | 内容 |
|---|---|
| 技术栈 | Swift 6 + AppKit 为主 / SwiftUI 留待设置界面；零第三方依赖 |
| 最低系统 | macOS 14，仅 arm64 |
| 签名 | 本机自签名证书 `zWGestures Local Signing`，放在独立钥匙串 `zWGestures.keychain-db`（密码 `zwgestures`），由 `make build` 自动解锁 |
| 应用目标语义 | 应用目标**替换**全局手势，不叠加（用户从原版 UI 确认：Finder 目标只有 3 条） |
| 未识别的手势 | **不回放**给系统 —— 位移超过阈值就说明用户在画手势，不该弹出右键菜单 |
| 普通点击 | 没移动、或停住超过起始超时（250ms）时，引擎补发 down+up，右键菜单照常 |
| 屏幕边缘手势 | **暂缓**（用户决定）：边角/角落检测与滚轮触发先不做 |
| 界面语言 | 中文为主 |

## 6. 原版数据模型（已勘察确认）

配置目录：`~/Library/Application Support/com.yingdev.wgestures/<版本>/`
（`gestures.json` + `prefs.json`）。**只读，绝不改写。**

```
{ "General": Target, "Groups": [Target], "Apps": [Target], "Specials": [Target] }
Target  = { Id, Name, Intents: [Intent], Triggers: [{ Def: [Step], Enabled: Bool }] }
Intent  = { Name, ExecuteOnRecognize, Gesture: [Step], Command: Command }
Step    = KeyDownStep{Key} | StrokeStep{IsSimple, P} | MoveToEdgeCornerStep{EdgeCorner:{Value}} | ScrollStep{IsHorizontal}
Key     = "MOUSE:0..2"（0=左 1=右 2=中）| "VSCROLL:±n"
Command = KeySeqCommand{IsSystemHotKey, Keys} | WebSearchCommand{SearchEngine}
        | ShellScriptCommand{Script} | SystemFunctionKeyCommand{SelectedIndex}
```

### 轨迹编码（已用原版快捷入门图与命令语义交叉验证）

- `IsSimple = true`：`P` **就是绘制顺序**，第一对点即笔画起点（原版 UI 在该点画触发符号）。
  网格单位 50，**y 轴向上为正**，转屏幕坐标要取反 y。
- `IsSimple = false`：`P` 是**原始屏幕坐标**点列（y 全为正），不倒序也不翻转。

> ⚠️ 这里踩过一次大坑。最初把 `P` 读成**倒序**、把 y 读成**向下为正**。
> 两个错误对纯竖直笔画（`拷贝`↑ / `粘贴`↓）恰好互相抵消，所以看起来是对的，
> 而所有横向与折线手势都被静默算成镜像或旋转版本。
>
> 抓住它的是两条独立证据：
> 1. **命令语义**：`Back` 绑定 ⌘[，画出来必须是**向左**；错误规则给出的是向右。
> 2. **原版快捷入门图**（放大核对）：「拷贝」的起笔圆圈在箭头**下方**；
>    「关闭标签页」= 下→右；「退出」= 下→左；「新建标签页」= 右→下。
>
> 已固化为 `StrokeDirectionTests.swift`：用真实配置里的 `P` 原值直接断言方向语义。

### 边角位掩码：`Top=1 Right=2 Bottom=4 Left=8`

依据原版快捷入门图：音量卡片（EDGE1）在监视器顶部画黑条；亮度卡片（EDGE4）在底部；
切换任务卡片（EDGE9）的角括号在屏幕左上角。已固化为
`ConfigTests.edgeMaskMatchesTheOriginalArtwork`。

### 配色格式：`#RRGGBBAA`

依据：两个「常态」颜色前六位都是**纯灰**（`7F7F7F` / `606060`），
按 `AARRGGBB` 解析要连续两次巧合；且识别色 `20D697` 出来是**青绿色**，与用户截图一致。

### 触发矩阵的粒度

矩阵行里的滚动是 `ScrollStep`（**不带方向**），手势定义里是 `VSCROLL:-11`（带方向）。
所以**方向 0 是通配符** —— 矩阵只区分「边角 + 滚轮」，区分 音量+ / 音量− 的是手势定义。
矩阵未列出的触发方式**不禁用**（保守选择）。

### 系统功能键

`SelectedIndex` 0..7 = 亮度−、亮度+、上一曲、播放/暂停、下一曲、静音、音量−、音量+
（映射到 `NX_KEYTYPE_*`）。

### 脚本环境变量

`WG_TARGET_PID`、`WG_TARGET_EXE`、`WG_TARGET_BUNDLE`、`WG_TARGET_WID`、
`WG_TARGET_APP_NAME`、`WG_TARGET_WIN_NAME`、`WG_MOUSE_X`、`WG_MOUSE_Y`、`WG_MOUSE_Y_FLIP`。

## 7. 仍未验证的细节

这些无法从配置文件推断，需要实机实验或与原版对照：

1. **后缀修饰步骤的按压时机** —— `剪切=[右↑, 左键]` 里的左键，是必须在画线**前**按住、
   画线**中**按住、还是画完仍按住再按？目前实现为「画完之后按也行」。
2. **`VSCROLL:n` 的量级分档**（原版存了 1/11/12/13 等原始值，说明匹配时是分档而非精确比较）。
   目前未实现滚轮触发，所以暂不影响。
3. **`CGEventTap` 是否还需要「输入监控」权限**（除辅助功能之外）。目前只申请了辅助功能，
   实测可用。
4. **左键触发「不阻止点击」的确切条件**（原版 2.5.0 起的行为）。
5. **跨屏手势的坐标归一与边界处理**（当前只在单屏上验证过）。
6. **分组（Groups）的格式** —— 现有配置里 `Groups` 为空，其 on-disk 结构未知，未实现。

## 8. 已知陷阱（踩过的，别重复）

- **不要在 `Timer` 的 block 里访问 actor 隔离状态**。`Timer` 的 block 是 `@Sendable` 闭包，
  会迫使编译器插入 `MainActor.assumeIsolated`，本工程里它**直接 SIGBUS 崩掉过整个 App**
  （崩溃报告 `zWGestures-2026-09-28-025040.ips`）。周期性刷新一律用 `Task` 循环。
- **签名必须用独立钥匙串**。登录钥匙串里的私钥要靠 SecurityAgent 弹窗授权，
  在无人值守的 `xcodebuild` 里会随机报 `errSecInternalComponent`。
- **`xcodebuild test` 在受限终端里会因伪终端失败**，所以单测放在 `ZWGCore` SwiftPM 包里，
  用 `swift test`（`make test` 已封装好所需参数）。
- **不要混用时间基**。`CGEvent.timestamp` 与 `mach_absolute_time()` 不同基
  （Apple Silicon 上差 125/3），相减会得到十几天的延时。事件时间戳统一用
  `MonotonicClock`（`ProcessInfo.systemUptime`），超时一律用相对延迟。
- **锁方向必须单向**。`overlayLock` 可以再取 `recognitionLock`，反之不行 ——
  实时手势名必须在取 `overlayLock` 之前算完。
- **手写测试 fixture 容易写反方向**。用真实配置里的 `P` 原值，或按真实编码规则生成。

## 9. 验证方式

- 单元测试：`make test`（104 项），其中多条**针对用户真实配置**的强回归断言。
- 实机验证：用户用右键画手势，读调试面板（`make run-debug`）的
  `state` / `gesture` / `target` / `executed` 四行，并观察屏幕上的轨迹与手势名。
- 崩溃报告在 `~/Library/Logs/DiagnosticReports/zWGestures-*.ips`
  （`.ips` 首行是 JSON 头、第二行才是正文，可用 Python 解析）。

## 10. 明确的边界

- 不复制、不打包原版任何二进制、字体、图标、资源或激活码；只做配置格式互通。
- 不复刻 Windows 版特有功能：自定义菜单、Lua、Cmd 脚本、运行/激活应用程序。
- 不做 App Store 上架（沙箱与全局输入拦截互斥）。
