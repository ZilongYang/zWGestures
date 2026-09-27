# zWGestures 路线图

源自已批准的实施方案。目标：在 Apple Silicon 上原生复刻 WGestures 2.3.3 (macOS) 的
可感知功能，并能直接导入现有配置。

## 阶段

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 工程骨架：git、XcodeGen、Info.plist、菜单栏 App、arm64 验证 | ✅ 完成 |
| P0b | 稳定的本机代码签名证书（避免每次重编都要重授辅助功能） | ✅ 完成 |
| P1 | 输入引擎：EventTap 生命周期、抑制/回放、起始超时、禁用自恢复、PanicGuard | ✅ 代码完成，待实机验证 |
| P2 | 配置层：完整 `Codable` 模型、旧配置导入器、偏好项 | ✅ 完成（导入与原文件逐键一致） |
| P3 | 识别层：简单手势、任意形状（DTW）、序列匹配 | ⏳ |
| P4 | 执行层：`KeySeqCommand` / `WebSearchCommand` / `ShellScriptCommand` / `SystemFunctionKeyCommand`，目标解析 | ✅ 完成（分组与触发矩阵继承待 P5） |
| P5 | 边角与滚轮触发、触发矩阵、轨迹可视化 Overlay、开机自启 | 🚧 触发矩阵已完成，边角/滚轮/Overlay 待做 |
| P6 | 设置界面（简版）：目标列表、手势列表、触发矩阵、命令编辑器 | ⏳ |
| P7 | 与原版逐项对照验收、多屏/全屏/长跑加固 | ⏳ |
| P8 | 完整可视化编辑器、分组、拖放排序、拼音搜索、动画回放 | ⏳ |

## 原版数据模型（已勘察确认）

配置文件：`~/Library/Application Support/com.yingdev.wgestures/<version>/gestures.json`
与 `prefs.json`。

```
{ "General": Target, "Groups": [Target], "Apps": [Target], "Specials": [Target] }
Target  = { Id, Name, Intents: [Intent], Triggers: [{ Def: [Step], Enabled: Bool }] }
Intent  = { Name, ExecuteOnRecognize, Gesture: [Step], Command: Command }
Step    = KeyDownStep{Key} | StrokeStep{IsSimple, P} | MoveToEdgeCornerStep{EdgeCorner:{Value}} | ScrollStep{IsHorizontal}
Key     = "MOUSE:0..2"（0=左 1=右 2=中）| "VSCROLL:±n"
Command = KeySeqCommand{IsSystemHotKey, Keys} | WebSearchCommand{SearchEngine}
        | ShellScriptCommand{Script} | SystemFunctionKeyCommand{SelectedIndex}
```

### 轨迹编码（已用快捷入门图与命令语义交叉验证）

- `IsSimple = true`：`P` 是扁平点数组，**就是绘制顺序**——第一对点就是笔画起点
  （也是原版 UI 画触发符号的位置），网格单位 **50**。
  **y 轴向上为正**（数学坐标系），转成屏幕坐标要取反 y。
- `IsSimple = false`：`P` 是**原始屏幕坐标**点列（y 全部为正，与 `CGEvent.location`
  同一坐标系），既不倒序也不翻转。

> ⚠️ 这里踩过一次坑。最初我把 `P` 读成了**倒序**、且把 y 读成了**向下为正**。
> 这两个错误对纯竖直笔画（`拷贝`↑ / `粘贴`↓）恰好互相抵消，所以看起来是对的，
> 而所有横向与折线手势都被静默地算成了镜像或旋转的版本。
>
> 抓住它的是两条独立证据：
> 1. **命令语义**：`Back` 绑定 ⌘[，画出来必须是**向左**；错误规则给出的是向右。
> 2. **原版自带的快捷入门图**：「拷贝」的圆圈（起点）画在箭头**下方**；
>    「关闭标签页」是**下→右**；「退出」是**下→左**。
>
> 现在这些都被 `StrokeDirectionTests.swift` 固化成语义断言 —— 用真实配置里的
> `P` 原值直接断言方向，任何编码改动都会立刻失败。

### 系统功能键

`SelectedIndex` 0..7 = 亮度-、亮度+、上一曲、播放/暂停、下一曲、静音、音量-、音量+
（映射到 `NX_KEYTYPE_*`）。

### 脚本环境变量

`WG_TARGET_PID`、`WG_TARGET_EXE`、`WG_TARGET_WID`、`WG_TARGET_APP_NAME`、
`WG_TARGET_WIN_NAME`、`WG_MOUSE_X`、`WG_MOUSE_Y`、`WG_MOUSE_Y_FLIP`。

## 待验证清单

这些细节无法从配置文件推断，需要在 P1/P3 用小实验定论，必要时与运行中的原版对照：

1. **`EdgeCorner.Value` 位掩码映射** —— ✅ 已确认：**Top=1, Right=2, Bottom=4, Left=8**。
   依据原版自带快捷入门图（音量卡片=监视器顶部黑条、亮度卡片=底部黑条、
   切换任务卡片=屏幕左上角角括号、终端/活动监视器=左右镜像对）。
   已固化为 `ConfigTests.edgeMaskMatchesTheOriginalArtwork`。
2. **后缀修饰步骤的按压时机** —— `剪切=[右↑, 左键]` 与 `拷贝=[右↑]` 的区别在于
   后缀步骤；该按键必须在画线前、画线中还是画完后仍按住？
3. **`VSCROLL:n` 的量级分档阈值**（原版记录了 1/11/12/13 等原始滚动量）。
4. **`CGEventTap` 是否还需要「输入监控」权限**（除辅助功能之外）。
5. **左键触发「不阻止点击」的确切条件**。
6. **跨屏手势的坐标归一与边界处理**。

## 明确的边界

- 不复制、不打包原版任何二进制、字体、图标、资源或激活码；只做配置格式互通。
- 不复刻 Windows 版特有功能：自定义菜单、Lua、Cmd 脚本、运行/激活应用程序。
- 不做 App Store 上架（沙箱与全局输入拦截互斥）。
