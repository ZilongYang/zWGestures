# zWGestures 路线图与接手说明

> **明天继续开发，从这里开始读。** 本文件是唯一的计划与进度来源；
> `README.md` 里是构建命令与开发约定。
> 最初批准的那份实施方案原样存档在 [`PLAN.md`](PLAN.md)（只作历史参考，不再更新）。


> **这份文档只放四件事**：目标、已完成、下一步、结论级的经验与坑。
> 「怎么查出来的」按主题拆到了 [`docs/reference/`](reference/)（见文末 §24 文档地图）。
> 章节号**刻意保持不变**：全仓库约 40 处代码/测试/脚本注释都按 `§N` 引用这里。

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
| 修复 | **整机输入冻结**（2026-09-29，发布阻断级）：tap 退出键盘同步路径 + 超时主动停用 + 掩码回归测试 | ✅ 已修复并装上（详见 §13）；修复后行为待实机确认 |
| 开源 | **出厂默认手势包**：48 条中文手势随 App 发布，没装过原版的人开箱可用（§16） | ✅ 已生成并提交；新增 12 项单测，CI 断言产物路径 |
| 开源 | **更新后授权失效的显式提示**：区分「还没授权」与「更新弄丢了」，后者弹一次说明（§13 相关） | ✅ 已实现并装上；标记写入已实机验证，新增 6 项单测 |
| 开源 | **Gatekeeper 实测与安装说明**：5 项逐条实测 → [`INSTALL.md`](INSTALL.md)；顺带查出 `make dist` 的两个硬要求（§17） | ✅ 已完成；其中 1 项（点「仍要打开」）留到全新账号验收 |
| P9 | 开机自启：`SMAppService` 优先 + **LaunchAgent 兜底** + 菜单栏开关 | ✅ 已实机验证（**重启后自动启动**：开机 22:59:28，5 分钟后进程已是 `/Applications` 那份、无 LaunchAgent 兜底、无新崩溃） |
| 修复 | **识别改成按「形状结构」判别**（2026-10-06）：L 形不再因横不够长而漏识别、三段手势不再按横的长短在 Enter / Minimize 之间跳 | ✅ 已实机验收 + 284 项单测全绿（提交 `26d6a9d`，详见 §21） |
| 修复 | **「松手后动作偶尔慢半拍」**（2026-10-06）：规则变更与目录刷新拆开、索引构建移出主线程；顺带让用户输入导致的 tap 停用立刻恢复 | ✅ 已实机验收（提交 `71d2fb0`，详见 §21） |
| 修复 | **主线程被辅助功能调用卡死 + 菜单栏崩溃**（2026-10-06 事故二，发布阻断级）：Web 搜索手势把主线程卡 47 秒、随后在 `menuWillOpen` 上崩溃 | ✅ 已修复（详见 §22）；`check-appkit-isolation.py` 扩到协议回调，新增 2 项单测 |

**可以日常使用的程度**：右键基本手势全部工作 —— 识别、执行命令、轨迹与手势名实时显示、
命中变绿淡出、未识别不弹菜单、急停快捷键；**并且改手势不再需要手改 JSON**：
浏览/搜索/改名/删除、重画形状（全屏录制）、改动作、按顺序调优先级、单独禁用某条、
给某个应用新建手势集（自己的优先、其余继承全局）、偏好设置（超时/外观/目标模式）都在界面里，
保存前自动备份。

「✅ 已实机验证」= 在本机用 `make run-settings` 实际操作过并确认行为符合预期。

## 3. 下一步（按建议优先级）

> **2026-10-06**：0.2.0 与 0.3.0 都已发布（发布记录见 [CHANGELOG](../CHANGELOG.md) 与
> [`release-notes/`](release-notes/)），**下面从第 1 项开始列的是「还没做的」**；
> 发版前那两轮人工回归的逐项清单留在当次的发版清单里，不在这里重复。
> 触发矩阵与边角/滚轮触发仍然**主动押后**（依据见第 6 项）。

### 1~2. ✅ 人工回归与两次发版（均已完成）

两轮实机回归（识别度量 / 卡死回归、双语 / 改名回归）逐项过完并通过，逐项清单在当次的发版清单里：
[`RELEASE-CHECKLIST-0.2.0.md`](RELEASE-CHECKLIST-0.2.0.md)、
[`RELEASE-CHECKLIST-0.3.0.md`](RELEASE-CHECKLIST-0.3.0.md)。
`v0.2.0`（修识别度量 + 三起崩溃/卡死）与 `v0.3.0`（界面中英双语 + 手势名中文化 + 两份默认包）
都已发布，站点线上版本号同步刷新。

### 3. 0.1.0 遗留的站点与验收尾巴 —— **这就是下一步**

> ✅ **站点已重新部署（2026-10-06 14:29）**：线上版本号已是 `v0.2.0`，`index.html` 与仓库
> **逐字节一致**（拉回来比对 sha256），4 张素材也一一比对一致，HTTP→HTTPS 301 正常。
> 顺带更正一处我写错的做法：**这台服务器没有 rsync**，用的是 `tar` over SSH +
> 远端 `chown root:root` / `chmod 644,755`（细节在 `docs/private/local-deploy.md`，
> 公共说明在 [`site/README.md`](../site/README.md)）—— 直接 `tar` 上传会把本机的
> `501:staff` 与 `600` 权限带上去，Web 服务器读不到会返回 403。

- ✅ 站点重新部署（只为了那行版本号；下载按钮走 `releases/latest`，本来就已指向 0.2.0）。
- **404 页**（你已确认要做）：`site/404.html`，与站点同风格、单文件。它属于站点内容，
  换掉它**不需要改 nginx 配置**。⚠️ 注意远端 **已经有一个 130 字节的 `404.html`**
  （面板/服务器默认页，不在仓库里）：部署用 `tar` 是**增量覆盖、不删除**，所以那个文件还在 ——
  写好新的 `site/404.html` 上传即可覆盖它。
- **全新 macOS 用户账号验收**：挂 dmg → 拖进 Applications → 按 `docs/INSTALL.md` 放行
  Gatekeeper → 授权辅助功能 → 确认**开箱就有 48 条中文手势**、画「上」触发拷贝。
  这一步同时完成 Release 配置的真机回归，并顺手拍 `site/assets/install-gatekeeper.png`；
  拿到图后把 `site/index.html` 安装那节里注释掉的 `<figure>` 取消注释。
- （可选）**`site/assets/` 长缓存头**：只用 `expires 30d;`，**不要**用
  `add_header Cache-Control` —— nginx 的 `add_header` 在子级 location 会覆盖父级同类指令，
  那会把站点现有的 `Strict-Transport-Security` 头在素材响应上抹掉。
- **全新 macOS 用户账号验收**：挂 dmg → 拖进 Applications → 按 `docs/INSTALL.md` 放行
  Gatekeeper → 授权辅助功能 → 确认**开箱就有 48 条中文手势**、画「上」触发拷贝。
  这一步同时完成 Release 配置的真机回归，并顺手拍 `site/assets/install-gatekeeper.png`；
  拿到图后把 `site/index.html` 安装那节里注释掉的 `<figure>` 取消注释。
- （可选）**`site/assets/` 长缓存头**：只用 `expires 30d;`，**不要**用
  `add_header Cache-Control` —— nginx 的 `add_header` 在子级 location 会覆盖父级同类指令，
  那会把站点现有的 `Strict-Transport-Security` 头在素材响应上抹掉。

### 4. P7 验收与加固：多屏、全屏应用、长时间运行、连续快速手势

发版之后最该做的一项 —— 真实问题会在这里暴露。有些项我这边的环境测不了（只有单屏、
无法模拟连续快速手势），需要你实测：多显示器之间画手势、在**全屏应用**（视频/游戏/演示）里画、
连续快速画多次、长时间挂着不重启；调试面板的 `state`/`tap`/`events`/`replays` 四行是主要判据。

### 5. P8 的一部分（按价值排）

手势**分组**（原版 `Groups`，本机配置为空、on-disk 结构未知，需要先勘察）、
拼音搜索（手势多了以后有用）、动画回放。

### 6. 触发矩阵编辑 + 边角/滚轮触发（P5 剩余）—— 押后，但两者应一起做

实测用户配置的 42 行矩阵里 **39 行是边角签名**，只有 3 行是鼠标键，而唯一在用的右键那行
本来就是启用的，所以现在做矩阵编辑器几乎不产生实际效果。边角/滚轮手势同理：用户配置里有
12 条这类手势（已默认隐藏），实现这两种触发后它们立刻可用。
⚠️ 已知缺陷：`areModifiersSatisfied` 对 `HSCROLL` 也拿 `deltaY` 比对（横向修饰键会被竖向滚动
满足），所以界面上**不提供**左右滚修饰键。做 P5 时应一并修掉。

### 7. 完整可视化编辑器

拖放建手势、所见即所得的修饰键/触发方式编辑。

### 8. 本次顺带发现的小项（都不阻塞发版，想做时单开）

1. **录制器的拟合残差**：`WGStrokeRecorder.simpleForm` 仍用弧长校验，所以手画一条竖横比很大的
   L 会被存成自由形状（只是不好看，识别两种都正常）。要让它吸到网格，需要给 `StrokeStructure`
   加一项「原始点相对简化折线的平均偏差」，并用它把「真正的曲线」与「画歪了的直线」分开。
2. **四条自由形状手势互相抢**：`重新载入` / `其他窗口` / `下一应用` / `上一个应用` 的形状本来就是
   同一种「∧」（两两 0.016~0.052），任何度量都分不开；要治只能改形状或加手势修饰键。
3. **两条退化的重复定义**：`Terminal` / `Activity Monitor` 的 `P` 是零宽竖向折返，本来就不可用
   （原版自带），想在界面里提示「这条形状无意义」的话有现成的冲突检测可复用。

## 4. 常用命令

```bash
cd /path/to/zWGestures

make build      # xcodegen generate + xcodebuild（会自动解锁签名钥匙串）
make test       # 运行 ZWGCore 的单元测试（230 项）
make run        # 构建并启动
make run-debug  # 构建并启动，同时打开调试面板（ZWG_DEBUG_HUD=1）
make install    # 构建并把 .app 拷到 /Applications（开机自启需要固定路径）
make info       # 打印产物的架构与代码签名
make clean
```

**改完代码后务必 `make test`**，测试里有多条针对参考配置的强回归断言。

> **术语：参考配置（reference configuration）**
> 早先这些回归断言直接读本机安装的原版 WGestures 配置（当时的说法是「真实配置」）。那样在
> 没有装原版的机器上会整条跳过，等于没测。现在改成读**随仓库提交的 fixture**：
> `ZWGCore/Tests/ZWGCoreTests/Fixtures/legacy/2.3.3/`（原版 2.3.3 的一份脱敏样本，含
> `gestures.json` / `prefs.json` / `Version`）。下文出现的「参考配置」都指这份 fixture，
> 「参考偏好」指其中的 `prefs.json`。改动 fixture 会让多处硬编码基线失效，改之前先读
> `ZWGCore/Tests/ZWGCoreTests/Fixtures/README.md`。
> `ConfigTests.loadsALocalInstallWhenThereIsOne` 是唯一一条仍然读本机原版安装的**哨兵**测试，
> 没装原版时会被明确跳过。

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

原版 `config.json` / `prefs.json` 的字段语义已逐条勘察确认，**改配置层之前必读**：

- 字段名与原版**逐键对应**，`ConfigTests` 有一条「真实配置重新编码后与原文件逐键一致」的守卫；
- `StrokeStep.P` **就是绘制顺序**（第一对点是起笔点）；简单手势与任意形状**共用同一坐标系：y 轴向上为正**，
  解码成屏幕坐标时一律取反 y（踩过两次坑，见 §8 最后一条）；
- 本项目新增的扩展键（`Enabled`、`Language`、`NameRenameOffered`…）一律**只在非默认值时写出**，
  否则上面那条守卫立刻失败。

> 逐字段表格、`$type` 判别、触发矩阵的原始结构：见 [`reference/LEGACY-FORMAT.md`](reference/LEGACY-FORMAT.md)。

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

每条按「现象 → 怎么防」写；**证据、崩溃栈与排查过程在 [`reference/POSTMORTEMS.md`](reference/POSTMORTEMS.md)**。

### 渲染

- **叠加层必须「先清除」、且只失效轨迹矩形**。`needsDisplay = false` 只是不重画、**不清像素**：
  轮询一旦跨过 alpha 归零那一刻，最后那帧就永久留在屏幕上（现象是「绿色轨迹下有模糊残影」）。
  现在用 `TrailBounds` 算「上帧 ∪ 本帧」矩形，`setNeedsDisplay(rect)` + `draw` 开头 `clear(dirtyRect)`。
- **备份文件名绝不可复用**。淘汰逻辑按名字序删最旧的，复用名字会**把刚写的备份删掉、且不报错**
  （现象是「保存十几次后备份不再增加」）。时间戳必须**严格递增**；测试把时钟钉死在同一毫秒，
  让撞名路径**必然**发生。

### 🔴 AppKit 主 actor 隔离雷区（同一族故障的**四个入口**，已崩过四次）

| 入口 | 防法 |
|---|---|
| `@MainActor` 类型的 AppKit **覆写**（`isFlipped`、`hitTest`…） | 纯几何/谓词类覆写标 `nonisolated` |
| `@MainActor` 类型的 AppKit **协议回调**（`menuWillOpen`…） | **干脆别实现它**，改成推送式刷新 |
| `Timer` / `DispatchQueue.main.async` 的 block | 周期与延后执行一律用 `Task` 循环 |
| 把**闭包字面量**交给非 `@Sendable` 回调（如 `addGlobalMonitorForEvents`） | 传**文件作用域 / `nonisolated` 函数引用** |

`scripts/check-appkit-isolation.py`（`make lint`）会强制检查这几类写法 —— **新增任何 AppKit 入口前先跑一遍**。
`draw(_:)` 与鼠标事件处理**故意保持隔离**（走正常事件派发，实测没问题，且它们要读实例状态）。

### 其它

- **签名必须用独立钥匙串**：登录钥匙串里的私钥要靠 SecurityAgent 弹窗授权，无人值守的 `xcodebuild`
  会随机报 `errSecInternalComponent`。
- **`xcodebuild test` 在受限终端会因伪终端失败** → 单测放 `ZWGCore` SwiftPM 包，用 `swift test`。
- **不要混用时间基**：`CGEvent.timestamp` 与 `mach_absolute_time()` 不同基，相减会得到十几天的延时；
  事件时间戳统一用 `MonotonicClock`（`ProcessInfo.systemUptime`）。
- **锁方向必须单向**：`overlayLock` 可再取 `recognitionLock`，反之不行。
- **手写测试 fixture 容易写反方向**：用参考配置里的 `P` 原值，或按真实编码规则生成（§6）。
- **语言是进程级状态，而测试默认并行**：别在测试里切全局语言，用 `L10n.text(_:language:)` 这类纯函数接口。

## 9. 验证方式

- 单元测试：`make test`（230 项），其中多条**针对参考配置**的强回归断言。
  在没装原版 WGestures 的机器上会有 1 项哨兵测试被跳过，属正常。
- 实机验证：用户用右键画手势，读调试面板（`make run-debug`）的
  `state` / `gesture` / `target` / `executed` 四行，并观察屏幕上的轨迹与手势名。
- 崩溃报告在 `~/Library/Logs/DiagnosticReports/zWGestures-*.ips`
  （`.ips` 首行是 JSON 头、第二行才是正文，可用 Python 解析）。

## 10. 开机自启（P9 做法与坑）

`SMAppService`（系统登录项）+ LaunchAgent 兜底的双机制；**系统状态才是真源** ——
`prefs.json` 里的 `AutoStart` 只是镜像，菜单栏那一行永远读系统。这台机器上做过的一次性手工收尾
（清理旧 `~/Library/LaunchAgents/…plist`）也记在详情里。

> 见 [`reference/LAUNCH-AT-LOGIN.md`](reference/LAUNCH-AT-LOGIN.md)。

## 11. 应用图标

图标走 asset catalog（编译成 `Assets.car`）+ `CFBundleIconName`，**不用**老的 `CFBundleIconFile` + `.icns`：
macOS 26+ 的 AppKit 路径（「关于」面板等）用老形式会渲染成空白。重新生成：`make app-icon`。

> 见 [`reference/APP-ICON.md`](reference/APP-ICON.md)。

## 12. 设置界面（P6）

设置界面每一页的设计、当初的取舍、以及看起来奇怪但其实刻意的行为（不保存不落盘、
冲突橙色告警、按列表顺序定优先级、打开编辑器时暂停引擎…）。**改界面前读它**。

> 见 [`reference/SETTINGS-UI.md`](reference/SETTINGS-UI.md)。

## 13. 2026-09-29 整机输入冻结事故（已修，发布阻断级）

2026-09-29：拦截器回调捕获了键盘 + 超时后**无条件立刻重新启用** → **整机打字失效、只能强制关机**。
现在拦截器**完全不碰键盘**（急停改用不吞事件的监听）、超时先**退避 0.5 秒**、一段窗口内超时过多就
**主动停用自己**并弹窗说明。这是本项目最重要的一条教训：**后台工具不能慢到让别人不可用**。

> 完整证据链与「为什么偏偏那次会话」：见 [`reference/POSTMORTEMS.md`](reference/POSTMORTEMS.md)。

## 14. 明确的边界

- 不复制、不打包原版任何二进制、字体、图标、资源或激活码；只做配置格式互通。
- 不复刻 Windows 版特有功能：自定义菜单、Lua、Cmd 脚本、运行/激活应用程序。
- 不做 App Store 上架（沙箱与全局输入拦截互斥）。

---

## 15. 界面多语言（中/英）（**进行中，2026-10-06 起**）

四期已全部完成（机制与菜单栏 → 编辑器与弹窗 → 手势名中文化 + 两份默认包 → Info.plist 与发版）。
两条值得记住的设计：`L10n` 用 **`switch` 对照表**（漏一条编译不过）自建，不引 String Catalog；
手势名是**用户数据**、不参与界面本地化，所以默认包备两份且**除名字外逐键一致**。

> 见 [`reference/I18N.md`](reference/I18N.md)。

## 16. 出厂默认手势包（随 App 发布）

出厂默认手势取自原版的出厂集（48 条），**备两份**（`Defaults/zh-Hans`、`Defaults/en`，按界面语言播种），
名字来自原版自带的名字表；生成脚本 `make default-gestures`，产物**提交进仓库**
（只有装了原版的机器能生成，所以不进 `make build`）。

> 见 [`reference/PACKAGING.md`](reference/PACKAGING.md)。

## 17. Gatekeeper 实测结果与 `make dist` 的两个硬要求（2026-09-30）

Gatekeeper 实测：未签名 + 未公证 → 首次打开必须去「系统设置 › 隐私与安全性」点「仍要打开」；
**dmg 卷内直接运行会被系统移置到随机只读路径**（开机自启会因此失效，必须拖进「应用程序」）。
`make dist` 的硬要求、以及「固定文件名不能改」（站点按钮指向 `releases/latest/download/`）都在详情里。

> 见 [`reference/PACKAGING.md`](reference/PACKAGING.md)。

## 18. 介绍页素材（截图）怎么拍的

截图怎么拍的、用什么内容、**不得出现本机信息**（路径 / 手势名 / 账号），以及站点文案的取舍。

> 见 [`reference/SITE.md`](reference/SITE.md)。

## 19. tap 线程性能硬化（2026-09-29）

tap 回调落在**全系统输入的关键路径**上，所以给它定了耗时预算并加了性能测试；
实时手势名与轨迹分别持两把锁、方向单向（§8）。

> 见 [`reference/PERFORMANCE.md`](reference/PERFORMANCE.md)。

## 20. 介绍页部署、一次自查发现的疏漏、以及留在明天的事（2026-09-30）

介绍页部署：这台服务器**没有 rsync**，用 `tar` over SSH + 远端 `chown root:root` / `chmod 644,755`
（不然 Web 服务器返回 403）；还有一次自查发现的疏漏。

> 见 [`reference/SITE.md`](reference/SITE.md)。

## 21. 2026-10-06：按「形状结构」判别手势，以及「松手后偶尔慢半拍」的根因

识别从「按弧长归一化」改成「按**形状结构**」（拐角方向占 0.85 + 相对长度），
「画出去再原路返回」的闭环手势保留弧长度量；同一轮还修掉「松手后偶尔慢半拍」
（索引原来每 3 秒在主线程重建一次）。标定数据：截图那条 L 的距离 0.109 → 0.063，
竖横比 0.4~4.0 全部命中，不同形状之间最近仍余 0.283。

> 见 [`reference/POSTMORTEMS.md`](reference/POSTMORTEMS.md)。

## 22. 2026-10-06 事故二：Web Search 手势 → 主线程卡 47 秒 → 菜单栏崩溃

Web 搜索手势 → 主线程**同步**调辅助功能 API 取窗口标题，卡 **47 秒** → 随后在状态栏菜单崩溃
（`NSMenuDelegate.menuWillOpen` 这个协议实现继承了主 actor 隔离）。现在窗口标题只在 **shell 脚本**需要时
才取、且在后台取、限时 0.25 秒；菜单改成推送式刷新。

**一眼判据**：日志里「命中手势」有了、「执行手势」没有 ⇒ 主线程被占住了。

> 见 [`reference/POSTMORTEMS.md`](reference/POSTMORTEMS.md)。

## 23. 2026-10-06 事故三：Web 搜索再次崩（急停监听的闭包继承了主 actor 隔离）

同一条路径上的另外两个缺陷：① 急停监听的**闭包字面量**继承了主 actor 隔离（被 Web 搜索自己合成的 ⌘C 点燃）；
② Web 搜索**深拷贝整个剪贴板**（当时是张 70+ MB 的图 → 卡约一分钟）。现在监听器用文件作用域函数且
**忽略合成事件**；选中文字优先走辅助功能 API，兜底才用 ⌘C 且**只在剪贴板本来是文本时**才用。

> 见 [`reference/POSTMORTEMS.md`](reference/POSTMORTEMS.md)。

## 24. 文档地图

本文件（ROADMAP）是**接手开发的第一份**：目标、已完成、下一步、结论级的坑。
下面这些是**按主题拆出去的参考文档**，需要动某一块时再点进去。

| 文档 | 什么时候读 |
|---|---|
| [`reference/POSTMORTEMS.md`](reference/POSTMORTEMS.md) | 改输入层、执行路径、并发/隔离之前 —— §8 那些结论的证据与崩溃栈都在这 |
| [`reference/LEGACY-FORMAT.md`](reference/LEGACY-FORMAT.md) | 改配置层、导入器、`prefs.json` 之前（原版字段的逐条勘察） |
| [`reference/SETTINGS-UI.md`](reference/SETTINGS-UI.md) | 改设置界面之前（很多「看着奇怪」的地方是刻意定的） |
| [`reference/PACKAGING.md`](reference/PACKAGING.md) | 发版、改默认手势包、改 `make dist` 之前 |
| [`reference/SITE.md`](reference/SITE.md) | 改介绍页、重新部署之前 |
| [`reference/I18N.md`](reference/I18N.md) | 改界面文案、加新语言、动默认包名字之前 |
| [`reference/PERFORMANCE.md`](reference/PERFORMANCE.md) | 改事件拦截器、加实时渲染之前 |
| [`reference/LAUNCH-AT-LOGIN.md`](reference/LAUNCH-AT-LOGIN.md) | 改开机自启之前 |
| [`reference/APP-ICON.md`](reference/APP-ICON.md) | 换图标之前 |
| [`PLAN.md`](PLAN.md)、[`PLAN-2026-10-06.md`](PLAN-2026-10-06.md)、[`PLAN-2026-10-06-i18n.md`](PLAN-2026-10-06-i18n.md)、[`OPEN-SOURCE-PLAN.md`](OPEN-SOURCE-PLAN.md) | 当初批准的方案存档，**不再更新** |
| [`RELEASE-CHECKLIST-0.2.0.md`](RELEASE-CHECKLIST-0.2.0.md)、[`RELEASE-CHECKLIST-0.3.0.md`](RELEASE-CHECKLIST-0.3.0.md) | 当次发版的可执行清单（做完即归档） |
| [`release-notes/`](release-notes/) | 对外发布的版本说明 |
| [`INSTALL.md`](INSTALL.md) | 安装与 Gatekeeper 放行 |

### 这次拆分（2026-10-06）

原来是 1481 行、23 节混在一起。现在把 11 节「一次性叙事」（事故调查、成本评估、部署记录）
原样搬到 `reference/`，原地只留结论 + 链接；**章节号一个没动** —— 搬走编号会让全仓库约 40 处
`§N` 引用（源码注释、测试、`make-dist.sh`、`check-appkit-isolation.py`、README、CHANGELOG）全部失效。
性能测试、守卫脚本与代码注释里的引用因此**不需要任何改动**。
