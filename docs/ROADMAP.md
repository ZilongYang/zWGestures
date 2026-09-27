# zWGestures 路线图

源自已批准的实施方案。目标：在 Apple Silicon 上原生复刻 WGestures 2.3.3 (macOS) 的
可感知功能，并能直接导入现有配置。

## 阶段

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 工程骨架：git、XcodeGen、Info.plist、菜单栏 App、arm64 验证 | ✅ 完成 |
| P0b | 稳定的本机代码签名证书（避免每次重编都要重授辅助功能） | ✅ 完成 |
| P1 | 输入引擎：EventTap 生命周期、抑制/回放、起始超时、禁用自恢复、PanicGuard | ✅ 代码完成，待实机验证 |
| P2 | 配置层：完整 `Codable` 模型、旧配置导入器、偏好项 | ⏳ |
| P3 | 识别层：简单手势、任意形状（DTW）、序列匹配 | ⏳ |
| P4 | 执行层：`KeySeqCommand` / `WebSearchCommand` / `ShellScriptCommand` / `SystemFunctionKeyCommand`，目标解析 | ⏳ |
| P5 | 边角与滚轮触发、轨迹可视化 Overlay、菜单栏完整化、开机自启 | ⏳ |
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

### 轨迹编码（已用快捷入门示意图交叉验证）

- `IsSimple = true`：`P` 是扁平点数组，**倒序存储**——最后一个点恒为笔画起点 `(0,0)`，
  坐标 **y 轴向上为正**，网格单位 **50**。校验：`Copy=[0,-50,0,0]`→↑、
  `Paste=[0,50,0,0]`→↓、`Web Search=[0,0,0,50,0,0]`→闭合竖环、
  `Backspace=[0,0,-50,0,0,0]`→闭合横环、`Fullscreen`/`Minimize` 互为镜像。
- `IsSimple = false`：`P` 是原始屏幕坐标点列，需要归一化 + DTW 匹配。

### 系统功能键

`SelectedIndex` 0..7 = 亮度-、亮度+、上一曲、播放/暂停、下一曲、静音、音量-、音量+
（映射到 `NX_KEYTYPE_*`）。

### 脚本环境变量

`WG_TARGET_PID`、`WG_TARGET_EXE`、`WG_TARGET_WID`、`WG_TARGET_APP_NAME`、
`WG_TARGET_WIN_NAME`、`WG_MOUSE_X`、`WG_MOUSE_Y`、`WG_MOUSE_Y_FLIP`。

## 待验证清单

这些细节无法从配置文件推断，需要在 P1/P3 用小实验定论，必要时与运行中的原版对照：

1. **`EdgeCorner.Value` 位掩码映射** —— 已确定 4 个单值 1/2/4/8 互为相邻环
   （因为 3/6/9/12 都是对角，且 1|2=3、2|4=6、4|8=12、8|1=9），
   即 `{Top,Right,Bottom,Left}` 或 `{Top,Left,Bottom,Right}` 两种镜像解二选一。
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
