# zWGestures 开源 + 发布计划（v4 定稿）

> 本文件是 2026-09-29 经作者批准的《开源 + 发布计划》原样存档。
> 执行进度与实施细节见 [`ROADMAP.md`](ROADMAP.md)；本文件不再更新。
>
> ⚠️ **本文件在公开发布前做过一次脱敏**：原稿引用的作者邮箱、邮箱前缀、激活码前缀与个人
> 主目录名已替换为 `<…>` 占位符；除此之外内容与批准原稿一致。

## 决策汇总

| 项目 | 决定 |
|---|---|
| 许可证 | MIT |
| Bundle ID | `io.github.zilongyang.zwgestures` |
| 开发文档 | 脱敏后全部公开 |
| README | 中文为主 + `README.en.md` |
| 提交邮箱 | 改写为 `8017854+ZilongYang@users.noreply.github.com` |
| 测试 fixture | **你现在的配置**（52 条） |
| 出厂默认手势 | **脚本生成的「原版默认 + 中文译名」**（48 条），独立文件 |
| 原版导入行为 | **保留自动导入**，宣传但不作最大亮点 |
| **App 界面多语言** | **搁置到 v0.2.0**；本次只做诚实清理 + 文档说明 |
| 发布签名 | ad-hoc 未签名（`CODE_SIGN_IDENTITY=-`） |
| 发布产物 | dmg + zip，各留一个固定文件名别名 |
| HTML 页 | 只产出 `site/` + 部署说明，你自己部署 |
| 计划落盘 | **第 0 步先写 `docs/OPEN-SOURCE-PLAN.md`** |

---

## 0. 验收标准

**A. 仓库可开源**（干净环境 + 未装原版 + 无签名证书）：
```bash
make bootstrap && make test && make build   # 全绿，make test 0 failed / 0 skipped
```

**B. 下载版真的能用**（新建 macOS 用户账号验证）：
挂载 dmg → 拖进 Applications → 绕过 Gatekeeper → 授权辅助功能 → **开箱 48 条中文手势，画「上」触发拷贝**。

**C. 无隐私泄漏**：全树 grep 不到 `<作者邮箱>`、`<个人主目录>`、`~/.dsh`、`com.zilong`、**`license.json` / 激活码 `<激活码前缀>…`**。

---

## 1. 已核实的事实

- 107 个跟踪文件、36 个提交、单作者、**无远端**、工作树干净、`.git` 4.2 MB；缺 `LICENSE` / `.github/` / `CHANGELOG.md` / 截图。
- **无密钥入库**：全树 + 全历史 grep 未见 API key、私钥、p12。唯一明文口令是 `scripts/create-signing-cert.sh` 里刻意公开的本地钥匙串口令 `zwgestures`。
- **原版 App 在本机**：`/Applications/WGestures.app`，`Mach-O 64-bit executable x86_64`，版本 2.3.3。
- **找到原版打包的出厂默认手势集**：`Contents/Resources/gestures.json`（**45 全局 + 3 Finder**），配套 `Contents/Resources/prefs.json`。
- **出厂默认用到的 42 个名字，在原版自带译名表 `zh_CN.lproj/tr_bootstrap.json` 里 100% 覆盖** → 中文版出厂默认可脚本生成，零人工翻译。
- **你现在这份配置 ≠ 出厂默认**（已纠正）：45 条同名条目逐字节相同，但你的配置删掉了 `Quit`/`Kill`，多加了 6 条中文手势（`退出`/`重新打开`/`重新载入`/`其他窗口`/`上一应用`/`下一应用`）；`prefs.json` 两者完全一致。
- 原版出厂默认**自带同名重复**：`Close`×2、`New`×2、`Previous Tab`×3、`Next Tab`×3。
- **应用配置目录硬编码** `~/Library/Application Support/zWGestures`（`ConfigStore.swift:12`），不由 bundle id 推导 → 改 bundle id **不会**搬迁配置与备份。
- 工程里 **Debug / Release 都存在**，但**至今只跑过 Debug**。
- `AppDelegate.swift:69-73` 已在未授权时弹辅助功能提示 → 首启权限引导**已有**。
- **首启是空的**（关键缺口）：`ConfigController.start()` → `importLegacy()`，无原版目录时抛 `directoryNotFound` → 手势 **0 条**。
- **Apple 官方口径**（[2026-09-01](https://developer.apple.com/news/?id=w5ngl9k2)）：macOS 26.4 起启动依赖 Rosetta 的应用会收到系统通知；**macOS 27 是最后一个支持 Rosetta 的版本，之后 Intel-only 应用在 Apple 芯片 Mac 上不再能运行**（少数老游戏除外）。
- **原版 macOS 版最后一版是 2.3.3 / 2021-12-12**（[官网更新日志](https://www.yingdev.com/projects/wgestures2)）。
- **App 界面零多语言基础设施**：0 处 `NSLocalizedString` / `String(localized:)`，0 个 `.lproj` / `Localizable.strings` / `.xcstrings`；生产代码约 **360** 处引号内中文串，测试 **555** 处，其中一批是**对用户可见文案的断言**（`"增加音量"`、`"全局"`、`"右→下"`、`"鼠标左键"`）。展示层在 ZWGCore（`WGIntentDisplay`、`WGConfig.swift`、`LegacyConfigImporter`、`WGCommandPlanner`）。
- **`Info.plist` 不实声明**：`CFBundleLocalizations: [zh-Hans, en]`，但一个英文资源都没有。（`Info.plist` 由 `project.yml` 的 `info.properties` 生成，要改 `project.yml` 再 `xcodegen generate`。）
- ⚠️ **`~/Library/Application Support/com.yingdev.wgestures/license.json` 里有你的邮箱和激活码**。它在 `2.3.3/` 的**上一级**，只拷 `2.3.3/` 就不会带进去 —— 但计划里加强制扫描（4.5）。

---

## 2. 阶段零：先落盘

**第 0 步（批准后第一个动作）**：把本计划原文写入 **`docs/OPEN-SOURCE-PLAN.md`**，并在 README 的「文档」索引表加一行。不覆盖 `docs/PLAN.md`（那是 2026-09-28 批准的实施方案存档，另一件事）。

---

## 3. 阶段一：让仓库可开源

### 3.1 `LICENSE`
MIT，`Copyright (c) 2026 Zilong Yang`。README / `README.en.md` 各加「许可证」小节。

### 3.2 测试 fixture（**当前 `make test` 在别人机器上是红的**）

三种病：

1. `SettingsModelTests.swift:589-591` 的 `realConfigHasUnsupportedGestures` **没有 `.enabled(if:)` 门控** → 找不到原版目录时 `#require` 抛错 → **测试失败**（不是跳过）。唯一一条会让 CI 变红的硬伤。
2. 另有 15 处 `.enabled(if: locateVersionDirectory() != nil)` → 没装原版时**静默跳过**，包括 `ConfigTests:400 reencodesRealFilesWithoutLoss`（逐键往返相等，抓过两个真 bug 的最强守卫）。
3. 断言写死本机数字：49 条全局 / Finder 3 条 / 52 条统计 / `stepsByType["StrokeStep"] == 39` / `commandsByType["KeySeqCommand"] == 38` / `startDragTimeout == 250`。

**fixture = 你现在这份配置**（52 条），因为 `ConfusionReportTests:73-102` 依赖 `重新载入`/`其他窗口`/`下一应用`/`上一应用`，`GestureRecognizerTests:52,265` 依赖 `重新载入` 的 `P` 原值 —— **这 4 个名字只存在于你的配置**；且现有 5 处写死条数全部保持有效。

1. 新增 `ZWGCore/Tests/ZWGCoreTests/Fixtures/legacy/2.3.3/{gestures.json,prefs.json,Version}`（**只从 `2.3.3/` 拷，绝不动上一级**）；同目录 `README.md` 记录来源与「改 fixture 要同步改断言」。
2. `ZWGCore/Package.swift` 的 `testTarget` 加 `resources: [.copy("Fixtures")]`。
3. 新增 `ZWGCore/Tests/ZWGCoreTests/TestSupport/FixtureConfig.swift`，用 `Bundle.module` 暴露 `directory: URL`。
4. 14 处 `try #require(LegacyConfigImporter.locateVersionDirectory())` → `FixtureConfig.directory`，删掉对应门控：

| 文件 | 行 |
|---|---|
| `ConfigTests.swift` | 374/377、402/405 |
| `SettingsModelTests.swift` | 589/591（**补门控 → 改 fixture**） |
| `CommandPlannerTests.swift` | 142/145、168/171 |
| `TargetResolverTests.swift` | 126/129 |
| `WGStrokeRecorderTests.swift` | 151/153 |
| `TriggerMatrixTests.swift` | 105/108 |
| `ConfusionReportTests.swift` | 43/74/94 + 助手 23 |
| `WGStrokeConflictTests.swift` | 57/59、91/93 |
| `StrokeDirectionTests.swift` | 113/116 |
| `OverlayStyleTests.swift` | 93/96/97 |

5. 断言里的具体数字**保留不动**；只把测试名/注释里的「真实配置」改成「参考配置（原版 2.3.3 + 用户改动）」。
6. **保留一条**读本机真实安装的测试（`ConfigTests.importsTheRealConfiguration`），仍带 `.enabled(if:)`，只断言结构性事实。
7. 生产代码 `LegacyConfigImporter` / `ConfigStore` 的**旧路径行为不动**。
8. README:73 的「223 项」条数会变，重新核对。

### 3.3 `make bootstrap`（全新克隆现在构建不起来）
`project.yml` 是 `CODE_SIGN_STYLE: Manual` + `CODE_SIGN_IDENTITY: "zWGestures Local Signing"` + `CODE_SIGNING_REQUIRED: YES`，没证书时 `make build` 直接失败。
① 新增 `make bootstrap`（检测不到就跑 `scripts/create-signing-cert.sh`，再打印下一步）；② README 改成 `make bootstrap` → `make build` → `make run`；③ `project.yml` **默认签名身份不变**（ad-hoc 只由 `make dist` 命令行覆盖）；④ 环境要求写明 **Apple Silicon**、macOS 14+、Xcode 26.x、XcodeGen。

### 3.4 CI
`.github/workflows/ci.yml` 两个 job：
- `core-tests`：`make lint` + `make test`（不需要证书、不需要原版安装 —— fixture 改造的收益）。
- `app-build`：`brew install xcodegen && xcodegen generate && xcodebuild … CODE_SIGNING_ALLOWED=NO build`，并**断言产物含 `Contents/Resources/Defaults/gestures.json`**（覆盖 `swift test` 碰不到的 App target：UI / EventTap / Overlay 都不在 ZWGCore 里）。

runner 优先 `macos-26`，取不到退 `macos-15`；**用一次真实 workflow run 确认，不臆测标签**。README 加 CI 徽章。

### 3.5 bundle ID 中性化
`com.zilong.zwgestures` → `io.github.zilongyang.zwgestures`，已 grep 穷举：

| 文件 | 位置 |
|---|---|
| `project.yml` | `bundleIdPrefix`、`PRODUCT_BUNDLE_IDENTIFIER` |
| `zWGestures.xcodeproj/project.pbxproj` | 2 处（`xcodegen generate` 重生成，不手改） |
| `ZWGCore/Sources/ZWGCore/Log.swift` | 第 7 行注释、第 9 行 `subsystem` |
| `ZWGCore/Sources/ZWGCore/Support/LaunchAgent.swift` | 第 17 行 `label`、第 19 行注释 |
| `ZWGCore/Tests/ZWGCoreTests/LaunchAgentTests.swift` | 11、14、23 行 |
| `zWGestures/Input/EventTapController.swift` | 105 行线程名 |
| `README.md` | 167、183 行 |
| `docs/ROADMAP.md` | 296、303、323、441 行 |

连锁影响（写进 README + ROADMAP，并在这台机器上手工收尾一次）：辅助功能授权失效需重新授权、系统设置可能残留旧条目；`SMAppService` 旧注册成为孤儿需重新注册；旧 `~/Library/LaunchAgents/com.zilong.zwgestures.plist` 手工清（**只在这台机器做一次，不进代码**）。不受影响：`~/Library/Application Support/zWGestures/`、导入路径 `com.yingdev.wgestures`。

### 3.6 文档脱敏

| 文件:行 | 改法 |
|---|---|
| `docs/PLAN.md:3` | `来源：DSH 会话记录 ~/.dsh/sessions/--Users-<个人主目录>-…` **整行删除** |
| `docs/PLAN.md:2` | 「经**<作者名>**批准」→「经作者批准」 |
| `docs/PLAN.md:37,130` | `/Users/<个人主目录>/zWork/ai/zWGestures` → `~/zWork/ai/zWGestures` |
| `docs/ROADMAP.md:72` | `cd /Users/<个人主目录>/…` → `cd /path/to/zWGestures` |
| `docs/ROADMAP.md:296,303,323,441` | 旧 bundle id → 新 bundle id |
| `docs/ROADMAP.md` 开头 | 加一句：文中「真实配置/参考配置」指原版 WGestures 2.3.3 配置的副本（含作者改动），已脱敏提交为 `ZWGCore/Tests/ZWGCoreTests/Fixtures/legacy/2.3.3/` |
| 全树 | 收尾 `git grep -niE "<作者邮箱用户名>|@gmail|/Users/|\.dsh|com\.zilong|license\.json"`，只允许剩新 bundle id |

### 3.7 git 历史作者邮箱改写
内置 `git filter-branch --env-filter`（36 个提交、线性历史，秒级）改写 `GIT_AUTHOR_EMAIL` / `GIT_COMMITTER_EMAIL` 为 `8017854+ZilongYang@users.noreply.github.com`，名字保持 `ZilongYang`。随后 `git reflog expire --expire=now --all && git gc --prune=now`，校验 `git log --format='%an <%ae>|%cn <%ce>' | sort -u` 只剩一行；`git config user.email` 也设为 noreply。**必须在建远端之前完成**。

### 3.8 开源文档
- **README 重构**：定位「开发」。顺序 → 一句话定位 + 徽章 → 截图 → 功能特性 → 环境要求 → 快速开始 → 配置与迁移 → **为什么会有 zWGestures**（5.2 致敬文案短版）→ **已知限制（界面目前仅中文）** → 开发约定（AppKit 隔离、`Timer` 陷阱、`open` 不重启 —— 保留）→ 贡献 / 文档索引 / 许可证 / 商标免责。「开机自启」「签名」两节折成 `<details>`。文档索引表加 `docs/OPEN-SOURCE-PLAN.md` 一行。
- **`README.en.md`**：同结构，顶部互链。
- **`CONTRIBUTING.md`**：构建方式、`make lint` + `make test`、提交前清单，两条**必须遵守**的约定（AppKit 几何/谓词覆写标 `nonisolated`；不要在 `Timer` 的 block 里碰 actor 隔离状态），以及「界面仅中文」这条限制。
- **`.github/ISSUE_TEMPLATE/bug_report.yml`**（macOS 版本 / Xcode 版本 / 复现步骤 / `.ips`）、**`.github/pull_request_template.md`**。
- **`CODE_OF_CONDUCT.md`：不做**。

### 3.9 App 界面多语言：搁置（本次只做三件便宜事）
1. **去掉 `Info.plist` 里不实的 `en` 声明** —— 改 `project.yml` 的 `CFBundleLocalizations` 为 `[zh-Hans]` 后 `xcodegen generate`（`Info.plist` 是生成物，不手改）。
2. README / `README.en.md` / `CONTRIBUTING.md` 写明：**界面目前仅中文，英文界面在 v0.2.0 路线图上**。
3. `docs/ROADMAP.md` 新增 v0.2.0 工作包，含成本评估（抽 200+ 条字符串进 String Catalog；ZWGCore 展示层要么做 locale 注入、要么上移到 App 层，两者都会动公开 API 与一批断言中文文案的测试；出厂默认手势需再做一份英文，等于两份默认配置）。

---

## 4. 阶段二：让下载版真的能用

### 4.1 出厂默认手势包（**最高优先级**）
现状：没装过原版的人装完 App、授权完辅助功能，画任何手势都没反应 —— 会直接判定是坏软件。

| 用途 | 来源 |
|---|---|
| 手势定义 | `/Applications/WGestures.app/Contents/Resources/gestures.json`（45 全局 + 3 Finder） |
| 中文名 | `/Applications/WGestures.app/Contents/Resources/zh_CN.lproj/tr_bootstrap.json`（42 个名字 100% 覆盖） |
| 偏好 | `/Applications/WGestures.app/Contents/Resources/prefs.json` |

1. 新增 `scripts/make-default-gestures.py`（与 `scripts/check-appkit-isolation.py` 同为 Python）：
   - 参数为原版 `Resources` 目录（默认 `/Applications/WGestures.app/Contents/Resources`，不存在就**报错退出，不静默**）；
   - 按 `tr_bootstrap.json` 把每个 `Name` 换成中文（**查不到就报错列出，不猜**）；
   - `prefs.json` 抄原版但 `AutoStart` 改 `false`（`SkipVersion: null` 保留，测试覆盖了这条编码）；
   - 输出 `zWGestures/Resources/Defaults/{gestures.json,prefs.json}`，stdout 打印条数与差异摘要；
   - 出处与重生成方式写在**脚本 docstring + Makefile 注释 + `docs/ROADMAP.md`**，不额外加文档文件。
2. `Makefile` 加 `make default-gestures`（**不挂进 `build`** —— 只有维护者机器上有原版）。生成物**提交进仓库**。
3. **资源要落到 bundle 的 `Defaults/` 子目录**：XcodeGen 默认把 `.json` 平铺到 `Contents/Resources/` 根，需给该目录单独一条 **folder reference**；**以 `xcodebuild build` 后检查产物路径为准**（本工程第一次用资源文件夹，属实施时验证点）。
4. ZWGCore 侧新增纯函数入口（**接 URL，不读 bundle**，便于测试驱动）：`ConfigStore.importDefaultConfiguration(from directory: URL)`，与现有 `importLegacyConfiguration(directory:)` 同构，复用「`AutoStart` 以系统登录项为准」的纠正逻辑。
5. `ConfigController.start()`：`hasConfig` → reload；否则 `locateVersionDirectory() != nil` → `importLegacy()`；否则 → `importDefault()`。`Status` 增加 `.seeded(intents:)`（「已载入内置默认手势（48 条）」），`presentImportSummary()` 给这一支单独文案。
6. **首启体验**：`AppDelegate` 里 `if !hadConfig { settings.show() }` —— 否则 LSUIElement（无 Dock 图标）的用户只看到菜单栏一个小图标。
7. 新增单测（全部走 fixture，不依赖 App bundle）：无配置+无原版 → 48 条且 `拷贝` 绑定 ⌘C；有原版 → **仍优先导入原版**；已有自有配置 → 原样 reload；出厂默认 `WGConfigCodec` **逐键往返相等**；所有键名经 `WGKeyCode.classify` 无 unknown；`AutoStart` 与系统不一致 → 保留系统状态。
8. README / 介绍页增一节「没装过 WGestures 的人拿到的是什么」。

**版权提示**：出厂默认是原版打包的配置数据 + 它自带的中文译名表，属「配置数据」而非二进制/字体/图标/代码；页面明确「独立重新实现、非官方、无隶属关系」并链接官网。后备方案 = 换取手写精简默认，接口不变。

### 4.2 首启与权限
权限引导**已有**，只需补 4.1 第 6 点的「首启自动打开设置面板」。最小改动，可裁剪。

### 4.3 ad-hoc 更新后授权失效要主动提示
ad-hoc 的 designated requirement 基于 CDHash → **用户每更新一版，「辅助功能」授权就失效**：App 正常启动、菜单栏图标在，但画手势毫无反应，会当作新版 bug。在 `EngineController` 现有 `isPermitted` / `startIfPermitted` 基础上补一条**「未授权 / tap 装不上」的显式提示**（状态栏文案 + 只弹一次的弹窗），并写进 Release notes 与页面 FAQ。

---

## 5. 阶段三：发布产物

### 5.1 签名：ad-hoc
对下载者而言，ad-hoc 与「你本人自签名」**效果一样** —— 都过不了 Gatekeeper 的「Developer ID 签名 + 公证」。选 ad-hoc 是因为不依赖任何证书、CI 可复现。只在 `make dist` 用命令行覆盖 `CODE_SIGN_IDENTITY=-`，**不动 `project.yml` 的默认身份**（否则本机开发构建每次编译都会丢辅助功能授权）。`ENABLE_HARDENED_RUNTIME: NO` 保持。

### 5.2 `make dist`
```
1. 读 MARKETING_VERSION
2. xcodebuild -configuration Release（首次真正验证 Release 路径）
     CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO
3. 校验：codesign 显示 adhoc、lipo -archs 只有 arm64、版本号一致、Defaults/gestures.json 存在
4. zip：ditto -c -k --keepParent → dist/zWGestures-<v>-arm64.zip
5. dmg：hdiutil create -srcfolder <staging> -format UDZO
     staging = zWGestures.app + 指向 /Applications 的符号链接（不做自定义背景图/图标位置）
6. 固定文件名别名：dist/zWGestures-arm64.dmg、dist/zWGestures-arm64.zip
7. shasum -a 256 … > dist/SHA256SUMS
```
`.gitignore` 加 `dist/`。

### 5.3 Gatekeeper 说明 —— **必须实测后再写文档**
实测 5 项，结果写成**单一事实来源** `docs/INSTALL.md`（README 与页面都引用）：
1. 浏览器下载的 zip/dmg，`xattr -l` 是否带 `com.apple.quarantine`（预期：带）
2. **`curl -L` 下载的是否带（预期：不带）** —— 这是「curl 安装脚本 / Homebrew Cask 能绕开弹窗」的依据，**必须实测，不凭记忆写**
3. 本机 macOS 26 上「系统设置 → 隐私与安全性 → 仍要打开」的准确文案与路径
4. `xattr -dr com.apple.quarantine /Applications/zWGestures.app` 之后能否正常打开
5. 之后是否仍需单独授权「辅助功能」（预期：需要）

安装说明必须加粗：**把 App 拖进 Applications**，不要在 dmg 卷里直接运行。

### 5.4 发版流程
不做 CI 自动出包（runner 的 Xcode 与 Xcode 26 不一致，产物行为不保证一致；等 `app-build` 稳定一段再考虑）。本机 `make dist` + `gh release create v0.1.0 --notes-file docs/release-notes/0.1.0.md dist/…`。Release notes 必含：未签名说明 + Gatekeeper 步骤 + **更新后要重新授权辅助功能** + 只支持 Apple Silicon + 必须拖入 Applications + **「从 WGestures 导入」怎么用** + **界面目前仅中文**。发版时同步三处版本号（`project.yml` 的 `MARKETING_VERSION`、`site/index.html`、`CHANGELOG.md`）。发版后验证 `releases/latest/download/zWGestures-arm64.dmg` 能下到。

### 5.5 打包前安全扫描（硬性）
`make dist` 与建仓前各跑一次：
```bash
git ls-files | grep -iE "license\.json|\.p12$|\.pem$|\.key$" && exit 1
git grep -n "<激活码前缀>\|<邮箱前缀>" && exit 1
find <dist staging> -name "license.json"   # 产物内不得含
```
**规则**：任何从 `~/Library/Application Support/com.yingdev.wgestures/` 拷数据的步骤，**只允许拷 `2.3.3/` 子目录**，拷完立刻跑扫描。

---

## 6. 阶段四：`site/` 介绍页

### 6.1 结构（零构建、零外部依赖）
```
site/
  index.html        单文件：内联 CSS/JS、中英同页切换、响应式、prefers-color-scheme
  assets/           icon.png、shot-overlay.png、shot-settings.png、shot-menu.png、install-gatekeeper.png
  README.md         部署说明（rsync/scp + nginx 片段）
```
刻意不用 React/Vite/静态站框架。**不引用任何外部 CDN、网络字体或统计脚本**（断网也能正常显示）。中英切换用一小段内联 JS + `localStorage`，默认中文，支持 `?lang=en`；**无 JS 时中文主内容仍可读**。

### 6.2 内容与宣传层级

| 位置 | 内容 |
|---|---|
| **Hero** | 一句话 + 下载按钮 + 「版本 x.y.z · macOS 14+ · Apple Silicon」。主打**原生 Swift、Apple 芯片原生、新系统上也能用** |
| 截图 | 4 张 |
| 功能特性 | 8 条：右键手势 / 任意形状 / 按应用手势集且有继承 / 按手势启用禁用 / 轨迹实时可视化 / 冲突提示与排序 / 开机自启 / **兼容 WGestures 配置，一键导入你已有的手势**（中等位置，不是 hero） |
| 安装 | 下载 → 拖进 Applications → 首次打开（Gatekeeper 步骤，配图）→ 授权辅助功能 → 完成 |
| **从 WGestures 迁移** | 独立小节：首次启动自动导入；原版目录**只读不改**；也可随时手动重新导入 |
| **为什么会有 zWGestures**（致敬） | 见下方定稿文案 |
| **已知限制** | 界面目前仅中文；仅支持 Apple Silicon |
| FAQ | 未签名安不安全 / 会不会改我的原版配置 / **更新后手势没反应** / 怎么卸载 / 为什么只有 Apple Silicon |
| 页脚 | GitHub、MIT、免责声明 |

**致敬小节定稿文案**（可直接用）：

> **为什么会有 zWGestures**
>
> WGestures 2 是一款出色的鼠标手势工具。它的「手势＝操作步骤之和」「手势修饰键」「继承与重载」等设计是 zWGestures 的直接灵感来源；zWGestures 也刻意保持了与它配置文件格式的兼容，好让你已有的手势能直接搬过来。
>
> 原版 macOS 版最后一个版本是 2021 年 12 月的 2.3.3。它是基于 Mono / Xamarin.Mac 的 x86_64 应用，在 Apple 芯片 Mac 上依赖 Rosetta 运行。而 Apple 已宣布：[macOS 26.4 起](https://developer.apple.com/news/?id=w5ngl9k2)，启动依赖 Rosetta 的应用会收到系统提示；**macOS 27 是最后一个支持 Rosetta 的版本，之后 Intel-only 应用在 Apple 芯片 Mac 上将不再能运行**（少数老游戏除外）。
>
> 为了让这套用了多年的鼠标手势能继续在新系统上用下去，我用 Swift 从头写了一个原生版本。它是**独立的重新实现，不是官方版本，与原项目及作者 yingdev（Ying Yuandong）没有隶属关系**，不包含原版的任何二进制、字体、图标或激活码。
>
> 如果你还在用原版并且觉得它好用，请去 [yingdev.com/projects/wgestures2](https://www.yingdev.com/projects/wgestures2) 支持原作者。

语气上刻意避开「原版已死」这类判断，只陈述可核实的事实（最后一版日期、x86_64、Apple 公告原文）。

下载按钮指向 `https://github.com/ZilongYang/zWGestures/releases/latest/download/zWGestures-arm64.dmg`（靠 5.2 的固定文件名，**发版后不用改 HTML**）。版本号手工写在页面里，发版时一起改 —— 不请求 GitHub API（限流 60/小时/IP，且会给页面引入失败态）。

### 6.3 部署
只产出 `site/` + `site/README.md`（含 `rsync -avz --delete site/ user@host:/var/www/zwgestures/` 与 nginx 片段），**不碰你的服务器**。域名与路径由你定（你已有 `zlyum.com`，候选 `zlyum.com/zwgestures/` 或 `zwgestures.zlyum.com`）。

---

## 7. 明确不做

- App 界面英文化（**搁置到 v0.2.0**，本次只做 3.9 的三件便宜事）
- 不做 Developer ID 签名 / 公证（$99/年，免费账号拿不到 Developer ID 证书）
- 不做 CI 自动出包（暂）
- 不做自定义外观的 dmg
- 不用 React/Vite/静态站框架
- 不引入 Sparkle 自动更新
- 不做 Intel / Universal 支持（`ARCHS=arm64` 保持）
- 不改按手势禁用 `Enabled` 扩展字段的现有行为（有 `ConfigTests` 守卫）
- 不改 `LegacyConfigImporter` / `ConfigStore` 现有的旧路径行为
- 不额外增加文档文件（出处说明写进脚本 docstring 与 ROADMAP）

---

## 8. 执行顺序

**阶段零**
0. **把本计划原文写入 `docs/OPEN-SOURCE-PLAN.md`** + README 文档索引加一行

**阶段一 · 仓库可开源**
1. `LICENSE` + 商标免责声明
2. 测试 fixture 化（3.2）→ `make test` 0 failed / 0 skipped
3. `make bootstrap` + README 构建段（3.3）
4. CI 两个 job（3.4）+ 徽章
5. bundle ID 中性化（3.5）→ 重新 `xcodegen generate` → `make test` / `make build` / `make install` → 重新授权
6. 文档脱敏（3.6）
7. git 历史邮箱改写（3.7）
8. README 重构 + `README.en.md` + `CONTRIBUTING.md` + 两个模板（3.8）
9. App 界面多语言搁置的三件便宜事（3.9）

**阶段二 · 下载版可用**
10. `scripts/make-default-gestures.py` + `make default-gestures` → 生成并提交出厂默认（4.1）
11. `ConfigStore.importDefaultConfiguration` + `ConfigController` 三分支 + 首启开设置面板 + 单测（4.1）
12. ad-hoc 更新后授权失效的显式提示（4.3）
13. 实测 Gatekeeper 5 项 → `docs/INSTALL.md`（5.3）

**阶段三 · 出产物**
14. `make dist`（5.2）→ **本机真机跑完整手势回归**（Release 配置第一次被使用）
15. 截图 5 张（需你参与）

**阶段四 · 站点**
16. `site/index.html` + `assets/` + `site/README.md`

**阶段五 · 发布**
17. `CHANGELOG.md` + Release notes + 安全扫描（5.5）
18. 建远端 → push → `v0.1.0` tag → `gh release create`
19. 你部署站点

第 1–8 步每步跑 `make lint && make test`；第 14 步之后跑一次完整真机回归。

---

## 9. 最终验证清单

- [ ] `docs/OPEN-SOURCE-PLAN.md` 已生成，README 文档索引已链接
- [ ] 干净环境 + 无原版安装 + 删掉钥匙串证书 → `make bootstrap && make test && make build` 三步成功
- [ ] `make test` 输出 **0 failed / 0 skipped**
- [ ] CI 两个 job 全绿；`app-build` 断言到 `Contents/Resources/Defaults/gestures.json`
- [ ] `git grep -niE "<作者邮箱用户名>|@gmail|/Users/|\.dsh|com\.zilong|license\.json|<激活码前缀>"` 只剩新 bundle id
- [ ] `git log --format='%ae' | sort -u` 只有 noreply
- [ ] `git status --short` 干净；`build/`、`dist/`、`docs/icon/AppIcon.icns` 均未入库
- [ ] `Info.plist` 的 `CFBundleLocalizations` 与仓库实际资源一致（无 `en`）
- [ ] **新建 macOS 用户账号**：挂 dmg → 拖进 Applications → 按 `docs/INSTALL.md` 绕过 Gatekeeper → 授权辅助功能 → **开箱 48 条中文手势、画「上」触发拷贝**
- [ ] 出厂默认：`WGConfigCodec` 逐键往返相等；无 unknown 键名
- [ ] Release 产物：`Signature=adhoc`、`lipo -archs` 只有 arm64、`SHA256SUMS` 校验通过、产物内无 `license.json`
- [ ] `releases/latest/download/zWGestures-arm64.dmg` 可下载
- [ ] `site/index.html` **断网**打开正常、中英切换正常、无外部请求
- [ ] 本机重装后：辅助功能重新授权成功、开机自启可用、旧 LaunchAgent 已清

---

## 10. 风险

| 风险 | 对策 |
|---|---|
| **Release 配置从未跑过** | 一直只用 Debug，Release 优化可能暴露新的并发/actor 隔离问题（本项目踩过两次 `isMainExecutor` 崩溃）。第 14 步真机跑完整手势回归，不只看构建成功。 |
| **XcodeGen 资源文件夹是首次使用** | 默认会平铺 JSON 到 bundle 根；改用 folder reference，**以构建产物路径为准**验证。 |
| **ad-hoc 更新后授权失效** | 用户会当 bug。三处都写：App 内提示 + Release notes + 页面 FAQ。 |
| **用户不拖进 Applications** | 安装说明加粗强调。 |
| **出厂默认的版权** | 属配置数据 + 短功能译名，非二进制/字体/图标/代码；页面明确「独立重新实现、非官方、无隶属关系」并链接官网。后备方案 = 换取手写精简默认。 |
| **只能提供中文界面** | 英文用户可能因此放弃。对策：README.en + 英文介绍页 + Release notes 明确写明；ROADMAP 里把英文化列为 v0.2.0 第一优先。 |
| **改 bundle ID 伤到你在用的安装** | 要重新授权 + 重装 + 手工清旧 LaunchAgent。若想开源版与个人版并存，替代方案是把 `com.zilong.zwgestures` 留在 `main`、开源另开分支 —— 需要你明确。 |
| **改写历史** | 重写全部 36 个哈希。还没有远端所以安全；一旦已推过，就得改用 `git filter-repo` + 强制推送并协调其他克隆。 |
| **CI 镜像与 Xcode 26 不一致** | 以真实 workflow 结果为准，必要时 `setup-xcode` 固定版本。 |

---

## 11. 需要你亲自参与

1. **新建一个 macOS 用户账号做干净验证**（出厂默认 / Gatekeeper / 辅助功能授权）—— 唯一能真实验证「下载版可用」的办法。
2. **5 张截图**，轨迹叠加层那张需要在屏幕上画手势的一瞬间截。
3. **确认域名与路径**（site 部署）。
4. 批准之后我才执行 `gh repo create` / push / tag / Release —— 每一步单独再请示一次。
