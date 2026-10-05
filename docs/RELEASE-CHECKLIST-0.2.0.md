# 0.2.0 发版打勾清单（2026-10-06 起）

> **本文是什么**：把**当次发版**要做的事拆成能照着打勾的步骤。做完即归档，只作历史参考。
> 实施这批修复的**方案**存档在同目录的 [`PLAN-2026-10-06.md`](PLAN-2026-10-06.md)；
> 长期优先级与依据仍然以 [`ROADMAP.md`](ROADMAP.md) 第 3 节为唯一真源，
> 本文只覆盖「这一次发版」。
> 发版流程的完整依据见 [`OPEN-SOURCE-PLAN.md`](OPEN-SOURCE-PLAN.md) 第 5.4 节。

## 0. 背景（一句话）

用户报的三个问题全部修完并已实机验收通过：① 手势的横都那么明显了还不算「关闭」；
② 三段手势按横的长短在 `Enter` / `Minimize` 之间跳；③ 松手后动作偶尔慢半拍。
现在要走的是「再测一轮 → push → 发一个新版本」。

## 1. 今天已完成（本地两条提交，**尚未 push**）

| 提交 | 内容 | 验证 |
|---|---|---|
| `26d6a9d` | 手势识别改成按「形状结构」判定 | 在该提交的树里单独跑 `make test`：283 项全过 |
| `71d2fb0` | 修「松手后动作偶尔慢半拍」+ 用户输入导致的 tap 停用立刻恢复 | `make lint` 通过、284 项全过、`make build` 成功、已 `make install` 并实机验收 |

关键数字（依据与完整数据见 [`ROADMAP.md`](ROADMAP.md) 第 21 节）：

- 截图那条「竖 467 / 横 210」的 L 到「关闭」：**0.109（不命中）→ 0.063**。
- 竖横比 0.4~4.0 全部命中「关闭」，且不再滑向 `Enter` / `Minimize` / `Paste`。
- 三段 `Enter` 的中间横 0.4×~3× 全部命中 `Enter`。
- 真正不同的形状之间最近仍有 **0.283** 的余量（`Enter` vs `Fullscreen`）。
- 热路径没有因此变慢：`scoredCandidates` **376~395 µs**（多批取最小；`ROADMAP` 第 19 节里旧度量的
  403 µs 是当时的单批均值，两者不能直接相减，但同一量级）。
- 闭环手势（`Web 搜索` / `退格` / `删除`）**行为不变**——它们继续走原来的弧长度量。

## 2. 待你做的实机回归（发版前唯一的人工闸门）

### 2.1 新行为

- [ ] 画一条**竖明显比横长**的「下→右」→ 命中**关闭**（不再「画了没反应」）。
- [ ] 把同一条 L 的横画长一些 → 仍是关闭，不跳 `Enter` / `Minimize`。
- [ ] 三段「竖→横→竖」把横画长 → 稳定是 `Enter`；`下→右→上` / `上→右→下` 分别是
      `Minimize` / `Fullscreen`。

### 2.2 回归面（不该有变化）

- [ ] 闭环手势：`Web 搜索`（上→原路返回）、`退格`、`删除` 仍按「细长环」命中；正圆仍不命中。
- [ ] 手势修饰键：`拷贝`（不按左键）与 `剪切`（画线时按住左键）都能用；`粘贴` / `粘贴并回车` 同理。
- [ ] 应用目标继承：Brave 里自有手势优先、其余继承全局仍然生效。
- [ ] 设置界面：形状冲突告警、按列表顺序调优先级、按手势禁用三者行为不变；
      录制笔画时引擎暂停、关闭后按原状态恢复。
- [ ] 开机自启：菜单仍显示「已开启（系统登录项）」。

### 2.3 读数（调试面板：`make run-debug`，或菜单栏打开）

- [ ] `idx rebuilds` 停在启动时的 **1**；**只有**改配置（保存 / 导入 / 换目标）才涨。
      ⚠️ 如果它每 3 秒自己涨，说明慢半拍那个修复没生效，立刻反馈。
- [ ] `交接 X ms` 长期是个位数毫秒；`最差 Y ms` 偶尔几十毫秒可接受，长期几百毫秒要反馈。
- [ ] `timeouts` = 0，`tap` = running。
- [ ] （可选）挂 1~2 小时后看 `~/Library/Logs/DiagnosticReports/zWGestures-*.ips` 有没有新文件。

## 3. 发 0.2.0

版本号取 **0.2.0**：识别判据变了、行为可见，0.x 里按 minor 走比 patch 合适。
（想改成 0.1.1 也行，但 `CHANGELOG` 里「行为变更」那段的措辞要跟着降级成「bug 修复」。）

- [ ] **CHANGELOG**：把开头的 `## [未发布]` 改成 `## [0.2.0] - <发版日期>`。
- [ ] **写 `docs/release-notes/0.2.0.md`**：以 `docs/release-notes/0.1.0.md` 为模板（下载表、
      首次放行、校验和那几节照抄，只改版本号），正文换成这次的用户视角描述。
      **必含七条**：未签名说明、Gatekeeper 步骤、**更新后要重新授权辅助功能**、
      仅 Apple Silicon、必须拖进 Applications、「从 WGestures 导入」怎么用、界面目前仅中文。
- [ ] **同步三处版本号**：
  - [ ] `project.yml` 的 `MARKETING_VERSION`（`0.1.0` → `0.2.0`）与 `CURRENT_PROJECT_VERSION`（`1` → `2`）
  - [ ] `site/index.html` 第 181 行附近的 `v0.1.0 · macOS 14+ · Apple Silicon`
  - [ ] `CHANGELOG.md`（上面已覆盖）
- [ ] **push**：`git push origin main`
- [ ] **`make dist`** —— ⚠️ **必须在正常终端里跑**：脚本用 `diskutil image create from`，会挂载卷，
      受限沙箱里连最小用例都失败。脚本自带两条硬断言（产物不含 `get-task-allow`、
      不泄露构建者 home 路径），失败会直接退出。
- [ ] **打 tag 并建 release**：
  ```bash
  git tag v0.2.0 && git push origin v0.2.0
  gh release create v0.2.0 --notes-file docs/release-notes/0.2.0.md \
    dist/zWGestures-0.2.0-arm64.dmg  dist/zWGestures-arm64.dmg \
    dist/zWGestures-0.2.0-arm64.zip  dist/zWGestures-arm64.zip \
    dist/SHA256SUMS
  ```
  **固定文件名那两个不能改名** —— 站点下载按钮指向
  `releases/latest/download/zWGestures-arm64.dmg`，靠它发版后不用改 HTML。
- [ ] **发版后验证**：该地址能下到且是新版；`site/index.html` 上的版本号与按钮一致；
      顺手复跑 `OPEN-SOURCE-PLAN.md` 第 9 节里「Release 产物」那几条
      （`Signature=adhoc`、`lipo -archs` 只有 arm64、SHA256 校验通过、产物内无 `license.json`）。

## 4. 发版之后（不急，但别忘了）

- [ ] **`site/404.html`**：与站点同风格的单文件；替换它**不需要改 nginx 配置**。
- [ ] **全新 macOS 用户账号验收**：挂 dmg → 拖进 Applications → 按 `docs/INSTALL.md` 放行
      Gatekeeper → 授权辅助功能 → 确认**开箱 48 条中文手势**、画「上」触发拷贝。
      同时完成 Release 配置的真机回归；顺手拍 `site/assets/install-gatekeeper.png`，
      拿到图后把 `site/index.html` 安装那节里注释掉的 `<figure>` 取消注释。
- [ ] （可选）`site/assets/` 长缓存头：只用 `expires 30d;`，**不要**用
      `add_header Cache-Control`（nginx 的子级 `add_header` 会覆盖父级，把 HSTS 头抹掉）。

## 5. 今天明确不做

- **不 push、不发版**，等你测完（你已明确）。
- 不顺手改长期项：P7 多屏/全屏/长跑验收、P8 分组与拼音搜索、P5 触发矩阵与边角/滚轮、
  完整可视化编辑器——这些排在下一个版本，见 [`ROADMAP.md`](ROADMAP.md) 第 3 节第 4~7 项。
- 三个已知但**不阻塞发版**的小项（需要时单开）：
  录制器的拟合残差（竖横比大的 L 目前会存成自由形状，只是不好看）、
  四条「∧」自由形状手势（`重新载入`/`其他窗口`/`下一应用`/`上一个应用`）互相抢、
  `Terminal` / `Activity Monitor` 两条退化重复定义。

## 6. 怎么确认「今天这一版装的是哪次编译」

设置窗口标题与底部状态栏都显示 `BuildInfo.buildStamp`（可执行文件写入时间）。
当前装到 `/Applications` 的那份是 **02:09** 左右构建的，对应提交 `71d2fb0`。
