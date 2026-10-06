# 应用图标

> 图标为什么走 asset catalog 而不是老的 `.icns`（macOS 26+ 的 AppKit 路径会渲染成空白）、怎么重新生成。
>
> **这一份是 `ROADMAP.md` 拆分出来的参考文档**（2026-10-06 搬迁，内容原样保留）。
> 路线图里对应的章节只留结论与链接 —— 那里是「接手开发要读的」，「怎么查出来的」都在这里。

---

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
