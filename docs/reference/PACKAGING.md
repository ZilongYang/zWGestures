# 打包与发布（默认手势包 / Gatekeeper / make dist）

> 出厂默认手势包怎么生成、Gatekeeper 实测踩到的坑、`make dist` 的硬要求。发版前读这一份。
>
> **这一份是 `ROADMAP.md` 拆分出来的参考文档**（2026-10-06 搬迁，内容原样保留）。
> 路线图里对应的章节只留结论与链接 —— 那里是「接手开发要读的」，「怎么查出来的」都在这里。

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

生成物 `zWGestures/Resources/Defaults/{zh-Hans,en}/{gestures.json,prefs.json}` + `name-translations.json` **提交进仓库**，但**不挂进 `build`**
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
