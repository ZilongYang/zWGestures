# 安装说明（macOS）

> 本文是 Gatekeeper / 安装步骤的**单一事实来源**：[`README.md`](../README.md) 与介绍页都引用这里。
> 文末「这些结论是怎么来的」列出了每一项是实测还是引用系统原文 —— 没有凭印象写的条目。

zWGestures **没有 Apple 开发者签名，也没有公证**（公证需要 99 美元/年的付费开发者账号）。
所以从网上下载之后，macOS 会拦你一次。这是预期行为，不是文件损坏。

## 下载与安装

1. 下载 `zWGestures-arm64.dmg`（或 `.zip`）。
2. 打开 dmg，**把 `zWGestures.app` 拖进 `Applications`**。
3. **不要在 dmg 卷里直接双击运行。** dmg 卷是只读的、随时会被卸载，而且系统会把卷内运行的应用
   移置（translocate）到一个随机只读路径。后果：开机自启注册的是那个临时路径，重启后就失效；
   系统对应用的识别也会变得不稳定。**必须先拖进 Applications 再运行。**
4. 首次打开会被系统拦下（见下一节）。
5. 放行后打开应用，到**系统设置 › 隐私与安全性 › 辅助功能**里勾选 zWGestures。
   没有这个权限，手势引擎不会启动 —— 菜单栏会明确写出「等待辅助功能授权」或「授权已失效」。

## 首次打开被系统拦下：怎么办

**现象**：双击之后应用好像启动了、随即又退出；或者只看到「无法打开」的提示。
菜单栏可能一闪而过。

**原因**：macOS 会先启动它、同时让 `syspolicyd` 在后台评估，评估不通过再把它结束掉。
本机实测（macOS 27）：从启动到被结束约 **19.6 秒**，系统日志里的原话是
`Gatekeeper policy blocked execution`。

**放行步骤**：

1. 打开**系统设置 › 隐私与安全性**，向下滚动到**安全性**一节。
2. 那一节会出现一行：**`已阻止“zWGestures”以保护Mac。`**
3. 点右边的**`仍要打开`**，按提示用 Touch ID 或密码确认。
4. 回到 Applications **再双击一次** zWGestures。

在 Finder 里双击时，如果系统给出的是对话框而不是直接退出，正文是：
**`Apple无法验证“zWGestures”是否包含可能危害Mac安全或泄露隐私的恶意软件。`**
这个对话框上的按钮**不能**放行（macOS Sequoia 起苹果移除了「按住 Control 点按 → 打开」这条老路），
必须按上面的步骤去系统设置。

放行一次之后，这个版本就不再被拦了 —— 直到你下载下一个版本。

## 另外三条放行路径

`仍要打开` 需要点界面。下面两条适合命令行或批量安装：

### 直接去掉隔离标记

```bash
xattr -dr com.apple.quarantine /Applications/zWGestures.app
```

本机实测：去掉之后应用正常运行，**不再被移置**，也不会再被评估。

> ⚠️ 这条命令等于对本应用关闭 Gatekeeper 检查。只在你自己确认过下载来源时使用。

### 用 `curl` 下载的包本身就没有标记

本机实测：`curl -sSL` 下载的 zip 与 dmg **都不带** `com.apple.quarantine`，因此打开时不会触发拦截。
所以「用脚本 / Homebrew Cask 安装」这条路是可行的，也正是它能绕开弹窗的原因。

（对照：**浏览器下载一定会带**这个标记。本机 `~/Downloads` 里由 Edge、Arc、AirDrop 保存的文件
全部带着它，形如 `0083;64d30c02;Microsoft Edge;`。）

## 授权「辅助功能」

这是**独立于 Gatekeeper 的另一步，任何放行方式都省不掉**。本机实测：去掉隔离标记后能正常启动的
Release 副本，日志里依然是 `accessibility trusted: false`。

- 系统设置 › 隐私与安全性 › 辅助功能 → 勾选 zWGestures。
- 勾选后**不需要重启应用**：它会自己发现授权并把引擎拉起来（菜单栏文案会变）。
- 菜单栏图标 →「辅助功能权限」可以直接跳到那个面板。

## 常见问题

**更新之后画手势没反应？**
几乎一定是授权失效了。未签名的构建每次编译都会改变系统用来识别它的指纹，所以**每更新一版都要
重新授权一次**。此时应用会主动弹一次说明并给出「打开系统设置」按钮；菜单栏也会写
「辅助功能权限：已失效（点击重新授权）」。到辅助功能列表里把 zWGestures 取消勾选再勾上即可。

**会不会改我的原版 WGestures 配置？**
不会。zWGestures 只**读**原版目录，配置写到自己的
`~/Library/Application Support/zWGestures/`，并在覆盖前自动备份（各留最近 10 份）。

**为什么只有 Apple Silicon？**
工程的 `ARCHS` 就是 `arm64`，Intel 机器构建不了。原版 WGestures 是 x86_64 应用，靠 Rosetta 运行 ——
zWGestures 存在的理由之一就是 Rosetta 即将退出（见 README 的「为什么会有 zWGestures」）。

**怎么卸载？**
1. 菜单栏图标 → 退出 zWGestures；
2. 把 `/Applications/zWGestures.app` 拖进废纸篓；
3. 如果开过开机自启，到系统设置 › 通用 › 登录项 里删掉它；再检查
   `~/Library/LaunchAgents/io.github.zilongyang.zwgestures.plist` 是否存在，存在就删掉；
4. 需要连配置一起清掉的话，删 `~/Library/Application Support/zWGestures/`；
5. 到 系统设置 › 隐私与安全性 › 辅助功能 里把 zWGestures 移除（列表里可能有新旧的重复条目，
   都删掉即可）。

## 这些结论是怎么来的

实测于 2026-09-30，macOS 27.0（26A428），M1 Pro。用本机 `make dist` 之前手工构造的
Release + ad-hoc 签名产物（zip 与 dmg 各一份）。

| 结论 | 来源 |
|---|---|
| 浏览器下载会带 `com.apple.quarantine` | **实测证据**：本机 `~/Downloads` 里 5 个由 Microsoft Edge / Arc / sharingd 保存的文件都带该属性 |
| `curl -L` 下载**不带** | **实测**：本地 HTTP 服务 + `curl -sSL` 下载 zip 与 dmg，`xattr -p com.apple.quarantine` 均报 `No such xattr`（只有 `com.apple.provenance`） |
| 带标记时「先启动、后被系统结束」且 `open` 返回 0 | **实测**：`open` 退出码 0，进程被移置到 `…/T/AppTranslocation/<UUID>/d/`，19.6 秒后 `syspolicyd` 记录 `Terminating process due to Gatekeeper rejection`，kernel 记 `Security policy would not allow process` |
| 系统设置里的文案与路径 | **系统原文**：从 `/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable` 取出 —— `已阻止“%@”以保护Mac。`、`仍要打开`、`Apple无法验证“%@”是否包含可能危害Mac安全或泄露隐私的恶意软件。`；配合 `syspolicyd` 记录的 *Gatekeeper denial breadcrumb (open)*（系统设置里那一行的来源） |
| `xattr -dr` 之后能正常打开、且不再被移置 | **实测**：移除后打开，等 25 秒（超过 19.6 秒的评估窗口）仍存活 |
| 仍需单独授权辅助功能 | **实测**：能正常启动的那个 Release 副本日志里 `accessibility trusted: false` |

**没有实测的一项**：在系统设置里点「仍要打开」之后应用确实能打开。这是苹果官方的放行路径，
本次只验证了它的入口（那句`已阻止…`与按钮文案、以及系统确实记下了这条拒绝）；
真正的点击验证放在「全新 macOS 用户账号开箱」那一步做。
