# 事故调查与已知陷阱（完整版）

> 四起严重故障的完整调查（整机输入冻结、主 actor 隔离家族、一次 47 秒卡死、一次一分钟卡死），以及拆分前 ROADMAP §8「已知陷阱」的全文。**结论级的清单在 ROADMAP §8**，这里放证据、崩溃栈与排查过程。
>
> **这一份是 `ROADMAP.md` 拆分出来的参考文档**（2026-10-06 搬迁，内容原样保留）。
> 路线图里对应的章节只留结论与链接 —— 那里是「接手开发要读的」，「怎么查出来的」都在这里。

---

## 13. 2026-09-29 整机输入冻结事故（已修，发布阻断级）

**现象**：授权辅助功能之后，整台 Mac 的键盘完全失效、点击几乎无响应，但鼠标右键画手势**仍能被识别**、
屏幕上的视频**仍照常播放**；没有任何可靠出路，只能按住电源键强制关机。

**证据**（全部来自本机日志，可复查）：

| 证据 | 内容 |
|---|---|
| 崩溃报告 | 该时刻**没有** zWGestures 的 `.ips` —— 不是崩溃，是卡住 |
| `/Library/Logs/DiagnosticReports/ResetCounter-*.diag` | `Boot faults: btn_rst,finger_reset force_off`，确认强制断电 |
| App 自身日志 | 会话 A 内事件 tap 被系统以 `kCGEventTapDisabledByTimeout`（type `-2`）摘掉 **42 次**（22:56:12–23:05:33） |
| 对照 | 同一二进制、同一配置，重启后的会话 B 为 **0 次** |
| 静默 | App 日志在 23:05:53 中断，直到重启后的 23:13:08 才恢复（约 7 分钟） |

**根因链**：`EventTapController` 用的是 `.cgSessionEventTap` + `.headInsertEventTap` + `.defaultTap`，
且事件掩码里含 `.keyDown`。事件 tap 的回调是**同步**的 —— 系统必须等回调返回才投递该事件。
鼠标移动可以被窗口服务器合并，回调慢只会让轨迹变粗；**键盘事件无法合并**，所以回调一旦错过系统的
截止时间，打字就整体失效（鼠标粗粒度手势仍能被识别，视频不受影响 —— 与现象逐条吻合）。
更糟的是旧实现在超时分支里**立刻无条件重新启用** tap，于是系统被反复拖回一个跟不上的 tap。

**为什么偏偏是那次会话**：未能确证，不再猜。当时的加重因素包括：系统正在给这个「新 App」建索引
（CoreSpotlight donation、UIIntelligenceSupport agent 连接）、上百个应用在跑、同时有视频在播；
以及主线程与 tap 线程共享三把锁（`AppDirectory.refresh` 每 3 秒持锁重建 `GestureRecognizer` 并整份
拷贝 `WGConfig`；`previewName` 每 50 ms 在 tap 线程上拷贝整个 `RecognitionContext`）。

**已做的修复**：

1. **App 退出键盘的同步路径**（关键）。事件掩码下沉为 ZWGCore 的 `EventTapMask` 并去掉 `.keyDown`；
   急停快捷键改用 `NSEvent` 全局 + 本地监听（listen-only，**结构上无法吞事件**）。从此回调再慢，
   也不可能让打字失效。
2. **tap 自我保护**。新增 ZWGCore 的 `EventTapHealthPolicy`：60 秒窗口内超时超过 3 次即**主动拆除**
   tap 并明确告知用户（弹窗给出 保持停用 / 重新启用）；其余超时改为**退避 0.5 秒**后再启用。
   恢复必须是用户的显式操作，**不自动重启、也不启动权限轮询** —— 否则等于又把系统拖回慢 tap。
3. **回归防线**。`EventTapMaskTests` 锁死「掩码里绝不含键盘类型」，与
   `scripts/check-appkit-isolation.py` 同属「单测表达不了的约束」。

**仍待观察**（未做，见 §7）：tap 线程上的整份配置拷贝、主线程锁竞争与 `AppDirectory` 刷新频率。
这些是性能隐患，不是冻结路径本身，但它们决定了回调会不会慢到触发超时。

**教训**：`headInsertEventTap` + `.defaultTap` + 键盘掩码 = 把自己的进程插进**全系统每一次按键的关键路径**。
一个后台工具可以慢到让自己不可用，但**不能慢到让别人不可用**；只要还想捕获某类事件，就必须先回答
「回调超时的时候，用户还能不能正常用这台电脑」。

---

---

## 21. 2026-10-06：按「形状结构」判别手势，以及「松手后偶尔慢半拍」的根因

### 用户报了什么

1. 截图里的手势是「竖很长、横很明显」的 **下→右**（一眼就是「关闭」），但不被识别。
2. 三段手势（竖→横→竖）也一样：**横的长度**决定它被认成 `Enter` 还是 `Minimize`。
3. 上次整机冻结之后，感觉「画手势时有一丁点迟滞」；追问后确认是**偶尔**「松手后动作执行慢半拍」。

### 一、识别器在看「比例」，而不是在「形状」

先用真实配置的定义复算（`Close` = 屏幕上的「下 50 → 右 50」，阈值 0.10）：

| 画出来的形状（屏幕坐标） | 旧度量的结果 |
|---|---|
| 下 467 → 右 210（V:H = 2.2，就是截图） | 到 `Close` = **0.109 > 0.10 → 不识别** |
| 下 200 → 右 100（V:H = 0.5，横比竖长一倍） | 到 `Enter` = **0.086**，到 `Minimize` = 0.085，两条都过阈值 → 列表靠前的 `Enter` 胜出 |
| 下 100 → 右 200 → 下 100（`Enter` 的形状，中间横 2× 竖） | 到 `Enter` = **0.120 > 0.10 → 不识别** |
| 同一条 L，画到 V:H = 2.2 时到「粘贴」（一条直线）的距离 | **0.075** —— 比到它自己的定义（0.109）还近 |

根因：`StrokeNormalizer.normalize` 把**整条笔画按总弧长缩放到 1** 再逐点比欧氏距离。于是「每一段
占全长的比例」被当成了形状本身。两个后果：① 比例一偏就漏识别；② 某一段特别长时，其余段的方向
信息被淹没 —— `Enter`/`Minimize`/`Fullscreen` 这三条方向完全不同的手势会挤到 0.085~0.12 之间，
胜负落到「谁排在列表前面」上。

### 二、新度量：`StrokeStructure`（结构描述子）

`ZWGCore/Recog/StrokeStructure.swift`：

1. **一次遍历**同时完成：校验有限性、算总长与外接矩形、按**固定点数**（48）抽取分析样本 ——
   成本因此与笔画点数**无关**（拦截器线程上原本 200 点要 1062 µs）。
2. 移动平均（窗口 5，**点数太少时跳过**，见下面的坑）→ Ramer–Douglas–Peucker 简化
   （容差 = max(8 点, 0.09 × 外接对角线)）→ 合并夹角 < 25° 的相邻段 → 丢掉占比 < 4% 的碎段。
3. 得到 `[Segment{方向, 长度占比}]`。两条结构之间的距离 = 段序列上的对齐代价：
   匹配一段 = `0.85 × 方向差(角度/90°) + 0.15 × 长度占比差`，**留下一段未匹配 = 1.0**，
   最后除以较长的段数。方向权重 0.85 是实测选的（见下）。
   - 一份数、一段对一段、段数相同时取对角（**无 DP、无分配**）；
   - 段数不同才走小规模 DP，且用 `withUnsafeTemporaryAllocation`（典型 2×3 表落在栈上）。
4. **闭环手势走原来的弧长度量**：存储轨迹的**起点与终点相距 ≤ 10% 总长**即判定为「画出去再原路
   返回」（`Web 搜索` / `退格` / `删除` / `Terminal` / `Activity Monitor`）。这些手势的「细长环
   命中、正圆不命中」容差是当年用实测调出来的（`GestureRecognizerTests` 钉着），结构度量会把
   一个椭圆拆成 4 段以上，等于悄悄砍掉那份容差 —— 与其牺牲它，不如保留第二套度量。
   **判重与选取规则一行没动**：修饰键多者优先 → 列表靠前优先 → 距离兜底。

标定与实测（2026-10-06，`make test` 281→284 项）：

| 事实 | 数值 |
|---|---|
| 截图那条 L 到 `Close` | 0.109 → **0.063**（阈值 0.15） |
| 竖横比 0.4~4.0 的 L | 全部命中 `Close`，且 `Enter`/`Minimize`/`Fullscreen`/`Paste` 一律不通过 |
| 三段「下→右→下」，中间横 0.4×~3× | 全部命中 `Enter` |
| L(1:8)（极端比例）到 `Close` | 0.153 → **0.122** |
| **真正不同的形状**之间最近的一对 | **0.283**（`Enter` vs `Fullscreen`）；同形重复照旧由列表顺序裁决 |
| 手绘失真回归（每段 0.5~2.0×、±8°、2px 抖动，固定种子） | 每条折线手势都过自己的阈值 |
| 同一个发生器下用旧度量复算（Python 复刻，更狠的信封 0.35~2.5×/±12°/2.5px） | 命中率 21% → 86% |

### 三、写这个度量时踩到的三个坑（都会静默地毁掉识别）

1. **别对稀疏折线做移动平均。** 存储定义只有 2~4 个顶点，窗口 5 的均值会把中间那个顶点平均到
   弦上 —— 一个 3 点的 L 会变成**一条直线**。实测「关闭」对自家定义的距离因此变成 0.252。
   现在点少于 `max(8, 窗口 × 3)` 时直接跳过平滑。
2. **逐候选的堆分配很贵。** 一开始每条候选都 `new` 一个 DP 表，32 条候选就是每次识别 32 次分配；
   加上一级/二级/对角三种短路之后，`scoredCandidates` 从 1256 µs 回到 **376~395 µs**
   （§19 记的旧度量 403 µs 是当时的单批均值，与现在的「多批取最小」不能直接相减，但同一量级 ——
   结论是这次改度量**没有**让热路径变慢）。
3. **分析点数必须封顶。** 不封顶时成本随笔画点数线性增长（800 点比 50 点慢 5.3 倍）；封顶后
   比值 1.96，形状信息一点没少（RDP 容差本来就远大于采样间距）。

### 四、「松手后偶尔慢半拍」：主线程上多出来的那份索引构建

`a65d89b`（tap 线程性能硬化）把所有手势的触发/形状**预先算好**，做法是让
`InputCoordinator.updateRecognition` 构建整份 `RecognitionIndex`。在此之前它只是在主线程上存一份
context（几乎零成本）。而它的调用点有两个：

- 配置变化（保存 / 导入 / 换目标）—— 罕见，原来的设计意图；
- **`AppDirectory.onChange`：每 3 秒一次的应用目录刷新，以及每次切换/启动/退出应用**。

于是「松手 → 识别完成 → 主线程执行命令」这条路上，每 3 秒会多出一段主线程忙活。赶上就慢半拍，
「偶尔」也吻合。修复：

1. **拆开两条路径**：`applyConfiguration`（规则变了才构建索引，且在专用串行队列上构建）与
   `updateTargeting`（只换 context，复用已发布的索引）。`RecognitionIndexCache` 用
   `WGConfig: Equatable` 兜底「内容没变就不重建」，`buildCount` 把它变成可观测的量。
2. **tap 停用按类型区分**：`tapDisabledByUserInput` 立刻重新启用（恢复冻结前的行为，它不是
   「回调慢」的信号）；只有 `tapDisabledByTimeout` 才退避 0.5 秒并在窗口内累计到上限后放弃。
3. **可观测**：调试面板新增 `idx rebuilds` 与 `交接 X ms / 最差 Y ms`；「识别到执行」超过 50 ms
   记一条 warning。这样「是否修好」有读数，不靠感觉。

### 五、刻意没做 / 已知问题

- **四个自由形状手势互相抢**：`重新载入` / `下一应用` / `上一个应用` / `其他窗口` 的形状本来就
  是同一种「∧」，新度量下两两距离 0.016~0.052（旧度量 0.022~0.068），依旧由列表顺序裁决。
  这是既存事实，换度量治不好；要治只能改形状或加修饰键。
- `Terminal` / `Activity Monitor` 是原版自带的**退化重复定义**（零宽竖向折返），本来就不可用。
- **录制器仍然用弧长校验**（`WGStrokeRecorder.simpleFormTolerance = 0.06`，未改）：它问的是
  「画出来的东西几何上像不像那几条网格直线」，而结构度量问的是「会不会被识别成那个形状」——
  后者会把真正的圆弧也判成两段折线（`curvedStrokesStayFreehand` 就是钉这个的）。代价是手画一条
  竖横比很大的 L 会被存成自由形状（不再吸到网格）：**只是不好看，识别两种都正常**。

---

---

## 22. 2026-10-06 事故二：Web Search 手势 → 主线程卡 47 秒 → 菜单栏崩溃

### 现象

用户画了一个「竖线 + 绕在竖线旁边的环」，被识别成 `Web Search`；**后续动作没有触发**，
界面卡住一段时间后应用自动退出。

### 证据（全部可复查）

| 证据 | 内容 |
|---|---|
| 崩溃报告 | `~/Library/Logs/DiagnosticReports/zWGestures-2026-10-06-024535.ips`，主线程 `EXC_BAD_ACCESS / SIGBUS (KERN_PROTECTION_FAILURE at 0x1800001120)` |
| 崩溃栈 | `@objc StatusItemController.menuWillOpen(_:)` → `_checkExpectedExecutor` → `SerialExecutorRef::isMainExecutor()` |
| 应用日志 | 02:44:46.086 命中「Web Search」；**之后没有** `执行手势「Web Search」`；02:45:05/06/07 又命中三条手势，也一条都没执行 |
| 对照 | 02:44:34 与 02:44:38 的 `Backspace` 命中后 50~60 ms 内都有 `执行手势` 日志 |
| 崩溃报告的 HIE 线程 | `SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION`，时间戳 **02:44:46.139** —— 系统判定应用无响应的时刻，比那次识别晚 53 ms |
| 崩溃 captureTime | 02:45:33（主线程那时正在弹状态栏菜单） |

### 两个独立缺陷叠在一起

**① 崩溃：同族问题的第三个入口 —— 非 `override` 的 AppKit 协议实现**

`StatusItemController` 是 `@MainActor`，而 `menuWillOpen(_:)` 是 `NSMenuDelegate` 协议实现，
于是入口被插入「我在主 actor 上吗」的运行时检查；AppKit 从状态栏菜单的**场景路径**
（`FrontBoardServices scene:handlePrivateActions:` → `NSSceneStatusItem _beginExpandedInterfaceSession`
→ `popUpStatusItemMenu`）调用它时，那个检查自己 fault。与 09-28 的两次（Timer block、
`TrailView.isFlipped`）同族，都是 `SerialExecutorRef::isMainExecutor` 自己 fault。

为什么没被守卫拦住：`scripts/check-appkit-isolation.py` 当时只匹配带 `override` 的
NSView/NSWindow 覆写，**协议实现是它的盲区** —— 而 `menuWillOpen` 正是 09-30 修「菜单栏状态
不刷新」时新加的（那次真正的修复是给 `engine.onStateChange` 赋值，这个回调只是「兜底」）。

修法：**不再实现 `NSMenuDelegate`**，改成推送式刷新（`onStateChange` + 每个菜单动作后 +
应用被激活时）；守卫补上协议回调这一类（`menuWillOpen` / `menuNeedsUpdate` / `menuWillClose` /
`validateMenuItem`，见脚本注释里的完整崩溃栈）。
代价：在「系统设置」里改开机自启、且期间应用从未被激活时，那一条菜单文案会短暂过期 ——
点一下就刷新。宁可这样，也不要一个会偶发崩溃的回调入口。

**② 卡死：主线程上的同步辅助功能（AX）调用**

`ActionContextProvider.windowTitle(for:)` 为了填 `WG_TARGET_WIN_NAME`，**每执行一次手势都在主线程
同步调用 `AXUIElementCopyAttributeValue`**。这是**跨进程**调用：目标应用一旦无响应（当时前台是
浏览器），它就会阻塞数秒到数十秒（系统默认 6 秒超时，对「无响应」的应用会更久）。卡住的时刻、
以及「命令一律没执行」，都与它吻合 —— 命令压根没走到执行那一步。

修法：`WGCommandPlan.needsTargetWindowTitle` —— 只有 **shell 脚本**用得到窗口标题，
其余动作（按键序列 / 系统功能键 / Web 搜索）一律不问；真要问时放到后台 `Task.detached`，
并先 `AXUIElementSetMessagingTimeout(0.25)` 把单次询问限时。
写进代码注释的原则：**执行路径的同步段里不允许出现跨进程调用。**

这条大概也是 2026-10-06 那次「偶尔慢半拍」的大头 —— §21 第四节修的主线程索引重建是真的，
但每次手势同步问一次 AX 更贵。调试面板新增的 `交接 ms` 正是用来抓这种等待的（这次它自己也没
打出来，因为主线程卡在 `run()` 里）。

### 留下的守卫

- `scripts/check-appkit-isolation.py`：新增「AppKit 协议回调」这一类检查（原先只查 `override`），
  并把两份崩溃报告写进脚本注释，让「为什么不能这么写」不依赖记忆。
- `TargetWindowTitleRequirementTests`（2 项）：只有 shell 脚本需要窗口标题。
- `StatusItemController` 的类注释：写明**不要**再实现 `NSMenuDelegate` 这类协议。

### 一条可以复用的判断方法

「识别成功但动作没执行」这类报告，先查**日志里成对出现的两行**：`命中手势「X」`（tap 线程）
与 `执行手势「X」`（主线程）。缺后者 = 主线程被占住或没轮到，而不是识别器的问题。

---

---

## 23. 2026-10-06 事故三：Web 搜索再次崩（急停监听的闭包继承了主 actor 隔离）

### 现象

装上 §22 的修复后，用户再次报「又崩溃了」。截图里轨迹是绿色、显示 `Web Search`，
调试面板显示 `交接 1.0 ms / 最差 1.6 ms`、`idx rebuilds 1` —— 也就是说 §21 的修复在正常工作，
这次是**另外两个**缺陷。

### 证据

| 证据 | 内容 |
|---|---|
| 崩溃报告 | `zWGestures-2026-10-06-030632.ips`（pid 81257 = §22 修复后那份），主线程 `EXC_BAD_ACCESS / SIGSEGV (KERN_INVALID_ADDRESS at 0x0)` |
| 崩溃栈 | `closure #1 in EngineController.startPanicMonitors()` → `swift_getObjectType` → `swift_task_isMainExecutorImpl` → `isMainExecutor()`；由 `AppKit GlobalObserverHandler` ← `HIToolbox DispatchEventToHandlers` 调用 |
| 日志 | 03:05:32.829 命中「Web Search」，之后没有 `执行手势「Web Search」`；崩溃报告的 HIE 线程标记 **03:05:32.860** |
| 对照（同一分钟） | 03:04:57 Backspace、03:05:01 Forward、03:05:04 Back、03:05:09 重新载入 —— 四个手势全都正常执行 |
| 粘贴板 | 事发时通用粘贴板里是一张图：`«class PNGf» 2.5MB · TIFF picture 20.4MB · «class 8BPS» 9.8MB · BMP 20.4MB · JPEG 0.56MB …` |

### 两个缺陷（都在同一条路径上，所以每次都只发生在 Web 搜索）

**① 崩溃：急停快捷键的全局 `NSEvent` 监听闭包继承了主 actor 隔离**

`NSEvent.addGlobalMonitorForEvents(matching:handler:)` 的 handler 参数是普通的
`@escaping (NSEvent) -> Void`（**不是** `@Sendable`）。写在 `@MainActor` 方法里的**闭包字面量**
会继承那份隔离，于是编译器给 AppKit 的回调插一个 `MainActor.assumeIsolated` thunk；AppKit 从
HIToolbox 的事件派发路径调用它时，那个检查自己 fault —— 与 09-28 的 Timer block、10-06 的
`menuWillOpen` 是同一族，这已经是**第四次**。

**把它点燃的是我们自己合成的 ⌘C**：Web 搜索为了读选中文字会合成 ⌘C，而急停监听器当时没有
过滤合成事件 —— 等于自己踩自己的雷，所以两次事故都紧随 Web 搜索手势。

修法：处理器改成**文件作用域的非隔离函数**（不继承隔离 → 不插检查），通过一条通知把
「匹配上了」交给主 actor 处理；并且**忽略我们自己合成的按键**（合成事件永远不该能触发急停）。

**② 卡死：粘贴板的深拷贝**

`WebSearchRunner` 为了「搜选中文字」，原来先把整个通用粘贴板**深拷贝**
（`PasteboardSnapshot.capture()` → `NSPasteboardItem.copy()`，而 `copy()` 会把每一项的**每个表示**
都实体化），再合成 ⌘C、读完、还原。事发时粘贴板里是一张 70+ MB 的多表示图片 → 主线程卡约一分钟。
同一分钟里其它四个手势都正常执行，正是因为只有 Web 搜索会碰粘贴板。

修法：
- 选中文字优先走**辅助功能 API**（`AXSelectedText`，后台 `Task.detached`、限时 0.25 秒，
  **完全不碰粘贴板**）；
- 兜底才用 ⌘C，而且**只有当粘贴板里本来就装着文本时才用**（图片剪贴板一根汗毛都不碰），
  150 ms 后把原来的文本写回；
- 删掉 `DispatchQueue.main.asyncAfter` 那个闭包（与 09-28 崩过的 Timer block 同族），
  `KeyCaptureView` 里同样的 GCD 写法也一并改成 `Task { @MainActor in … }`。

### 留下的守卫

- `scripts/check-appkit-isolation.py` 新增两类检查（脚本注释里附了这次的崩溃栈）：
  - `addGlobalMonitorForEvents` / `addLocalMonitorForEvents` **必须传函数引用**，不能写闭包字面量；
  - `DispatchQueue.main.async` / `.sync` / `Timer.scheduledTimer` / `Timer(timeInterval` 一律禁止，
    改用 `Task` 循环。
  已用一份「故意写错」的样例手工验证过：三个坏写法全被拦下，注释里提到这些名字不会误报。
- `run()` 的每一步（规划动作 / 构造上下文 / 取窗口标题 / 执行动作）都计时，任何一步超过 50 ms
  记一条 warning —— 前两次卡顿都只能靠推断定位，下次日志会直接点名。
- Web 搜索的日志会写明「已取到选中文字」还是「没选中文字，按空查询」，这样下次就知道
  AX 这条路在浏览器里到底通不通。

### 可以推广的教训

**「闭包写在哪里」和「闭包体里写了什么」一样重要。** 只要闭包**字面量**出现在 `@MainActor`
上下文里，并被交给**非 `@Sendable`** 的回调（AppKit 的 handler、`DispatchQueue.main.async`、
`Timer`），就会多出一个运行时隔离检查点，而它在某些 AppKit/GCD 调用路径上会自己 fault。
本项目已经因此崩了四次。两个正确写法：**传函数引用**（文件作用域或 `nonisolated`），
或者让闭包显式 `@Sendable` 并把隔离状态通过 `Task` 跳着访问。

---

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

- 🔴 **同一个雷区的第三条路径：`@MainActor` 类型实现的 AppKit 协议回调（不是 `override`）。**
  协议实现同样继承类的隔离、同样在入口插检查，而 AppKit 会从**状态栏菜单的场景路径**调用它们。
  2026-10-06 崩在这里：

  ```
  crash report zWGestures-2026-10-06-024535.ips
  EXC_BAD_ACCESS / SIGBUS in swift_task_isMainExecutorImpl
    _checkExpectedExecutor
    zWGestures  @objc StatusItemController.menuWillOpen(_:)   ← 崩在这里
    AppKit      -[NSMenu _sendMenuOpeningNotification:]
    AppKit      -[NSSceneStatusItem _beginExpandedInterfaceSession:]
    FrontBoardServices -[FBSSceneObserver scene:handlePrivateActions:]
  ```

  **守则是「干脆别实现它」**：菜单文案改成推送式刷新（`onStateChange` + 动作后 + 应用激活时），
  而不是在打开菜单的那一刻去问。`check-appkit-isolation.py` 现在也检查
  `menuWillOpen` / `menuNeedsUpdate` / `menuWillClose` / `validateMenuItem` 这四个名字；
  如果再实现它们，必须标 `nonisolated`，并且**只碰非隔离状态**（碰实例状态会引发隔离错误）。
  完整经过见 §22。

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
- **手写测试 fixture 容易写反方向**。用参考配置里的 `P` 原值，或按真实编码规则生成。
