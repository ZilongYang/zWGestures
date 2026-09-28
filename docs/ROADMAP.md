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
| P4b | 目标解析：按应用选择手势集 | ✅ 已实机验证（语义已于 2026-09-28 由「替换」改为「叠加」，见 P6j） |
| P5a | 触发矩阵：启用/禁用与继承 | ✅ |
| P5b | 轨迹可视化：实时轨迹 + 实时手势名 + 识别即变绿 | ✅ 已实机验证 |
| P6a | 设置界面（第一阶段）：目标列表 + 手势列表（方向缩略图）+ 搜索 + 重命名/删除 + 显式保存 | ✅ 已实机验证 |
| P6b | 命令编辑器：按键序列（可录制）/ Web 搜索 / Shell 脚本 / 系统功能键 + 识别即执行 | ✅ 已实机验证（含组合键录制） |
| P6c | 手势编辑器：**画布重画笔画** + 名称 + 动作，以及**新建手势** | ✅ 已实机验证 |
| P6d | 形状冲突：检测 + **用列表顺序决定优先级** + 拖拽 / 右键（上移、下移、移到最前、移到最后） | ✅ 已实机验证（顺序生效：画向右已按列表顺序命中） |
| P6e | 编辑器改两栏：左栏现在的手势 / 右栏**全屏录制**新手势 + 重画 | ✅ 已实机验证 |
| P6f | **按手势启用/禁用**（本项目扩展字段 `Enabled`，禁用后保留但永不生效） | ✅ 已实机验证（配置里 General 有 2 条、Brave 有 1 条处于禁用） |
| P6g | **保存前自动备份**（`Backups/<label>-时间戳.json`，各留最近 10 份）+ 打开配置文件夹 | ✅ 已实机验证（Backups/ 里已有 15 个真实备份：11 config + 4 prefs） |
| P6h | **偏好设置界面**：起始超时、目标模式、轨迹/手势名的显示与 4 个颜色、线宽、手势名位置 | ✅ 已实机验证 |
| P6i | **应用目标管理**：新增（从运行中的应用 / 选 `.app` 文件）、移除手势集 | ✅ 已实机验证（Brave Browser 目标已建、bundleId 正确并已落盘） |
| P6j | **应用手势集继承全局**（自己的优先，其余继承；每目标一个开关） | ✅ 已实机验证 |
| 修复 | AppKit 覆写导致的崩溃（`zWGestures-2026-09-28-211050.ips`）+ 源码守卫脚本 | ✅ 已修复；修复后连续使用约 1 小时无新崩溃报告（此类偶发崩溃只能说「观察中」） |
| P9 | 开机自启：`SMAppService` 优先 + **LaunchAgent 兜底** + 菜单栏开关 | ✅ 已实机验证（**重启后自动启动**：开机 22:59:28，5 分钟后进程已是 `/Applications` 那份、无 LaunchAgent 兜底、无新崩溃） |

**可以日常使用的程度**：右键基本手势全部工作 —— 识别、执行命令、轨迹与手势名实时显示、
命中变绿淡出、未识别不弹菜单、急停快捷键；**并且改手势不再需要手改 JSON**：
浏览/搜索/改名/删除、重画形状（全屏录制）、改动作、按顺序调优先级、单独禁用某条、
给某个应用新建手势集（自己的优先、其余继承全局）、偏好设置（超时/外观/目标模式）都在界面里，
保存前自动备份。

「✅ 已实机验证」= 在本机用 `make run-settings` 实际操作过并确认行为符合预期。

## 3. 下一步（按建议优先级）

> **2026-09-28 收尾复核**：P6a–P6l（设置界面全部）与 **P9（开机自启）** 均已实机验证通过。
> 剩下的按下面顺序，触发矩阵与边角/滚轮触发**主动押后**（有数据支撑，见第 3 项）。

1. **P7 验收与加固**：多屏、全屏应用、长时间运行、连续快速手势。
   这是当前最该做的一项 —— 应用已经日常在用（开机自启也通了），**真实问题会在这里暴露**。
   注意有些项我这边的环境测不了（我只有单屏、无法模拟连续快速手势），需要你按下面几条实测：
   多显示器之间画手势、在**全屏应用**（视频/游戏/演示）里画、连续快速画多次、
   长时间挂着不重启；调试面板的 `state`/`tap`/`events`/`replays` 四行是主要判据。
2. **P8 的一部分（按价值排）**：手势**分组**（原版 `Groups`，本机配置为空、on-disk 结构未知，
   需要先勘察）、拼音搜索（手势多了以后有用）、动画回放。
3. **触发矩阵编辑 + 边角/滚轮触发（P5 剩余）** —— 押后，但两者应一起做：
   实测用户配置的 42 行矩阵里 **39 行是边角签名**，只有 3 行是鼠标键，而唯一在用的右键那行
   本来就是启用的，所以现在做矩阵编辑器几乎不产生实际效果。边角/滚轮手势同理：
   用户配置里有 12 条这类手势（已默认隐藏），实现这两种触发后它们立刻可用。
   ⚠️ 已知缺陷：`areModifiersSatisfied` 对 `HSCROLL` 也拿 `deltaY` 比对（横向修饰键会被竖向滚动
   满足），所以界面上**不提供**左右滚修饰键。做 P5 时应一并修掉。
4. **完整可视化编辑器**：拖放建手势、所见即所得的修饰键/触发方式编辑。

## 4. 常用命令

```bash
cd /Users/zilong/zWork/ai/zWGestures

make build      # xcodegen generate + xcodebuild（会自动解锁签名钥匙串）
make test       # 运行 ZWGCore 的单元测试（223 项）
make run        # 构建并启动
make run-debug  # 构建并启动，同时打开调试面板（ZWG_DEBUG_HUD=1）
make install    # 构建并把 .app 拷到 /Applications（开机自启需要固定路径）
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
| 应用目标语义 | **已推翻并改掉（2026-09-28）**：原记录是「应用目标**替换**全局手势，不叠加（用户从原版 UI 确认：Finder 目标只有 3 条）」。用户实测后指出这不对 —— 给 Brave 加一条手势后，那个应用里其余全局手势全都不见了。**现在的语义是叠加：应用自己的手势优先，未定义的继承全局**，每个目标一个「继承全局手势」开关（`WGTarget.inheritsGlobal`）。见 §12「应用手势集继承全局」。 |
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
- `IsSimple = false`：`P` 是手写轨迹的点列，**坐标系与前一种完全相同**（同样绘制顺序、
  同样 y 轴向上为正）。`IsSimple` 只影响匹配宽容度，不影响解码。

> ⚠️ 这里踩过**两次**坑，都是坐标系的问题，务必引以为戒。
>
> **第一次**：把 `P` 读成倒序、把 y 读成向下。两个错误对纯竖直笔画（`拷贝`↑ / `粘贴`↓）
> 恰好互相抵消，所以看起来是对的，而所有横向与折线手势都被静默算成镜像或旋转版本。
>
> **第二次**：修好简单手势后，又以为任意形状的 `P` 是原始屏幕坐标、不需要翻转，
> 于是用户「重新载入」与「其他窗口」两条最常用的手势上下颠倒。
> 当时的错误论据是「`P` 里的 y 全是正数，所以是屏幕坐标」—— 但**原点在屏幕底部时
> y 也是正数**，这个论据根本不成立。
>
> 两次的抓错手段：
> 1. **命令语义**：`Back` 绑定 ⌘[，画出来必须是**向左**。
> 2. **原版快捷入门图**（放大核对）：「拷贝」的起笔圆圈在箭头**下方**；
>    「关闭标签页」= 下→右；「退出」= 下→左；「新建标签页」= 右→下。
> 3. **用户报告的现象反推**：两条手势互为镜像 + 它们在混淆报告里距离 ≥ 0.30
>    （识别器不可能弄混）⇒ 只能是解码错。
> 4. **先跑全量手势两两距离的混淆报告**（`ConfusionReportTests`）再动手，
>    不要「用户报一条、我修一条」。
>
> 这些都固化成了断言：`StrokeDirectionTests` 用真实配置的 `P` 原值直接断言方向语义，
> `ConfusionReportTests` 断言 `重新载入` 与 `其他窗口` 必须能区分。

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

## 8. 已知陷阱

### 叠加层必须「先清除」且只失效轨迹矩形（2026-09-28 修）

用户报「已识别的绿色轨迹下面有一层模糊残影」。查下来是渲染层的两个缺陷（数据流是干净的：
状态里只有一条轨迹，新按下时会清掉上一条）：

1. `needsDisplay = needsDrawing` —— 当 alpha 归零时**不重画**，而 `needsDisplay = false`
   只是「不重画」、**不会清除已有像素**。轮询一旦跨过 alpha 归零那一刻，最后画上的那帧就
   **永久定格**在屏幕上。
2. 每帧 `needsDisplay = true` 让**整视图**（外接屏 2304×1296 @2x ≈ 1200 万像素）重画并整块
   上传图层（约 47MB/帧），而实际只有轨迹那几像素在变。帧率因此很粗，淡出以粗步进推进，
   最后一帧可能停在 alpha 0.1~0.2 —— 那层半透明旧轨迹叠在清晰轨迹下，正是「模糊残影」。
   叠加层是**图层支撑**的视图，**不会自动擦除上一帧**，而 `draw` 里从没 `clear` 过。

修法：
- `TrailBounds`（ZWGCore，纯几何、有单测）：算描边折线的包围盒（按线宽撑开），
  以及「上帧区域 ∪ 本帧区域」的并集
- `refresh` 改成 `setNeedsDisplay(该矩形)`；`draw(_:)` 开头 `cgContext.clear(dirtyRect)`
- 不可见时传空状态，于是**失效的就是上帧区域** → 那一帧把残留擦掉（修掉缺陷 1）
- 面板重新显示时整块重画一次：窗口隐藏期间不重画，图层里可能还留着上一次的轨迹

### 备份文件名绝不可复用（2026-09-28 修）

`ConfigStore.backUpIfPresent` 的硬要求：**新备份的时间戳必须严格大于该 label 已存在的最新一份**，
不能用「第一个空出来的名字」。原因是淘汰逻辑按名字序删最旧的，而**被淘汰的正是最小的那个名字** ——
如果新备份复用了它，它立刻又成为「最旧的」，下一次淘汰就**把刚写的文件删掉**，
表现是「保存超过 10 次后备份不再增加」，而且**不报错**。

这个 bug 只在同一毫秒内连续保存时出现，手工点保存几乎碰不到（所以设置界面从没暴露过它），
但测试里快速循环保存就会命中 —— 表现为**每 8 次跑挂 1 次**的 flaky 失败。
修法与防线：`nextStamp(for:formatter:)` 取「now 与已存在最新时间戳+1ms 的较大者」；
测试把时钟钉死在同一毫秒（`ConfigStore.now` 是可注入的），让撞名路径**必然**发生。
（踩过的，别重复）

- 🔴 **不要在 `NSView` / `NSWindow` 的覆写里带 actor 隔离 —— 这是同一个雷区的第二条路径。**
  `NSView`/`NSWindow` 在本 SDK 上被标注为 `@MainActor`，所以覆写它们的成员会继承这份隔离，
  Swift 于是**在覆写入口插入「当前是否在主 actor 上」的运行时检查**。而 AppKit 会从
  **跟踪区域 / 命中测试**这些内部路径去问这些成员，那个检查在那里**崩过**：

  ```
  crash report zWGestures-2026-09-28-211050.ips
  EXC_BAD_ACCESS / SIGSEGV in swift_task_isMainExecutorImpl
    _checkExpectedExecutor
    zWGestures  @objc TrailView.isFlipped.getter      ← 崩在这里
    AppKit      _convertPoint_fromAncestor
    AppKit      ___nonOverridableViewHitTest_block_invoke
    AppKit      -[_NSTrackingAreaAKManager _mouseMoved:]
  ```

  与 02:50 那份（`MainActor.assumeIsolated`，Timer block）**是同一族故障的不同入口**，
  特征都是 `SerialExecutorRef::isMainExecutor` 自己 fault。

  **修法**：纯几何/谓词类覆写一律标 `nonisolated`（它们不读任何 actor 状态，opt-out 零成本）。
  目前需要标记的成员清单（`scripts/check-appkit-isolation.py` 会强制检查，`make test` 会先跑它）：
  `isFlipped`、`hitTest`、`acceptsFirstResponder`、`canBecomeKeyView`、`canBecomeKey`、
  `canBecomeMain`、`menu(for:)`。**新增任何 AppKit 覆写时先跑一遍 `make lint`。**
  注意 `draw(_:)` 与鼠标事件处理**故意保持隔离**：它们走正常事件派发，实测没问题，
  而且它们要读实例状态，标 `nonisolated` 会引发一片隔离错误。若将来在那里也崩，再单独处理。

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

- 单元测试：`make test`（223 项），其中多条**针对用户真实配置**的强回归断言。
- 实机验证：用户用右键画手势，读调试面板（`make run-debug`）的
  `state` / `gesture` / `target` / `executed` 四行，并观察屏幕上的轨迹与手势名。
- 崩溃报告在 `~/Library/Logs/DiagnosticReports/zWGestures-*.ips`
  （`.ips` 首行是 JSON 头、第二行才是正文，可用 Python 解析）。

## 10. 开机自启（P9 做法与坑）

实现在 `zWGestures/App/LoginItem.swift`，菜单栏「开机自动启动」开关调用它。

- 用 `SMAppService.mainApp.register()` / `unregister()`，**不需要**额外的 entitlement
  （App Sandbox 关闭、本机自签名即可）。
- **系统是唯一真相**：每次刷新菜单都读 `SMAppService.mainApp.status`，不拿 `prefs.json`
  当依据 —— 用户可以在「系统设置 → 通用 → 登录项」里绕过我们把开关关掉。
  `prefs.json` 里的 `AutoStart` 只在**注册成功后**才回写，保持两边一致。
- **不主动注册**：启动时不检查 `AutoStart` 去自动 `register()`。原版偏好里
  `AutoStart` 默认是 `true`，但那是导入来的意图，不该在用户没点开关时擅自写进系统。
- `status` 有五种：`notRegistered` / `enabled` / `requiresApproval` / `notFound` /
  `unknown`。`requiresApproval` 表示系统要用户在设置里手动放行，此时菜单标题会显示
  「等待系统设置里确认」，并在点击后直接打开登录项面板
  （`SMAppService.openSystemSettingsLoginItems()`）。
- ⚠️ **重新导入配置不许覆盖登录项状态。** 原版 `2.3.3/prefs.json` 里
  `AutoStart: true`，而导入会把原版偏好整份覆盖到本地 —— 于是「先关掉自启、再重新导入」
  会让 `prefs.json` 说开着、系统却是关的。修法：`ConfigController.importLegacy` 在导入
  **之前**记下系统状态，导入后若不一致就用系统的值写回并记日志（`readLoginItem`
  这个闭包是为了让这条交互可测而注入的）。
- ⚠️ **登录项记录的是应用路径。** 应用只在
  `build/Build/Products/Debug/zWGestures.app` 里时也能注册成功，但 `make clean`
  或移动应用之后这条登录项就失效了。所以补了 `make install` 把应用拷到
  `/Applications/zWGestures.app`，在固定路径下注册才稳。
- ✅ **2026-09-28 晚：注册成功。** 先是实测到从 `/Applications/zWGestures.app` 启动时菜单显示
  「系统找不到该应用」（`SMAppService.mainApp.status == .notFound`，且 `sfltool dumpbtm` 里始终
  没有任何记录）；后来**改用原地覆盖方式重装**（`make install` 不再 `rm -rf`）并重新从
  `/Applications` 启动，再点开关就变成了 `.enabled`，底账里出现了：

  ```
  Type: app (0x2)   Disposition: [enabled, allowed, notified]   URL: /Applications/zWGestures.app
  Bundle Identifier: com.zilong.zwgestures
  ```

  **归因要谨慎**：`rm -rf` + `ditto` 重建 bundle 破坏系统关联**只是时序吻合的怀疑**
  （旧装法 → `.notFound`；换原地覆盖 → 注册成功），并不能严格证明因果 —— 也可能来自新构建或
  单纯重新注册。但**结论可以确定**：`SMAppService` 对本机这个无 Team ID 的自签名应用
  **是能用的**，不必绕开它。
  同一时刻 `sfltool dumpbtm` 里**没有任何** zWGestures / zilong 记录，
  近 1 小时的 `smappservice` / BTM 日志也没有相关报错。
  成因大概率是 `make install` 用 `rm -rf` + `ditto` 把已有 bundle 整个删掉重建，
  破坏了系统对这份 bundle 的身份关联 —— **尚未证实**，需要单独一轮排查。
  在状态是 `.notFound` 时点开关，`register()` 会失败，所以这一项**暂时搁置**
  （用户决定：先做别的手势功能，此项放到最后再收尾）。
  可能的排查方向：① 键路径改成原地覆盖（`ditto` 直接盖在现有 bundle 上，
  不先 `rm -rf`）后重新注册；② 查 `SMAppService` 对**无 Team ID 的自签名应用**
  是否本就无法建立登录项关联（若是，则需要换签名方式或改用 LaunchAgent 方案）。
  注意：`.notFound` 与「未注册」不同 —— 前者意味着系统里有残留/损坏的关联记录。
- 失败时（例如签名要求不满足）会弹窗，并附上当前应用路径，提示换固定路径重试。

#### LaunchAgent 兜底（2026-09-28 增加；作为保险保留）

`SMAppService.mainApp` 走 BackgroundTaskManagement，对签名身份比 LaunchAgent 严格。
虽然实测它最终能注册（见上），但**一旦失败用户就完全没有开机自启**，所以保留一条兜底：
开启时**先试 `SMAppService`（成功则系统设置里可见），失败或状态非 enabled/requiresApproval
就写 LaunchAgent**；关闭时**两处都清**，不留残渣。菜单标题显示实际生效的机制
（「已开启（系统登录项）」或「已开启（LaunchAgent）」）—— 用户能看出走的是哪条路。

- plist 位置：`~/Library/LaunchAgents/com.zilong.zwgestures.plist`；生成逻辑在
  `ZWGCore/Support/LaunchAgent.swift`，用 `PropertyListSerialization` 构造而不是拼字符串 ——
  一个格式错误的 plist 会让开机自启**静默失效**，所以这部分有单测（标签、RunAtLoad、
  `open -a` 参数、非 ASCII 路径往返）
- **用 `/usr/bin/open -a <app>` 而不是直接执行二进制**：这样启动走 LaunchServices，
  已手动开着时只是把它切到前台，不会起第二个实例
- 加载/卸载用 `launchctl bootstrap` / `bootout`，状态判断 = plist 存在 **且** `launchctl print`
  成功（只看文件存在会把「写进去了但没加载」误报成已开启）
- 顺带更正一条**我先前的误判**：LaunchServices 里那条「Bundle node not found on disk」的记录
  一开始被我当成根因，但 Sparkle 更新器、Brave 的 helper 等都有一堆同类失效记录，
  有它们照样能正常注册登录项 —— 所以那不是证据，已撤回。

#### 重启验证（2026-09-28 23:04，通过）

机器于 **22:59:28** 重启，5 分钟后检查：

- 进程已经是 `/Applications/zWGestures.app`（pid 2543，登录时自动起来，不是手动启动）
- 底账里 `Type: app` + `Disposition: [enabled, allowed, notified]` 仍在
- **没有** LaunchAgent plist → 走的是系统登录项这条路，兜底未被用到
- 重启后**没有新的崩溃报告**（顺带说明 AppKit 覆写崩溃的修复扛住了重启）

✅ 开机自启验收通过。

## 11. 应用图标

`scripts/make-app-icon.swift` 生成 `zWGestures/Resources/Assets.xcassets/AppIcon.appiconset`
（asset catalog，`make icon`，`VARIANT=corner|swoosh`）；`docs/icon/AppIcon.icns` 是同一脚本产出的
独立分发件（不进 bundle）。设计上刻意与产品自身一致而不另起一套视觉：底色是轨迹面板那种深板岩，
轨迹用**已识别**色 `#20D697`（就是 `prefs.json` 里的 `PathColorRecognized`），
起笔空心圆 + 末端实心点也和屏幕上的轨迹一致；形状取用户配置里真实存在的笔画。

### 必须走 asset catalog，不能用老的 CFBundleIconFile（2026-09-28 实测）

第一版用「`CFBundleIconFile: AppIcon` + 手搓的独立 `.icns`」，结果 Finder 认、**「关于」面板空白**：
- Finder / `NSWorkspace.icon(forFile:)` 走**图标服务**，读 `.icns` 没问题（我把系统返回的图标导出来看过）
- 「关于」面板走 **AppKit 的 `NSApplication.applicationIconImage`**，在 macOS 26/27 上它走
  **asset catalog（编译后的 `Assets.car` + `CFBundleIconName`）**，老形式渲染成空白

改成 asset catalog 后，`actool` 自己会生成一份 `.icns` 并注入 `CFBundleIconFile`
（37KB，比我手搓的 378KB 小得多）。**注意别同时把自己的 `.icns` 放进 Resources**：
两个文件抢同一个路径，谁赢取决于构建顺序。所以脚本现在把 `.icns` 写到 `docs/icon/`。

⚠️ **这次同时改了两处**（asset catalog + 关于面板里显式取图标），所以**无法归因是哪一处解决了空白**。
显式那行是保险（`NSWorkspace.icon(forFile:)` 正是 Finder 验证可用的那条路），
要隔离验证的话删掉它再装一次即可。

两个实现细节值得记：**模块缓存必须放在工作区内**（受限 shell 写不了 `/var/folders` 下的默认缓存，
报错看起来像编译器故障而不是沙箱拒绝 —— 已写进 `make icon`）；**iconset 也落在 `build/`**，
同理。png 由 `NSBitmapImageRep` + `NSGraphicsContext` 逐尺寸渲染（不是把 1024 缩下去，边缘更干净）。

`loop`（闭环）变体渲染出来是实心水滴形 —— 笔画相对闭环太大，填充掉了中间的孔，**已弃用**。

## 12. 设置界面（P6）

菜单栏「打开设置…」（⌘,）→ 左栏手势集、右栏手势列表、搜索框、右键菜单改/删、
双击一条手势（或右键 →「编辑命令…」）打开命令编辑器，底部「保存 / 放弃改动」。
保存后立刻 `engine.apply(...)`，不用重启。

- **P6a（已完成）**：浏览、搜索、重命名、删除、显式保存。
- **P6b（已完成）**：命令编辑器 —— 四类命令都能改，外加「识别手势后立即执行」。
  按键序列支持**录制组合键**（含多步序列，如 `⌘V → ↩`）。
- **P6c（已完成）**：它其实是**手势编辑器** —— 一条手势 = 笔画 + 动作，所以顺序是
  **先画形状、再命名、最后选动作**。列表头部的「+ 新建手势」用同一套流程新增一条。
- **P6e（已完成）**：形状区改成**两栏** —— 左栏显示**现在的手势**，右栏点击后进入
  **全屏录制**（在屏幕任意位置画，与日常画手势的方式一致，画完立刻显示在右栏）；
  「重画」丢弃刚画的重新录，「不改了」放弃新手势保留原形状。

### 分层：逻辑在 ZWGCore，UI 只做渲染

| 文件 | 职责 |
|---|---|
| `ZWGCore/Settings/SettingsModel.swift` | 工作副本、选中目标、搜索、重命名/删除/改命令、脏标记。**全部可单测** |
| `ZWGCore/Settings/CommandEditorModel.swift` | 一条命令的编辑状态：类型切换、按键步骤增删、四类命令的校验。**全部可单测** |
| `ZWGCore/Config/Display/WGIntentDisplay.swift` | 方向文字、命令摘要、输入名（鼠标/滚动/按键符号） |
| `zWGestures/UI/SettingsCoordinator.swift` | 装配三者：读 `ConfigController`、写 `ConfigStore`、通知 `EngineController` |
| `zWGestures/UI/SettingsPanel.swift` | SwiftUI 渲染：左栏、列表行、方向缩略图（`Canvas`）、命令编辑 sheet |
| `zWGestures/UI/CommandEditorSheet.swift` | 命令编辑器界面（渲染 `CommandEditorModel`） |
| `zWGestures/UI/KeyCaptureView.swift` | 按键录制：第一响应者 `NSView`，见下面的警告 |
| `zWGestures/UI/SettingsWindowController.swift` | 窗口与所有需要 `NSAlert` 的模态 |

这么分的原因见 §8 的 Timer/SIGBUS 教训：UI 层越薄，能跑单测的逻辑就越多。宁可在
`SettingsModel` 里多写点代码，也不要把状态机放进 SwiftUI。

### ⚠️ 按键录制不要用 `NSEvent.addLocalMonitorForEvents`

它的闭包**不是 `@MainActor` 隔离**的，从里面碰编辑器的状态会迫使编译器插入
`MainActor.assumeIsolated` —— 正是让本 App SIGBUS 崩过的那种组合（§8）。所以录制用的是
第一响应者 `NSView`（`KeyCaptureView`），事件投递到 responder 时本来就在主线程/主 actor 上。

两个必须注意的点：
- **必须重写 `performKeyEquivalent`**：⌘ 组合键会被窗口菜单先吃掉，`keyDown` 根本收不到，
  而「录制 ⌘C」是最常见的用法。
- **`isRecording == false` 时要把所有事件交还**（`super.keyDown` / 返回 `false`），否则
  Escape 再也到不了 sheet 的「取消」按钮。

### 未知命令类型必须显式确认

配置里可能出现本版本不认识的 `$type`（原版有 Lua/Cmd 等）。`CommandEditorModel` 会把这种
命令标成「未知」并**禁止提交**，直到用户点「我知道，要替换它」—— 否则改一次命令就会悄悄把
用户的原始数据抹掉。

### ⚠️ 不要用 `onTapGesture(count: 2)`，弹窗也别用 SwiftUI 的 `.sheet`

（**本节已被上面的「诊断教训」取代**：那两条结论建立在「旧进程」的误判上，没有证据。
`onTapGesture(count: 2)` 现在正常工作，用于双击打开编辑器；命令编辑器保留 AppKit
`beginSheet` 只是因为其他模态都是 AppKit，一致且已验证。）

实测（2026-09-28）两处「点了没反应」，都改成 AppKit 机制后解决：

- **手势列表的行**：`onTapGesture(count: 2)` 在 `ScrollView` + `LazyVStack` 里**根本不触发**，
  双击行没有任何反应。现在整行是一个 `.buttonStyle(.plain)` 的 `Button`（单击即打开命令
  编辑器），用的是和「重命名 / 保存」按钮完全一样的点击路径 —— 那些按钮已被证实在同一个
  窗口里可以正常工作。铅笔图标也从「仅悬停时出现」改成常驻，避免看不见入口。
- **命令编辑器弹窗**：原本用 SwiftUI 的 `.sheet(item:)`，改成 AppKit 的
  `NSWindow.beginSheet`。理由同上：本 App 里所有**已被证实可用**的模态（重命名、删除确认）
  都是 AppKit 的。以后加新弹窗请照这个来。
- 两个入口都加了 `Log.ui` 日志（「打开命令编辑器…」「命令编辑器已提交…」），这样
  「点击没反应」可以区分成两种情况：**没有日志 = 点击没到代码**，**有日志但没界面 =
  呈现失败**。排查命令见 README（`log stream --predicate 'subsystem == "com.zilong.zwgestures"'`）。

> ⚠️ **上面这段的第一版结论是错的，别照着抄。** 当时把「点击没反应」归因于
> `onTapGesture(count: 2)` 在 `ScrollView` 里不触发，还据此把整行改成了 `Button`。
> 真实原因见下面「诊断教训」：**一直在测旧进程**。改成 AppKit `beginSheet` 是有效的改进
> （本 App 其他模态都是 AppKit，保留），但「SwiftUI 手势/`.sheet` 不可用」这个结论**没有
> 证据支持**，`onTapGesture(count: 2)` 现在已恢复为双击打开编辑器的正常实现。

### 🔴 诊断教训：`open` 不会重启已在运行的 App（最容易骗到自己）

连续三次「点了没反应」的真实原因：**测的一直是旧进程**。

- macOS 上**覆盖二进制文件不影响已在运行的进程**，它内存里还是旧代码；而
  `open <App>` 对一个**已在运行**的 App **只做前台激活，绝不启动新二进制**。
  于是「改了代码 → `make run` → 没变化」，看起来像改动无效，其实新代码根本没跑。
- 症状特征（三条同时出现就要立刻怀疑）：新加的功能无效 + **新加的日志一行都没有** +
  旧行为照旧。日志缺失是最强的信号 —— 代码里明明写了 `Log`，却什么都不输出。
- 现在有两道防线：
  1. **`make run` / `run-debug` / `run-settings` / `install` 都先跑 `stop` 目标**：
     用 `osascript` 发正常退出指令（不是 kill，要让它走 `applicationWillTerminate`
     卸载 EventTap），轮询等它真的退出，超时才警告。
  2. **构建标记**：设置窗口标题与底部状态栏都显示 `BuildInfo.buildStamp`
     （可执行文件的写入时间）。一眼就能确认「这个进程是哪次编译」。
- 我自己的盲区：`ps` 在本沙箱里被拒绝（`Operation not permitted`），我**读不到进程启动时间**，
  所以当时无法从这边证实，只能靠构建标记让你一眼看出来。

### 录制按键的语义：一个热键 vs 多步序列

第一版只有一个「录制按键」，每按一次加一步，于是用户录 ⌘C 时就出现了「第 1 步 ⌘C /
第 2 步 ⌘C / 第 3 步 ⌘W」。现在拆成两个明确动作：

- **「录制按键」/「重新录制」**（`CommandEditorModel.setSingleStep`）：按一个组合键，
  **整段替换**，然后**自动停止录制** —— 点了「录制」的人期待的是一个热键。
- **「添加一步」**（`appendStep`）：接到序列最后，并**继续录制**，可连续加多步。

### 一条手势 = 笔画 + 动作（用户纠正过的模型）

**别再把设置界面做成「笔画只读缩略图 + 只能改动作」。** 用户 2026-09-28 明确纠正：
「编辑这个手势是把我现在的手势修改或者是改为新的手势 …… 确定新的手势以后，这个手势会引发的
后续动作才会有快捷键、网络搜索、系统脚本或者是系统功能。」所以编辑器的顺序必须是
**形状 → 名称 → 动作**，而「录制」必须录的是**鼠标笔画**，不是键盘组合键。

### 录制笔画：用识别器自己做往返校验

`WGStrokeRecorder`（`ZWGCore/Settings/WGStrokeRecorder.swift`）把画布上的
**屏幕坐标点列（y 向下、绘制顺序）**编码成配置里的 `StrokeStep`。三个关键点：

1. **输出必须取反 y**：配置的约定是 y 向上为正（简单与任意形状一致，见 §6）。
   输入约定是屏幕坐标，所以编码时统一取反 —— 画布 `StrokeCanvasNSView` 用
   `isFlipped = true`，让它的坐标本身就是屏幕方向，**中间不再有任何一步手工换算**。
2. **存下来的形状必须仍然能被识别**：候选的「简单手势」编码出来后，会用**识别器自己的
   归一化距离**（`StrokeNormalizer` + `StrokeMatcher`）与原始绘制比对，只有距离 ≤
   `simpleFormTolerance`（0.06，远低于匹配阈值 0.10）才采用；否则退回存任意形状。
   这样「存进去却认不出来」在结构上就不可能发生。
3. 简单手势用 **50 网格的轴对齐折线**（原版 36 条里有 32 条是这种），任意形状则压缩到
   ≤12 个点，并把起点平移到原点 —— 原版存的是绝对屏幕坐标（如 `969, 546`），
   归一化后位置无意义，相对坐标在文件里更可读。

回归防线：`WGStrokeRecorderTests` 直接断言「上/下/左/右/下→右/闭环」的方向文字，
并且有一条**与真实配置里「Copy」定义比对归一化距离**的测试 —— 录一个向上笔画必须能匹配
原版的拷贝，这是 y 轴方向与绘制顺序最强的守卫（这两点历史上各错过一次）。

### ⚠️ 同形状不一定是冲突 —— 必须看修饰键

**这是我在 P6d 第一版里犯过的错，差点把用户正常的配置判成坏的。**
用户真实配置里 `Copy` 与 `Cut` 都是「上」、`Paste` 与 `Paste & Enter` 都是「下」，
区分它们的是**手势修饰键**（鼠标左键）。识别器 `GestureRecognizer` 的实际规则是：

- `areModifiersSatisfied`：意图声明的每个修饰键步骤都必须真实发生（子集判定）；
- `bestCandidate`：**修饰键多的优先**，其次比形状距离，平局给列表靠后的。

所以不按左键时只有 `Copy` 符合条件，按住左键时 `Cut` 更具体而胜出 —— **两条都能用**。
判成冲突的条件必须同时满足三条：**同一个触发键 + 同样的修饰键要求 + 形状距离 ≤ 阈值**。
`WGStrokeConflict` 用签名比较（滚动的幅度折叠成方向，与识别器一致）实现这三条，
并有一条**不变量测试**跑在用户的真实配置上：凡是被报出来的冲突，两条手势的触发与修饰键
签名必须完全一致。

### 顺带查出的既存问题

2026-09-28 独立复算用户配置（另写一份 Python 复算，与 Swift 实现互证）发现
**导入原版时就有的同形重复**（`P` 逐字节相同、都不带修饰键，任何匹配算法都无法区分）：
`Close`/`Sleep`、`Terminal`/`Activity Monitor`、`重新打开`/`Shut Down`、
`Fullscreen`/`其他窗口`（后两对距离 0.000 / 0.068）。原版同样只有一条能生效，
现在列表里会用橙色 ⚠️ 标出来。

### 按手势禁用：`Enabled` 是本项目的扩展字段

原版 `Intent` 里**没有**启用开关（它只有触发矩阵 `Triggers`，是按触发方式启停，做不到
「禁用某一条手势」）。所以这条是扩展：

- `WGIntent.enabled`，缺键即视为启用；**只有禁用时才写出 `"Enabled": false`**。
  这一点是硬约束：`ConfigTests` 有一条「真实配置重新编码后与原文件逐键一致」的守卫，
  如果对启用状态也写键，那条测试立刻失败（已实测验证通过）。
- 识别器 `scoredCandidates` 第一步就 `guard intent.enabled`，禁用的手势不进入候选；
  调试面板的「最近候选」也不会再报一条已禁用的手势。
- **禁用的手势不参与冲突检测** —— 它本来就不会生效，不该占着某个形状不让别人用。
  这也是用户解决重复形状冲突的另一个办法（除了排序与改形状）。
- 界面：每行最左边一个复选框（禁用后整行变淡 45%），右键菜单有「启用/禁用」，
  编辑器里也有「启用这条手势」。底部状态栏显示「其中已禁用 N 条」。
- 注意：原版 App 不认识这个键会忽略它，于是被禁用的手势在原版里**仍然生效**。
  这个偏差可以接受（本项目就是为了替代它），但必须记在这里。

### 🔴 同形状冲突：**列表靠前的优先**（引擎行为已按用户要求改变）

用户明确要求「可以通过手势的排序，按照排序前面的优先」。因此
`GestureRecognizer.bestCandidate` 的取舍顺序是：

1. **手势修饰键多的优先** —— `拷贝`/`剪切` 靠左键区分，这条不能动，否则按左键时会被
   排在前面但不需要修饰键的那条抢走；
2. **列表靠前的优先** —— 这是用户可控制的优先级；设置界面里右键「上移 / 下移」就是改它；
3. 形状更近，仅作最后兜底。

**这是对原版的刻意偏离**：原版文档行为是「later match wins（靠后的优先）」，
现在改成靠前的优先，理由是「可见、可调的顺序」比「文件里最后一条赢」好理解得多，
而且这正是设置界面里排序功能的意义所在。

改顺序的方式是**拖拽**（用户要求）：行首有 `line.3.horizontal` 手柄，按住行拖到目标位置即可。
长列表（全局有 50+ 条）里跨屏拖拽不好操作，所以右键菜单提供四个入口：
**上移 / 下移 / 移到最前（最高优先级）/ 移到最后（最低优先级）** —— 后两个在 50 条手势里
是一步到位的唯一办法。两个实现细节：
- 拖拽落下时用**状态里的拖动源下标**，不去回读粘贴板 —— 进程内拖拽没必要引入异步，
  少一个失败模式（`GestureRowDropDelegate` 只负责高亮与回调，`performDrop` 直接调 `onDrop()`）。
- **搜索过滤时禁用拖拽**：过滤后可见的是子集，落点下标与用户看到的顺序对不上。
  此时底部状态栏会提示「清空搜索后可拖拽调整顺序」。

把顺序放在距离之前是**安全**的：在用户的真实配置里，非重复形状之间最近的一对约 0.28，
是匹配阈值 0.10 的近三倍，所以「两条不同形状同时通过阈值」实际不会发生 ——
顺序只会在**真正的重复**之间做决定。这条推理写进了 `bestCandidate` 的注释与
`GestureRecognizerTests` 的两个用例（靠前的赢；修饰键优先级不被顺序推翻）。

### 录制期间必须暂停引擎

画笔画用的是**右键** —— 正是全局 EventTap 盯着的按钮。所以打开手势编辑器时
`SettingsCoordinator.beginShapeEditing()` 会 `engine.pause(...)`（`pause` 是真的把
EventTap 拆掉，不是「忽略事件」），关闭时**只按原状态恢复**：用户自己暂停过的话不会被
擅自打开。

全屏录制用 `StrokeRecordingOverlay`：一个**无边框、覆盖所有屏幕**的窗口（`level = .screenSaver`，
内容视图复用 `StrokeCanvasNSView` 的 `.fullScreen` 样式）。两个容易踩的点：
① 无边框 `NSWindow` 默认**不能成为 key window**，不重写 `canBecomeKey` 的话 Esc 收不到；
② 画得太短时**不要关掉覆盖层**，而是把原因画在上面让用户重画（`onDraw` 返回非 nil 即继续录制）。

### 列表行的排版约定

行的左列**只放「怎么触发」**（名称、笔画方向、手势修饰键），右列**只放「做什么」**（命令摘要）。
第一版把修饰键放到了右列，于是「下」和「鼠标左键」被命令摘要隔开了一大段，用户一眼就看出
排版不对 —— 这两个信息都属于触发方式，必须挨在一起。改动很小，但这条约定要留着。

### 应用手势集继承全局（2026-09-28 推翻旧决策）

旧决策是「应用目标替换全局」（依据是原版 UI 里 Finder 目标只显示 3 条手势）。用户实测指出这是错的：
给 Brave 加了一条「保存」后，Brave 里**连拷贝粘贴都不能用了**。现在的语义：

- **应用自己的手势排在前面** —— 顺序就是优先级（`bestCandidate` 靠前的赢），所以同形状时应用的赢；
- **其余继承全局** —— 应用没定义的形状照常工作；
- 每个目标一个开关：`WGTarget.inheritsGlobal`（**默认：应用目标开启，桌面等特殊目标关闭**）。
  桌面目标保持关闭是为了不悄悄改变现状：用户配置里那个 Desktop 目标本来是空的，
  一旦默认继承就会让桌面上突然多出 49 条手势。

实现落在 **`TargetResolver.resolve`**：合并成一份「有效手势集」再交给识别器，
所以匹配、调试面板、触发矩阵**一行都没改**。这是刻意的 —— 引擎只认识 `resolved.target`。

`inheritsGlobal` 与 `WGIntent.enabled` 一样是本项目的扩展键，**只在偏离该类型的默认值时才写出**，
保证重新编码真实配置仍然逐键一致（`ConfigTests` 守着）。

### 继承来的手势在列表里可见但只读

窗口会给应用目标列出「自己的 + 继承来的」，继承的那些变淡、带「继承自全局」徽标、
不可编辑/删除/拖动/切换启用，双击或点徽标会**跳到全局手势集**去改 —— 避免出现
「在这里改了但其实改的是另一条」的错觉。

两个实现细节：
- **继承行的 `id` 从自有手势之后开始编号**。`ForEach` 用 `id` 做身份，两段都从 0 开始会撞车、
  让 SwiftUI 渲染错乱；这个偏移同时保证「误用继承行的 id 去改自有数组」会越界失败而不是改错对象。
- 冲突检测**仍然只在各自的手势集内部做**。应用手势与全局手势形状相同是**有意覆盖**，
  不该报警告 —— 那正是「自己的优先」的用法。

### 新增应用目标时的判重比识别器更严格

`WGAppCandidate.isCovered(by:)` **故意比 `TargetResolver.matchApplication` 严**。识别器的规则是
「bundleId 优先，路径只对**没有 bundleId 的目标**生效」。如果照抄，就会出现这种情况：
给已有 `com.apple.finder` 目标的 Finder 再添加一个**只有路径**的目标 —— 它永远轮不到，
因为 bundleId 那一轮先返回了已有目标。判重的意义正是「不创建永远不会生效的目标」，
所以这里**一律比路径**，并且两边都归约到 `.app` bundle（`TargetResolver.bundlePath(of:)`），
这样 `…/Finder.app` 与 `…/Finder.app/Contents/MacOS/Finder` 视为同一个应用。

### 刻意的设计选择

1. **显式保存，不做输入即写。** 窗口只改内存里的工作副本，`isDirty` 为真时才亮「保存」。
   `config.json` 是用户的真实配置，输入中途写坏很难受。
2. **未保存的改动绝不进运行中的引擎。** 连删除手势都只改工作副本；`engine.apply`
   只在写盘成功之后调用。这样「引擎在跑的」永远等于「磁盘上有的」。
3. **状态以文件为准。** 窗口每次 `show()` 都 `reloadFromConfig()`，因为菜单栏可以随时
   重新导入配置，窗口不能抱着过期副本。因此 `SettingsModel.load(config:)` 是**原地更新**
   同一个实例 —— SwiftUI 绑定的是这个对象，换实例会让窗口渲染旧数据。
4. **保存必须有可见反馈。** 第一版保存成功后只把按钮变灰，用户实测报「保存点了没反应」——
   而磁盘上其实已经写好了（`config.json` 的 mtime 与内容都变了）。现在保存成功会在标题栏
   闪 3 秒「已保存到 config.json」（用 `Task` + `sleep` 重置，**不用 `Timer`**，见 §8），
   同时用窗口关闭按钮上的小红点表示有未保存改动（`isDocumentEdited`）。
   教训：磁盘写入是无声的，别指望用户从按钮变灰推断出「成功了」。

### 顺手合并的一处重复

`WGCommandPlanner.summary(of:)` 与新增的 `WGCommand.summary` 是同一个「命令摘要」的两份
实现。现在前者转发给后者，**单一来源**，菜单栏的「已执行」日志行与设置界面不可能再对不上。
`CommandPlannerTests` 里的 `⌘+⇧+T` 断言原样保留。

### ⚠️ 不要用 `@Observable` 宏

`SettingsModel` 用的是 `ObservableObject` + `@Published`，**不是** `@Observable` 宏。
实测（2026-09-28）：`@Observable` 在本工程的 Xcode 构建下直接编译失败 ——

```
error: external macro implementation type 'ObservationMacros.ObservableMacro' could not be found
       for macro 'Observable()'; 'swift-plugin-server' produced malformed response
```

`swift-plugin-server` 这个宏插件在本机 Xcode 26.6 下返回损坏响应。`ObservableObject`
是纯编译期特性、不依赖插件，功能等价。以后再想用宏（`@Observable`、`#Predicate`、
自定义宏）都要先想到这条。

## 13. 明确的边界

- 不复制、不打包原版任何二进制、字体、图标、资源或激活码；只做配置格式互通。
- 不复刻 Windows 版特有功能：自定义菜单、Lua、Cmd 脚本、运行/激活应用程序。
- 不做 App Store 上架（沙箱与全局输入拦截互斥）。
