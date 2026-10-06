# 0.3.0 发版打勾清单（2026-10-06 起）

> **本文是什么**：把**当次发版**要做的事拆成能照着打勾的步骤。做完即归档，只作历史参考。
> 本版主题 = 界面中英双语 + 手势名中文化（方案存档在 [`PLAN-2026-10-06-i18n.md`](PLAN-2026-10-06-i18n.md)）。
> 长期优先级与依据仍以 [`ROADMAP.md`](ROADMAP.md) 第 3 节为唯一真源。
> 上一版的清单见 [`RELEASE-CHECKLIST-0.2.0.md`](RELEASE-CHECKLIST-0.2.0.md)。

## 1. 发版前：我自己能做的（自动化）

- [x] `make lint`（含 AppKit 隔离守卫与「监听器必须传函数引用 / 禁止 `DispatchQueue.main.async`」两类）通过
- [x] `make test`：306 项全过，**连跑三轮**（第 1 期的语言切换测试曾因并行而随机失败，已改成纯函数接口）
- [x] `make build` 成功；产物 `Info.plist` 里 `CFBundleShortVersionString = 0.3.0`、`CFBundleVersion = 3`
- [x] 产物里默认包布局正确：`Defaults/zh-Hans/`、`Defaults/en/`、`Defaults/name-translations.json`
- [x] 产物里 `zh-Hans.lproj/InfoPlist.strings`、`en.lproj/InfoPlist.strings` 都在，`CFBundleLocalizations = [zh-Hans, en]`
- [x] 两份默认包**除手势名外逐键一致**，且**英文包 + 译名表 == 中文包**（测试钉住）
- [x] 全工程只剩日志与调试面板是中文（12 处，刻意保留）

## 2. 发版前：需要你在真机上过一遍的（人工闸门）

**双语**

- [ ] 设置 › 偏好设置 › 界面语言：切 English → 保存。菜单栏、两个分段标签、窗口标题**都要立刻变英文**
      （上一版这两个 AppKit 控件不会自己刷新，已修）
- [ ] 英文界面下把设置界面各页、命令编辑器、手势编辑器、各类弹窗都点一遍：**不该有残留中文**，
      也不该有被挤断行的标签（本版放宽了窗口与列宽）
- [ ] 切回「简体中文」→ 保存，一切恢复

**手势名中文化**

- [ ] 菜单栏「把英文手势名改为中文」：确认后列表里的 `Close` / `Web Search` 变成中文
- [ ] 改完看一眼配置目录的 `Backups/`：应当自动留了一份改前的 `config-*.json`
- [ ] 自己改名过的手势（如果有）**保持不变**
- [ ] （可选）启动弹窗：本次已把测试留下的「已问过」标记清掉，所以**下次启动应当会问一次**

**系统层**

- [ ] 更新后辅助功能授权若失效：按弹窗重新授权一次，画手势恢复正常
- [ ] 需要 AppleScript / Shell 脚本控制目标应用时，系统权限弹窗里的说明跟着界面语言走
      （中文系统显示中文，`en` 环境显示英文）

**回归面（本版不该碰的）**

- [ ] 画手势的手感、识别结果与 0.2.0 一致（本版没动识别与执行路径）
- [ ] `Web 搜索`（含剪贴板里放着图片时）、`退格`、`删除` 等闭环手势照旧
- [ ] 开机自启仍是「已开启（系统登录项）」；调试面板 `idx rebuilds` 停在本启动的 1 次

## 3. 发版步骤

- [x] CHANGELOG：`## [未发布]` → `## [0.3.0] - 2026-10-06`
- [x] 写 `docs/release-notes/0.3.0.md`（七条必含项：未签名说明、Gatekeeper 步骤、
      **更新后重新授权**、仅 Apple Silicon、必须拖进 Applications、怎么从 WGestures 导入、
      界面语言现状）
- [x] 三处版本号：`project.yml`（0.2.0→0.3.0、build 2→3）、`site/index.html`（v0.3.0）、CHANGELOG
- [x] `git push origin main`
- [x] `make dist`（⚠️ 用带完整权限的会话或正常终端跑：`diskutil image create from` 要挂载卷）
- [x] 核对产物：`0.3.0` / arm64 / `Signature=adhoc` / 默认包两份都在 / `lipo -archs` 只有 arm64
- [x] `git tag v0.3.0 && git push origin v0.3.0`，然后
      `gh release create v0.3.0 --title "zWGestures 0.3.0" --notes-file docs/release-notes/0.3.0.md`
      附上 `dist/` 里五个产物（两个版本化 + 两个固定名 + `SHA256SUMS`）
- [x] 验证 `releases/latest/download/zWGestures-arm64.dmg` 返回 200
- [x] 把站点重新部署一次（`tar` over SSH + 远端 `chown/chmod`，这台服务器**没有 rsync**）

**实际结果（2026-10-06 16:22 前后）**

| 步骤 | 结果 |
|---|---|
| push | `daaf9f6..1313e73`，工作树干净、与远端同步 |
| `make dist` | **第一次失败**：断言还在查旧的 `Defaults/gestures.json`（第 3 期把包改成按语言分目录了）。修正断言后通过，并新增「两份包除手势名外逐键一致」的产物级校验 |
| 产物核对 | `0.3.0` / build `3` / arm64 / `Signature=adhoc` / 两份默认包 + 译名表 + 两个 `.lproj` 都在 |
| tag + release | `v0.3.0`，标题「zWGestures 0.3.0」，五个产物齐、非草稿非预发布、已标记为 **Latest** |
| 下载地址 | `releases/latest/download/zWGestures-arm64.dmg` 实测 **200** |
| 站点 | 线上版本号 **v0.3.0**；`index.html` 与仓库**逐字节一致**（sha256 比对），4 张素材一致，HTTP→HTTPS 301 正常 |

## 4. 发版之后（下一轮）

- [ ] **404 页**（作者已确认要做）：`site/404.html`，与站点同风格的单文件；
      远端本来就有一个 130 字节的默认页，直接覆盖即可（部署是增量覆盖、不删除）
- [ ] **全新 macOS 用户账号验收**：挂 dmg → 拖进 Applications → Gatekeeper 放行 → 授权 →
      确认开箱 48 条手势；**并且分别用中文与英文系统各装一次**，确认默认包随语言切换
      （这一条同时完成 Release 配置的真机回归），顺手拍 `site/assets/install-gatekeeper.png`
- [ ] （可选）`site/assets/` 长缓存头：只用 `expires 30d;`，不要用 `add_header Cache-Control`
