# 开机自启（P9）

> `SMAppService` 与 LaunchAgent 双机制、系统状态才是真源、以及这台机器上手工收尾做过什么。
>
> **这一份是 `ROADMAP.md` 拆分出来的参考文档**（2026-10-06 搬迁，内容原样保留）。
> 路线图里对应的章节只留结论与链接 —— 那里是「接手开发要读的」，「怎么查出来的」都在这里。

---

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
