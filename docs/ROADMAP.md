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

> **2026-10-06 更新（发版已完成）**：第 1、2 项都已做完 —— 你实机测了大半天没有新问题，
> 9 条提交已 push 到 GitHub，**v0.2.0 已发布**
> （<https://github.com/ZilongYang/zWGestures/releases/tag/v0.2.0>，五个产物齐全，
> `releases/latest/download/zWGestures-arm64.dmg` 已验证返回 200）。
> **所以现在从第 3 项开始**：把站点版本号刷上去（仓库里已是 v0.2.0，但线上还写着 v0.1.0），
> 再做 404 页与全新账号验收。
> 当次发版的**打勾清单**在 [`RELEASE-CHECKLIST-0.2.0.md`](RELEASE-CHECKLIST-0.2.0.md)
> （已完成项已勾上）；这批修复当初批准的**实施方案**原样存档在
> [`PLAN-2026-10-06.md`](PLAN-2026-10-06.md)。
> P6a–P6l、P9 已于 2026-09-28 实机验证通过；触发矩阵与边角/滚轮触发仍然**主动押后**
> （依据见第 6 项）。

### 1. ✅ 发版前由你做的实机回归（2026-10-06 完成）

这一轮改的是**识别判据**与**主线程调度**，两者都容易「看着没事、实际手感不对」。
下面这份清单当时逐条过过，结果：**通过**（详见 §21~§23 的三次事故记录 —— 前两次崩溃都是在
这一轮测试里抓出来的，修完又测了一天才发版）。

**新行为（期望值来自 §21 的实测）**

- 画一条**竖明显比横长**的「下→右」（截图那种）→ 应命中**关闭**，不再「画了没反应」。
- 把同一条 L 的横画长一些 → 仍应是关闭；不该跳成 `Enter` / `Minimize`。
- 三段手势（竖→横→竖）把横画得较长 → 应稳定是 `Enter`；`下→右→上`、`上→右→下` 分别是
  `Minimize` / `Fullscreen`，方向不该被长度带跑。
- **剪贴板里放一张图片**时画「Web 搜索」→ 也应当立刻响应（这条覆盖 §23 那个一分钟卡死）。

**回归面（这些不该有变化）**

- **闭环手势**：`Web 搜索`（上→原路返回）、`退格`、`删除` 仍然按「细长环」命中；正圆仍然不命中。
- **手势修饰键**：`拷贝`（不按左键）与 `剪切`（画线时按住左键）都还能用；
  `粘贴` / `粘贴并回车` 同理。
- **应用目标继承**：在 Brave 里自有手势优先、其余继承全局的那几条仍然生效。
- **Web 搜索手势**（前台是浏览器时画）：应当立刻打开页面，**不该**出现界面卡住、动作不执行
  —— 2026-10-06 的卡死就是这条路径（§22、§23）。
- **设置界面**：形状冲突的橙色告警、按列表顺序调优先级、按手势禁用，三者行为与之前一致；
  打开编辑器录制笔画时引擎会暂停、关闭后按原状态恢复。
- **开机自启**：菜单仍显示「已开启（系统登录项）」。

**读数（`make run-debug` 打开调试面板，或菜单栏里打开）**

- `idx rebuilds`：正常使用时应停在启动时那 1 次；**只有**你改配置（保存/导入/换目标）才会涨。
  如果它每 3 秒自己涨一次，说明 §21 第四节那个修复没生效，请立刻告诉我。
- `交接 X ms / 最差 Y ms`：X 应长期是个位数毫秒；`最差` 偶尔几十毫秒可以接受，长期几百毫秒
  就是还有别的主线程工作，把 HUD 截图给我。
- `timeouts` 与 `tap`：应长期是 `0` 与 `running`。

**长跑（可选但推荐）**：挂 1–2 小时后看 `~/Library/Logs/DiagnosticReports/zWGestures-*.ips`
有没有新文件（本项目踩过两次主 actor 相关崩溃）。

### 2. ✅ 发 0.2.0（2026-10-06 已发布）

流程照 `OPEN-SOURCE-PLAN.md` §5.4 走。版本号取 **0.2.0**：识别判据变了（行为可见），
按 0.x 里 minor 走比 patch 合适。

**实际执行结果**（每一步都验证过）：

| 步骤 | 结果 |
|---|---|
| push | 9 条提交 push 到 `origin/main`（`2182f87..2d3f33c`） |
| CHANGELOG | `## [未发布]` → `## [0.2.0] - 2026-10-06` |
| release notes | 新增 `docs/release-notes/0.2.0.md`（七条必含项齐全） |
| 三处版本号 | `project.yml` 0.2.0 / build 2（产物 `Info.plist` 实测已是 0.2.0+2）、`site/index.html` v0.2.0、CHANGELOG |
| `make dist` | 六项硬断言全过（arm64、版本、默认手势包在、无调试 entitlement、无构建者主目录、无敏感文件） |
| 产物核对 | zip 解开后：0.2.0 / arm64 / `Signature=adhoc` / 默认手势包在 |
| tag + release | `v0.2.0`，标题「zWGestures 0.2.0」，五个产物齐、非草稿非预发布 |
| 下载地址 | `releases/latest/download/zWGestures-arm64.dmg` 实测 **200** |

> ⚠️ 与清单里那句话的差异：清单说 `make dist` **必须在正常终端**跑（`diskutil image create from`
> 要挂载卷）。这次是在带完整权限的会话里跑成功的，如果将来受限环境失败，仍以正常终端为准。

1. **CHANGELOG**：把开头的 `## [未发布]` 改成 `## [0.2.0] - <发版日期>`。
2. **写 `docs/release-notes/0.2.0.md`**：以 `docs/release-notes/0.1.0.md` 为模板（下载表、
   首次放行、校验和那几节照抄，只改版本号），正文换成这次的用户视角描述：手势不再被笔画长短
   左右、动作不再偶尔慢半拍。**必含那七条**：未签名说明、Gatekeeper 步骤、
   **更新后要重新授权辅助功能**、仅 Apple Silicon、必须拖进 Applications、
   「从 WGestures 导入」怎么用、界面目前仅中文。
3. **同步三处版本号**（这是历史上容易漏的一步）：
   - `project.yml` 的 `MARKETING_VERSION`（现在 `0.1.0`；`CURRENT_PROJECT_VERSION` 一并 +1）
   - `site/index.html` 第 181 行附近的 `v0.1.0 · macOS 14+ · Apple Silicon`
   - `CHANGELOG.md`（第 1 步已覆盖）
4. **push**：`git push origin main`。
5. **`make dist`** —— ⚠️ **必须在正常终端里跑**，不要在我这种受限沙箱里跑：脚本用
   `diskutil image create from`（会挂载卷），沙箱里连最小用例都失败；脚本自带
   「产物不含 `get-task-allow`」「不泄露构建者 home 路径」的硬断言，失败会直接退出。
6. **打 tag 并建 release**：
   ```bash
   git tag v0.2.0 && git push origin v0.2.0
   gh release create v0.2.0 --notes-file docs/release-notes/0.2.0.md \
     dist/zWGestures-0.2.0-arm64.dmg dist/zWGestures-arm64.dmg \
     dist/zWGestures-0.2.0-arm64.zip dist/zWGestures-arm64.zip dist/SHA256SUMS
   ```
   固定名的那两个产物不能改名 —— 站点的下载按钮指向
   `releases/latest/download/zWGestures-arm64.dmg`，靠它发版后不用改 HTML。
7. **发版后验证**：`releases/latest/download/zWGestures-arm64.dmg` 能下到且是新版；
   `site/index.html` 上的版本号与按钮一致；顺手把 `OPEN-SOURCE-PLAN.md` §9 清单里
   「Release 产物」那几条（`Signature=adhoc`、`lipo -archs` 只有 arm64、SHA256SUM 校验通过、
   产物内无 `license.json`）再跑一遍。

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
> 这些都固化成了断言：`StrokeDirectionTests` 用参考配置的 `P` 原值直接断言方向语义，
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

## 9. 验证方式

- 单元测试：`make test`（230 项），其中多条**针对参考配置**的强回归断言。
  在没装原版 WGestures 的机器上会有 1 项哨兵测试被跳过，属正常。
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

  > 上面这段是当时的原始输出，保留原样。`com.zilong.zwgestures` 属于个人命名空间，开源前已
  > 统一改为 `io.github.zilongyang.zwgestures`（详见 [`OPEN-SOURCE-PLAN.md`](OPEN-SOURCE-PLAN.md) 阶段一）。
  > 改 ID 之后 `SMAppService` 需要按新身份重新注册一次。

  **归因要谨慎**：`rm -rf` + `ditto` 重建 bundle 破坏系统关联**只是时序吻合的怀疑**
  （旧装法 → `.notFound`；换原地覆盖 → 注册成功），并不能严格证明因果 —— 也可能来自新构建或
  单纯重新注册。但**结论可以确定**：`SMAppService` 对本机这个无 Team ID 的自签名应用
  **是能用的**，不必绕开它。
  同一时刻 `sfltool dumpbtm` 里**没有任何** zWGestures / zilong 记录（改 ID 后应搜
  `io.github.zilongyang.zwgestures`），
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

- plist 位置：`~/Library/LaunchAgents/io.github.zilongyang.zwgestures.plist`；生成逻辑在
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
  呈现失败**。排查命令见 README（`log stream --predicate 'subsystem == "io.github.zilongyang.zwgestures"'`）。

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
并且有一条**与参考配置里「Copy」定义比对归一化距离**的测试 —— 录一个向上笔画必须能匹配
原版的拷贝，这是 y 轴方向与绘制顺序最强的守卫（这两点历史上各错过一次）。

### ⚠️ 同形状不一定是冲突 —— 必须看修饰键

**这是我在 P6d 第一版里犯过的错，差点把用户正常的配置判成坏的。**
参考配置里 `Copy` 与 `Cut` 都是「上」、`Paste` 与 `Paste & Enter` 都是「下」，
区分它们的是**手势修饰键**（鼠标左键）。识别器 `GestureRecognizer` 的实际规则是：

- `areModifiersSatisfied`：意图声明的每个修饰键步骤都必须真实发生（子集判定）；
- `bestCandidate`：**修饰键多的优先**，其次比形状距离，平局给列表靠后的。

所以不按左键时只有 `Copy` 符合条件，按住左键时 `Cut` 更具体而胜出 —— **两条都能用**。
判成冲突的条件必须同时满足三条：**同一个触发键 + 同样的修饰键要求 + 形状距离 ≤ 阈值**。
`WGStrokeConflict` 用签名比较（滚动的幅度折叠成方向，与识别器一致）实现这三条，
并有一条**不变量测试**跑在参考配置上：凡是被报出来的冲突，两条手势的触发与修饰键
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
  这一点是硬约束：`ConfigTests` 有一条「参考配置重新编码后与原文件逐键一致」的守卫，
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

把顺序放在距离之前是**安全**的 —— 但这条推理的**依据在 2026-10-06 被实测推翻，已改**：
原文写「参考配置里非重复形状之间最近的一对约 0.28，是阈值的近三倍，所以两条不同形状不可能同时
通过阈值」。实测（`ConfusionReportTests` 打印的正是这份矩阵）在**旧弧长度量**下最近的不同形状只有
**0.100**（`Enter` 与 `Close`），所以 `Enter` 因为排在前面，会抢走本该属于「关闭」的 L 形轨迹。
现在这条规则之所以仍然安全，靠的是**度量**而不是阈值：换成结构度量后，真正不同的形状最近一对是
**0.283**（`Enter` vs `Fullscreen`），能同时过阈值的只剩真·重复形状 —— 那正是该由列表顺序裁决的
情形。见 §21。

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
保证重新编码参考配置仍然逐键一致（`ConfigTests` 守着）。

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

## 14. 明确的边界

- 不复制、不打包原版任何二进制、字体、图标、资源或激活码；只做配置格式互通。
- 不复刻 Windows 版特有功能：自定义菜单、Lua、Cmd 脚本、运行/激活应用程序。
- 不做 App Store 上架（沙箱与全局输入拦截互斥）。

---

## 15. 界面英文化（成本评估）

> **2026-10-06 更正**：0.1.0 的 release notes 与站点曾写「英文界面排在 v0.2.0」。**没有兑现** ——
> 0.2.0 把力气全用在修识别度量与三起崩溃/卡死上了（第 21~23 节），界面语言一个字没动。
> 站点与 README 里那句已改成「仍在路线图上、尚未排期」；0.1.0 的 release notes 是对外发布过的
> 存档，**不回头改**，以本文与 0.2.0 的 release notes 为准。

用户 2026-09-29 决定：**v0.1.0 不做界面多语言，搁置**。当时只做三件便宜事 ——
`CFBundleLocalizations` 去掉不实的 `en`（已改，`Info.plist` 是生成物，已重新生成）、三份文档写明
「界面目前仅中文」（已写）、把成本评估记在这里。

### 要做的事

1. **抽字符串。** 界面文案现在是散落各处的字面量，需要抽进 String Catalog。规模约 **200+ 条**：
   设置界面（手势列表 / 手势编辑器 / 偏好设置）、命令编辑器、应用目标管理、菜单栏、各类弹窗与错误提示。
2. **ZWGCore 的展示层要改结构 —— 这是真正麻烦的部分。** 用户可见文案有一部分**住在核心逻辑包里**：
   `ZWGCore/Sources/ZWGCore/Config/Display/WGIntentDisplay.swift`（对 `WGIntent` 的展示扩展，提供
   `displayName` / `strokeDescription` / `modifierDescriptions` / `summary` / `describe(inputKey:)` /
   `keySymbol`）与 `WGCommand.summary`。而 ZWGCore 是个不知道 UI 语言的纯逻辑包。两条路：
   - 给这些入口做 **locale 注入**（传 `Locale` 或一个文案提供者），或
   - 把展示层**上移**到 App target（ZWGCore 只留结构化数据）。

   两条都会**改动公开 API**，并会碰一批断言中文文案的测试。
   （`ConfigController.Status.localizedText` 与 `LoginItem.Status.localizedText` 已经在 App target 里，
   这部分不用搬。）
3. **出厂默认手势要做第二份。** 默认手势的名字来自原版的 `tr_bootstrap.json`（中文译名表）。要出英文界面
   就得再做一份英文默认配置 —— 等于**两份默认配置**都要维护，各自都要有往返与键名测试。
4. **系统层文案要跟着走。** 菜单栏、弹窗、`Info.plist` 的 `NSAppleEventsUsageDescription` 等；
   `CFBundleLocalizations` 加回 `en`；复核 `CFBundleDevelopmentRegion`。

### 不做的部分

- 不做 RTL 适配 —— 界面没有需要镜像的布局。
- 不做中英以外的第三语言。
- 不动 `site/index.html`（那个页面自带中英切换，与 App 界面语言无关）。

### 实施顺序与风险

**先做第 2 条（展示层结构），再抽字符串。** 顺序反了会把同一批文案抽两遍。

主要成本是「断言中文文案的测试」：那批测试要么改成断言结构化数据（枚举 / 键），要么把期望文案一并本地化。
实测的粗略基线（2026-09-29）：

| 位置 | 中文字面量 | 说明 |
|---|---|---|
| `zWGestures/`（App target） | 约 160 处 | 含日志与注释里的字符串，不全是界面文案 —— 需要逐个甄别 |
| `ZWGCore/Tests/ZWGCoreTests/` | 约 649 处，分布在 19 个文件 | 其中大部分是测试标题与诊断信息，**不全是文案断言** —— 同样需要逐个甄别 |

这两个数字只用来判断量级，不能直接当作「待抽条数」。

顺带能修掉一个现存的不一致：`WGCommand.summary` 这类**给用户看的**文案，本来就不该住在核心逻辑包里。

---

## 16. 出厂默认手势包（随 App 发布）

**要解决的问题**：没装过原版 WGestures 的人装完 App、授权完辅助功能，画任何手势都没反应 ——
会被直接判定为坏软件。这是下载版能不能用的第一道门槛。

**做法**：随 App 发布一份 48 条中文手势的出厂默认包，直接取自原版自己的出厂手势集。

| 手势集 | 条数 | 来源 |
|---|---|---|
| 全局 | 45 | `/Applications/WGestures.app/Contents/Resources/gestures.json` |
| Finder | 3 | 同上 |

- 中文名来自原版自带的中文译名表 `zh_CN.lproj/tr_bootstrap.json`：48 条 / 42 个不同名字，
  **100% 覆盖**，一个都查不到就报错退出（不猜）。`WGIntent.name` 没有任何运行时翻译，
  所以名字必须烘进 JSON。
- 偏好抄原版，但 `AutoStart` 强制改为 `false`；`SkipVersion: null` 原样保留
  —— 它守着 `encodeIfPresent` 那条编码路径。
- 本机实测：产出与原版 `gestures.json` 的差异**只有 47 处 `Name` 取值**，其余逐字节相同 ——
  脚本按原版自己的 JSON 风格（2 空格缩进、无结尾换行）写回，评审时肉眼可看。
- 原版出厂就带着重名条目（`关闭`×2、`新建`×2、`上一标签`×3、`下一标签`×3），靠手势修饰键区分，
  是数据不是错误；单测把这份名册钉死了。

**出处与重生成方式**（三处，不再另加文档文件）：

1. `scripts/make-default-gestures.py` 的 docstring —— 数据来源、为什么安全、怎么重新生成；
2. `Makefile` 的 `default-gestures` 目标注释；
3. 本节。

```bash
make default-gestures                # 用 /Applications/WGestures.app
make default-gestures ORIGINAL=/path/to/WGestures.app/Contents/Resources
```

生成物 `zWGestures/Resources/Defaults/{gestures.json,prefs.json}` **提交进仓库**，但**不挂进 `build`**
—— 只有装了原版的机器才生成得出来。它必须以**目录**形式进 bundle
（`Contents/Resources/Defaults/`），所以 `project.yml` 里单独给它一条 **folder reference**
（普通的 `.json` 资源会被 XcodeGen 平铺到 Resources 根目录）；产物路径由 CI 的一条断言守着。

**首启顺序**：已有配置 → 原版的安装 → 内置默认。决策逻辑在 `ConfigBootstrapper`（有单测），
`ConfigController.start()` 按它分三支，`Status` 增加 `.seeded(intents:)`。
**首次用到默认包或导入成功时会自动打开设置窗口** —— `LSUIElement`（无 Dock 图标）的 App
否则只有一个菜单栏小图标，看起来像没启动。

**版权**：默认包是**原版的配置数据 + 它自带的中文译名表**，属配置数据，而非二进制、字体、图标或代码。
README 与 `README.en.md` 的「许可证与商标」已写明「独立的重新实现、非官方、无隶属关系」并链接官网。
后备方案：换成一份手写精简默认，`ConfigStore.importDefaultConfiguration(from:)` 这个接口不变。

---

## 17. Gatekeeper 实测结果与 `make dist` 的两个硬要求（2026-09-30）

用 Release + ad-hoc 签名的产物在本机（macOS 27.0 / 26A428 / M1 Pro）实测，逐条结论与「怎么测的」
写成了单一事实来源 [`INSTALL.md`](INSTALL.md)。这里只记**踩到的两个坑**和三条值得记住的事实。

### 坑一：Release 产物带着调试 entitlement

第一次真正跑 Release 路径时发现产物里有：

```
[Key] com.apple.security.get-task-allow   [Value] [Bool] true
```

这是**允许别人 attach 调试器**的开发用 entitlement，不该出现在分发产物里。来源是
`CODE_SIGN_INJECT_BASE_ENTITLEMENTS` 默认为 YES。`make dist` 必须显式加
`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`（Debug 构建保留它，那是要用的）。

### 坑二：`hdiutil create` 在 macOS 27 上已废弃，新 API 又需要非沙箱环境

`hdiutil create -srcfolder …` 会打印废弃警告并**直接失败**（`create failed - 目录非空`）。替代：

```bash
diskutil image create from --format UDZO --volumeName zWGestures <staging> <out.dmg>
```

它需要挂载卷，**在受限沙箱里连最小用例都失败**（`OSStatus error 1`）——
做发布产物必须在正常终端里跑。`make dist` 用这条新 API。

### 三条值得记住的事实

1. **带隔离标记时是「先启动、后被系统结束」，不是「弹窗拒绝」。** `open` 返回 **0**（成功），
   应用被移置到 `…/T/AppTranslocation/<UUID>/d/`，`syspolicyd` 异步评估后才结束进程
   （本机实测 **19.6 秒**）。所以**绝不能用 `open` 的退出码判断应用是否真的起来了** ——
   任何安装脚本都别这么写。
2. **`curl -L` 下载的包不带隔离标记**（zip 与 dmg 都实测过）。这是「脚本 / Homebrew Cask 安装
   可以绕开弹窗」的依据，也正是计划里特别标注「必须实测、不凭记忆写」的那一条。
3. **去掉 `com.apple.quarantine` 的同时也去掉了 App Translocation。** 移置会把应用换到一个随机
   只读路径，而登录项记录的是**路径** —— 所以「不要在 dmg 卷里直接运行」不是洁癖，
   是功能正确性问题（否则开机自启注册的是那个临时路径，重启后就失效）。

打包前的安全扫描（`license.json` / `.p12` / `.pem` / `.key` 不得入产物）第一次跑过，产物干净；
`.gitignore` 已加 `dist/`。

---

## 18. 介绍页素材（截图）怎么拍的

截图放在 **`site/assets/`**（不是 `docs/screenshots/`）：`site/` 是要单独部署出去的目录，素材必须
自带在它里面，否则部署时就会缺图；放两份又迟早走样。

| 文件 | 内容 | 怎么来的 |
|---|---|---|
| `icon.png` | 应用图标 512×512 | 由 `docs/icon/appicon-1024.png` 用 `sips -Z 512` 缩放 |
| `shot-settings.png` | 设置界面（48 条中文手势） | 按**窗口 id** 真实截图，再裁掉底部状态栏 |
| `shot-menu.png` | 菜单栏菜单展开 | 真实截图，**只截菜单那个窗口** |
| `shot-overlay.png` | 轨迹与手势名 | 见下 |

### 隐私：截图里不能出现本机信息

第一版设置截图里，底部状态栏写着 `存于 /Users/<用户名>/Library/…`；后来按固定区域截菜单时，
还把你的桌面文件、浏览器标签、视频通话窗口一起截了进去。两条都换了做法：

1. **状态栏路径改显示 `~`**（`SettingsPanel` 改用 `abbreviatingWithTildeInPath`）——更短、更友好，
   顺带让任何截图都不再带用户名。
2. **只截应用的窗口，不按屏幕区域截**。轨迹只画在应用自己的覆盖层窗口里，那个窗口**除轨迹与手势名
   之外完全透明**；按窗口 id 截它，就不可能混进桌面内容。实测：没有轨迹时非透明像素为 **0**，
   所以它同时也是一个**零误判**的「轨迹出现了没」检测器 —— 这比按颜色找绿色可靠得多
   （第一版按绿色找，把壁纸和应用图标里的绿色当成了轨迹）。

### 轨迹图的背景是衬底，不是屏幕截图

覆盖层窗口截出来是**透明 PNG**（只有轨迹 + 手势名）。发布用的 `shot-overlay.png` 是把这份真实截图
叠在一层深色渐变衬底上、再按轨迹包围盒裁切的结果 —— **背景纯装饰，轨迹与文字是真实取景**。
不伪造任何界面内容；但若有人问「这是不是一张屏幕截图」，诚实答案是「轨迹是，背景不是」。

### 截图用的是出厂默认手势，不是本机配置

用 `ZWG_CONFIG_DIR` 指向临时目录跑出「下载者看到的样子」：48 条中文手势。这样截图才与
「开箱 48 条中文手势」的说法一致 —— 本机配置是从原版导入的英文名，直接拍会自相矛盾。

⚠️ **一个重要发现**：`ZWG_CONFIG_DIR` 只改**配置目录**，不改**原版目录**。所以在一台装了原版
WGestures 的机器上，首启依旧走「导入原版」而不是「播种出厂默认」——
这是 `ConfigBootstrapper` 的正确优先级（见 §16），但也意味着**出厂默认那条路径在本机测不出来**。
要真正验证它，得在一台**没有原版**的机器上跑，也就是全新用户账号那一步。

### 顺手修掉的一个 bug：菜单栏状态不刷新

拍菜单截图时发现它显示「手势引擎：已暂停 / 辅助功能权限：未授权」，而日志里明明是
`accessibility trusted: true` + `event tap installed`。原因：`EngineController.onStateChange`
声明了、也在 4 处触发，但**从来没有人给它赋值**，于是一个静态 `NSMenu` 永远保持构建时的文案。

修了两处：`AppDelegate` 把 `engine.onStateChange` 接到 `statusItemController.refresh()`；
`StatusItemController` 同时实现 `NSMenuDelegate.menuWillOpen` 再刷新一次作为兜底。
对一个菜单栏应用来说，把引擎状态写错比不显示更糟。


---

## 19. tap 线程性能硬化（2026-09-29）

§13 的冻结事故之后，这一项被列为当时 §3 的待办（2026-10-06 起不再是待办项，已完成）。下面记的是**实测数据**与改了什么 ——
因为动手前的假设被数据推翻过一次，那个过程比结论更值得留下。

### 先量，再改

新增 `RecognitionPerformanceTests`（跑在 fixture 上，不依赖 App bundle），量的是拦截器线程真正
走的那条路径：

| 指标 | 改前 | 改后 |
|---|---|---|
| 一次候选评分（200 点笔画） | **1460 µs** | **403 µs** |
| 「没匹配上」的完整路径 | **2903 µs** | **428 µs** |
| 笔画从 50 点涨到 800 点的耗时比值 | 2.62 | 1.55 |

改后参与评分的手势从 49 降到 32，因为不可能触发的那些在构建索引时就被摘掉了（见最后一段）。

### 我一开始猜错了什么

事故诊断时我怀疑「tap 线程每 50 ms 拷贝整份 `RecognitionContext`」是主因。**数据不支持这个判断**：
Swift 的数组是 COW，那只是几次 retain。用两个数据点解出模型
`T = 1035 µs（常数项） + 2.51 µs × 点数` 之后才看清 —— **71% 的开销在常数项**，也就是每个候选
都在重复做的工作：

- `WGIntent.triggerSteps` 用 `.map` **每次访问都新建数组**；`modifierSteps` 用 `Array(...)` 同理，
  而且它被访问**两次**（判修饰键一次、取 `.count` 又一次）
- `WGInputToken(key:)` 每次都要 `hasPrefix` 解析字符串（`MOUSE:1` / `VSCROLL:-3`）
- `WGTriggerSignature.make(from:)` 每次构造一个 token 数组 —— 而它在 `WGTriggerMatrix.allows`
  的「空矩阵直接 return true」短路**之前**执行，对全局目标等于纯白做
- `WGStrokeStep.drawingOrderPoints` 把 `[Int]` 转成 `[CGPoint]`，`StrokeNormalizer.normalize`
  里再做重采样 + 两轮 map + pathLength
- **实时笔画的归一化对每个候选都重算一遍**，而它的结果对所有候选完全相同

约 8 次堆分配 × 45 个候选 ≈ **每次识别 380 次堆分配**。

### 改了什么

1. **新增 `PreparedGesture` / `GestureIndex` / `RecognitionIndex`（ZWGCore）**：把每条手势的触发
   按钮、触发签名、修饰键要求、归一化后的形状全部预先算好。构建索引是昂贵的那一半，所以它只在
   **配置变化时、在主线程上**做一次，绝不进 tap 回调。
2. **实时笔画只归一化一次**，而不是每个候选一次 —— 这就是「45 倍无用功」那一项。
3. **`recognizeWithNearest`**：识别与「最近候选」合并为一次遍历。原来未命中时要跑两遍全量，
   而那正是最慢的一条路径。
4. **tap 线程不再拷贝配置**：`RecognitionSnapshot` 是引用型，锁里只做一次 retain；
   索引构建移出临界区。
5. **合并规则只写一处**：抽出 `TargetResolver.effectiveTarget`，让解析器与索引构建看到**同一个**
   目标（索引按 `id` 查表，两者不一致就会「手势静默不响应」—— 那种现象最难查）。
   索引查不到时的兜底是**记 error 日志**，不是静默跳过。

### 顺带发现的一处「白做」

索引把不可能触发的手势提前摘掉后，参考配置的全局手势从 49 条降到 **32 条**。也就是说改之前，
**每次事件都有 17 条不可能生效的手势被完整解析、归一化、算形状距离，然后才被触发键检查否决**。

### 留下的守卫

- `RecognitionPerformanceTests`（4 项）：绝对上界（候选评分 < 0.8 ms、未命中路径 < 1.2 ms），
  以及「索引路径必须明显快于每次重建」—— 防止有人把索引构建又搬回拦截器线程。
  命中上界的具体数字每次跑都会打印出来，便于对比。
- `GestureIndexTests`（3 项）：钉住「永不生效的手势不进索引」「解析出的每个目标都能查到索引」
  「继承目标里自己的手势排在全局之前（列表顺序就是优先级）」。


---

## 20. 介绍页部署、一次自查发现的疏漏、以及留在明天的事（2026-09-30）

### 已部署并验证

介绍页已部署到用户自己的服务器，并逐项验证：HTTP→HTTPS 301、首页与 4 张素材**逐字节一致**
（把线上文件拉回来比对 sha256）、gzip 已启用、用 WebKit 实际渲染**线上**页面确认显示正常。
面板的 `server_name` 里同时写了两个域名，所以两个地址都能访问 —— 但页面里的 `canonical`
只指向一个，避免同一份内容有两个规范地址。

部署方式与踩到的坑写在 [`site/README.md`](../site/README.md)：**`tar` 会原样保留本地属主与权限**，
第一次部署后远端是 `501:staff` 且 `index.html` 为 `600`，Web 服务器读不到、访客拿到 403；
rsync 没有这个问题（按远端 umask 新建）。

### ⚠️ 一次自查发现的疏漏：基础设施信息进了公开仓库

第一次写部署记录时，我把**服务器主机别名**与**绝对路径**直接写进了 `site/README.md` 并推到了
GitHub。用户指出后自查，处理如下：

- 真实连接信息移到 `docs/private/local-deploy.md`，该目录**已 gitignore** ——
  `git` 从一开始就看不到它，所以**不需要「git filter」**那一步；
- 公开文档只保留通用做法与经验教训（主机写成 `user@your-server`，路径写成 `<域名>` 占位符）。

**为什么之前没拦住**：这条信息「看起来不像密钥」—— 没有密码、没有 token、没有私钥。
教训是：**「只对某台机器成立」的东西一律不进仓库**，而不是「只有密钥才不进仓库」。
这条已写成 `site/README.md` 开头的一条约定。

**待你决定的一件事**：那个提交（`8175234`）**已经在 GitHub 上**。工作树现在干净了，但历史里
仍然查得到那个主机名（`git log -p`）。

- 要干净地清掉，得**改写那一个提交并 force-push**。仓库刚建、还没有 fork 或协作，风险很低；
  但 GitHub 侧被孤立的对象仍可能按旧 SHA 访问一段时间。
- 不清理也能接受：那个别名解析到 CGNAT 网段（`100.64.0.0/10`），**公网不可达**，不是可攻击目标；
  它泄漏的是「用 1Panel」「服务器目录结构」「主机命名习惯」这类指纹。

**没有批准我不会 force-push。**

### 明天要做的

> **2026-10-06 注**：这三项一直没有做，现在由 §3 第 3 项接管（那里写清了可执行口径）。
> 下面这段保留为当时的原始记录，不再更新。

1. **做一个与站点同风格的 404 页**（用户已确认要做）。`404.html` 就在站点目录里，属于站点内容，
   替换它**不需要改 nginx 配置**，风险很低。
2. **全新 macOS 用户账号验收**：挂 dmg → 拖进 Applications → Gatekeeper 放行 → 授权辅助功能 →
   验证开箱 48 条中文手势。这一步同时完成 **Release 配置的真机回归**，并顺手拍下
   `site/assets/install-gatekeeper.png`（那个账号没有任何个人信息，适合入镜）。
   拿到图后把 `site/index.html` 安装那节里注释掉的 `<figure>` 取消注释即可。
3. （可选）**`assets/` 的长缓存头**：面板生成的配置里没有，而它由面板管理、手改可能被重新生成
   覆盖，所以要加得走面板的网站配置界面。加的时候**只用 `expires 30d;`，不要用
   `add_header Cache-Control`** —— nginx 的 `add_header` 在子级 location 会**覆盖**父级同类指令，
   那会把站点现有的 `Strict-Transport-Security` 头在素材响应上抹掉。

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
