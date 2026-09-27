<!--
本文件是 2026-09-28 经子龙批准的那份实施方案的**原样导出**，不是重写的。
来源：DSH 会话记录 ~/.dsh/sessions/--Users-zilong-zWork-ai-zWGestures--/session-374ee8cb-18f7-4f08-8a30-15d2ff4cb425/session.v4.jsonl.zstd
      中 seq=204 的 exit_plan_mode 工具调用（提交时间 2026-09-28 00:54）。
进度与后续计划请看 docs/ROADMAP.md；本文件只作为当时的方案存档，不再更新。
-->

# zWGestures — 原生 arm64 版 WGestures 实施方案

## 1. 目标与成功标准

**目标**：在 Apple Silicon 上以原生 arm64 复刻 WGestures 2.3.3 (macOS) 的可感知功能，不依赖 Rosetta，并能**直接导入你现有的配置**，做到日常无感替换。

**v0.1 成功标准（可验收）**
1. `file`/`lipo -info` 显示纯 arm64，运行时不加载 `oahd`。
2. 导入 `~/Library/Application Support/com.yingdev.wgestures/2.3.3/{gestures.json,prefs.json}` 后，**General 49 条手势 + Finder 目标 3 条手势**全部可触发。
3. 与原版逐项对照通过：右/中/左键画线、斜线、任意曲线、边角（碰撞/点击/滚轮/滑动）、手势修饰键（`剪切` vs `拷贝`）、4 类命令。
4. 轨迹与手势名可视化（颜色/线宽/标签位置均读偏好），执行后按 `ShowGesturePath` 淡出。
5. 菜单栏图标、暂停/继续、起始超时绕过、开机自启。
6. **绝不卡死鼠标**：未授权、tap 被系统禁用、退出时都完整恢复被抑制的按键与鼠标事件。
7. 单元测试全绿（配置往返、旧配置导入快照、键名映射、边角位掩码、轨迹识别回归）。

## 2. 已确认的决策

| 项 | 决定 |
|---|---|
| 范围 | **分阶段**：先交付可日常替代的核心版 v0.1，再做完整可视化编辑器 |
| 签名 | 本机自签名证书 `zWGestures Local Signing`（稳定 CDHash，辅助功能授权一次长期有效） |
| 最低系统 | macOS 14 Sonoma+，SDK macOS 26.5，仅 arm64 |
| 技术栈 | Swift 6 + AppKit 为主 / SwiftUI 做设置界面；**零第三方依赖** |
| 工程 | XcodeGen 2.46.0（本机已装）由 `project.yml` 生成 `.xcodeproj`；`xcodebuild` 构建 |
| 沙箱 | **关闭 App Sandbox**（全局事件拦截 + Shell 脚本必需），不进 App Store |
| 语言 | 中文（zh-Hans）为主，保留英文资源 |

## 3. 已勘察到的原版数据模型（迁移依据，已实测）

工作区 `/Users/zilong/zWork/ai/zWGestures` 目前为空、非 git 仓库。原版信息来自只读勘察：

- 结构：`{General, Groups, Apps, Specials}`，每个 Target = `{Id, Name, Intents[], Triggers[]}`
- Step 类型：`KeyDownStep{Key}` / `StrokeStep{IsSimple,P[]}` / `MoveToEdgeCornerStep{EdgeCorner:{Value}}` / `ScrollStep{IsHorizontal}`
- Key 取值实测：`MOUSE:0..2`（0=左 1=右 2=中，对应 CGMouseButton）、`VSCROLL:±n`（实测 1/11/12/13 等原始滚动量）
- Command 类型实测：`KeySeqCommand{IsSystemHotKey,Keys[]}`（`null` 分隔序列步，如 `["Command","ANSI_V",null,"Return"]`）、`WebSearchCommand{SearchEngine}`、`ShellScriptCommand{Script}`、`SystemFunctionKeyCommand{SelectedIndex}`
- `SystemFunctionKeyCommand.SelectedIndex` 0..7 = 亮度-/亮度+/上一曲/播放暂停/下一曲/静音/音量-/音量+（由 tr.json 顺序与配置交叉验证，映射到 `NX_KEYTYPE_*`）
- 偏好全量：`AutoStart, StartDragTimeout, ShowStartDragTimeoutIndicator, ShowPath, ShowGestureName, ShowStatusIcon, PathColorNormal, PathColorRecognized, LabelColorNormal, LabelExecuted, TargetMode, PathLineWidth, GesturePos`
- 脚本环境变量：`WG_TARGET_PID/EXE/WID/APP_NAME/WIN_NAME`、`WG_MOUSE_X/Y/Y_FLIP`

**轨迹编码（已用快捷入门示意图交叉验证，可靠）**
- `IsSimple=true`：`P` 是扁平点数组，**倒序存储**——最后一个点恒为笔画起点 `(0,0)`，坐标 **y 轴向上为正**，网格单位 **50**。
  - 验证：`Copy=[0,-50,0,0]`→↑（起点在下方）、`Paste=[0,50,0,0]`→↓、`Web Search=[0,0,0,50,0,0]`→闭合竖环、`Backspace=[0,0,-50,0,0,0]`→闭合横环、`Fullscreen`/`Minimize` 互为镜像 —— 与 `quickStart.003.png` 的每一张卡片形状完全吻合。
- `IsSimple=false`：`P` 是**原始屏幕坐标点列**（如 `[969,546,1069,395,1203,575]`），识别需归一化 + DTW。

## 4. 技术架构

单一 app target，内部按目录分层：

```
zWGestures/
  App/      AppDelegate、StatusItemController、PermissionGate、PanicGuard（全局急停）
  Config/   WGConfig（Codable，$type 多态）、ConfigStore、LegacyImporter
  Input/    EventTapController、MouseTriggerEngine、EdgeCornerDetector、ScrollNormalizer
  Recog/    StrokeRecorder、SimpleStrokeRecognizer、ShapeRecognizer(DTW)、GestureMatcher
  Target/   TargetResolver(Focused/UnderCursor)、AppTargetRegistry、TriggerInheritance
  Action/   CommandExecutor、KeySequenceRunner、ShellScriptRunner、WebSearchRunner、SystemFunctionRunner
  Overlay/  OverlayWindowController、StrokeRenderer、LabelView、TrailAnimator
  UI/       SettingsWindow、GestureListView、IntentEditorView、PreferencesView、QuickStartView
  Resources/ zh-Hans + en 本地化、AppIcon
zWGesturesTests/
```

### 4.1 输入层（最高风险，Phase 1 先做）
- `CGEvent.tapCreate(tap:.cgSessionEventTap, place:.headInsertEventTap, options:.defaultTap)`，独立线程 + `CFMachPort`/`CFRunLoop`，C 回调桥接。
- **按键透传策略**（保证正常点击不受影响）：
  - 触发键按下 → 先抑制该事件，启动 `StartDragTimeout`（默认 250ms）计时。
  - 超时前位移超过阈值（约 8–10pt）→ 判定为手势，进入绘制态，并把光标精确回起点（原版行为）。
  - 超时且未移动 → 合成一次真实 mouseDown 并放行后续事件，点击正常生效。
  - 手势结束但无匹配命令 → 合成完整 down/drag/up 序列回放给系统（原版"未识别则还原"）。
  - `MOUSE:0`（左键）按原版 2.5.0 起的行为特判：不阻止点击，默认不允许裸左键画线。
- **必须处理 `kCGEventTapDisabledByTimeout/UserInput`**：收到即立刻重启 tap —— 原版"卡死鼠标"的根因就在这里。
- `PanicGuard`：全局急停快捷键（默认 ⌃⌥⌘⎋）+ 信号/退出钩子，任何路径退出都释放被抑制的按键。
- 边角检测：`EdgeCornerDetector` 独立判定，支持碰撞/点击/滚轮/画线/滑动子条件。
- 滚轮：原始 `scrollingDeltaY/X` → "方向 × 量级档位" 归一后再匹配（原文记录了 1/11/12/13 等值，说明是分档而非精确比较）。
- 多屏：`NSScreen.screens` 拼全局坐标，统一用 CG 左上原点，处理不同缩放。

### 4.2 识别层
- 简单手势：实时轨迹量化到 50 网格 → 方向序列打分（含 4 条斜线单列一档）。
- 任意形状：重采样 32 点 → 平移/缩放归一 → 起始方向对齐 → DTW 距离，阈值可调，用于"替换所有相似手势轨迹"。
- `GestureMatcher`：把 `Intent.Gesture` 当作**时序步骤序列**匹配——先匹配触发前缀（触发键 ± 边角/滚轮），画线期间采集轨迹；`ExecuteOnRecognize=true` 时笔画一识别完就执行，否则继续等后续步骤（`MOUSE:0`、`VSCROLL:n`）消歧。同轨迹多条命中时取列表**靠后者**（原版 2.3.1 行为）。
- `General.Triggers[]` 决定每种触发方式启用/禁用；子目标 `Triggers` 为覆盖语义，空数组 = 继承。

### 4.3 目标解析
- `Focused` → `NSWorkspace.frontmostApplication`；`UnderCursor` → `CGWindowListCopyWindowInfo(.optionOnScreenOnly,…)` 取鼠标下最上层窗口的 PID。
- `MacAppTarget` 匹配：BundleId 优先；为 `null` 时由可执行路径反推 `.app` 再取 bundleIdentifier（你现有 Finder 目标就是 Path 形式）。
- 优先级：特殊目标（桌面）> 命中的 App/分组 > General。
- 用 AX API 取窗口标题/窗口 ID，供脚本变量使用。

### 4.4 命令执行
- `KeySeqCommand`：`null` 切分序列步，每步内顺序按下、逆序抬起；`IsSystemHotKey=false`（默认）**先激活目标 App 再发键**，`true` 则不激活。键名映射表覆盖你配置里出现的全部：`ANSI_A..Z`、`ANSI_0..9`、`ANSI_Grave/LeftBracket/RightBracket`、`Return/Delete/ForwardDelete/Home/End/Tab`、`Command/Shift/Control/Option`。
- `WebSearchCommand`：`{0}` 占位；选中文字/剪贴板是 URL 时直接打开，否则搜索。
- `ShellScriptCommand`：`/bin/sh -c`，注入前述 WG_* 环境变量（你的 5 条脚本已用到 `osascript` heredoc 与 `open`）。
- `SystemFunctionKeyCommand`：`NSEvent.otherEvent(.systemDefined, subtype: 8, data1:(NX_KEYTYPE << 16) | 0xA00)`。

### 4.5 可视化
- 每屏一个 `.borderless`、`ignoresMouseEvents`、`isOpaque=false`、`canJoinAllSpaces + fullScreenAuxiliary + stationary` 的窗口，层级 `CGShieldingWindowLevel()` 以免被全屏 App 遮挡。
- `CAShapeLayer` 绘制，60/120Hz 刷新；标签位置/颜色/线宽读偏好；未识别显示警示标记；执行后淡出；设置界面内做轨迹"回放"动画。

### 4.6 配置与导入
- `WGConfig` 用 `Codable` + 自定义 `$type` 多态解码，**字段名与枚举值与原版完全一致**，因此导入导出可直接互通。
- 存储：`~/Library/Application Support/zWGestures/{config.json,prefs.json}`；导入从 `com.yingdev.wgestures/2.3.3/` **只读复制**，幂等，未知字段通过兜底容器保留。
- 版本号/偏好独立于原版，绝不写回原版目录。

### 4.7 权限与稳定性
- 启动检查 `AXIsProcessTrusted()`，未授权弹窗（复刻原版文案）带"打开系统设置"按钮 + 轮询，未授权期间完全不安装 tap。
- Info.plist：`LSUIElement=true`、`NSAppleEventsUsageDescription`（脚本控制其它 App 时的自动化授权提示）；辅助功能/输入监控无 purpose string，只能引导用户勾选。
- 开机自启：`SMAppService.mainApp.register()`。

## 5. 分阶段实施计划

| 阶段 | 内容 | 产出/验收 |
|---|---|---|
| **P0 骨架** | git init、`project.yml`、Info.plist、自签名证书（工作区外操作，单独征求同意）、最小菜单栏 App | 能编译、能被"辅助功能"授权、能启动 |
| **P1 输入引擎** | EventTap 生命周期、抑制/回放、起始超时、禁用自恢复、PanicGuard | 装好后**正常点击/拖拽完全不受影响**；demo 显示当前触发态 |
| **P2 配置层** | 完整 Codable 模型、导入器、偏好 | 单测：模型往返 + 导入你现有配置的快照比对（49+3 条） |
| **P3 识别层** | 简单/任意形状/序列匹配 | 单测：用你配置里的真实轨迹做回归；斜线与曲线可识别 |
| **P4 执行层** | 4 类命令 + Focused/UnderCursor 目标 | 你的 49 条 General + Finder 3 条全部可跑通 |
| **P5 触发扩展 + 可视化** | 边角/滚轮触发、Overlay、菜单栏、开机自启 | 边角 8 个位置 + 滚轮组合全部生效 |
| **P6 设置界面（简版）** | SwiftUI 目标列表 + 手势列表 + 触发矩阵 + 三种命令编辑器 + 手势/快捷键录入 | 可不用手改 JSON 完成日常配置 |
| **P7 对照验收** | 与原版逐项对照、多屏/全屏/长时间运行加固 | 第 1 节全部成功标准达成 |
| **P8（后续）** | 完整可视化编辑器、分组、拖放排序、拼音搜索、动画回放 | 与原版 2.3.3 全功能等价 |

每个阶段的构建/运行命令会**先列给你确认再执行**；批准本方案即视为授权我在 `/Users/zilong/zWork/ai/zWGestures` 内自由写代码/构建。工作区外的一切（建证书、装到 `/Applications`、改系统设置、推 git 远端）都单独再问一次。

## 6. 待验证清单（P1/P3 用小实验定论，不靠猜）

1. **`EdgeCorner.Value` 位掩码映射**：已确定 4 个单值 1/2/4/8 互为相邻环（因为 3/6/9/12 是对角，且 1|2=3、2|4=6、4|8=12、8|1=9），即 `{Top,Right,Bottom,Left}` 或 `{Top,Left,Bottom,Right}` 两种镜像解二选一。会做一个"边角探针"窗口，你与原版 UI 对照一次即可定案。
2. **后缀修饰步骤的按压时机**（`剪切=[右↑,左键]` vs `拷贝=[右↑]`）：按压是必须在画线前、还是画完仍按住再按即可。做一个二选一的对照实验。
3. **`VSCROLL:n` 量级分档阈值**（原版存了 1/11/12/13）。
4. **CGEventTap 是否还需"输入监控"权限**（除辅助功能外），实测决定。
5. 左键触发"不阻止点击"的确切条件。
6. 跨屏手势的坐标归一与边界处理。

## 7. 测试与验收

- **单元测试**：配置编解码往返、旧配置导入快照、键名→CGKeyCode 表、边角位掩码、简单手势方向归约、DTW 阈值回归。
- **手动验收清单**：按第 1 节逐条对照原版行为。
- **稳定性**：连续 200 次手势无泄漏/无按键残留；运行中撤销辅助功能授权立即安全退出拦截；睡眠唤醒后 tap 自动恢复。
- **对照期注意**：原版与 zWGestures 不能同时运行（都抢全局鼠标事件），测试时需退出原版。

## 8. 明确不做 / 边界

- 不复制、不打包原版任何二进制、字体、图标、资源或激活码；只做**配置格式互通**（数据可读）。
- 不复刻 Windows 版特有功能：自定义菜单、Lua、Cmd 脚本、运行/激活应用程序。
- 不做 App Store 上架（沙箱与全局输入拦截互斥）。
- 不实现原版的注册/试用校验（全部功能直接可用）。

## 9. 需要你配合的事

1. 首次运行时到「系统设置 › 隐私与安全性 › 辅助功能」勾选 zWGestures（以及可能需要的"输入监控"）。
2. 第 6 节第 1、2 项需要你对照原版 UI 各确认一次（各 1 分钟）。
3. 对照测试期间退出原版 WGestures。
4. 钥匙串里已存在 `Developer ID Application: Chaoyang Xie (P3YTJX7552)`：如果不是你本人的证书，就按你选的方案新建自签名证书；P0 开工前我会再确认一次。
