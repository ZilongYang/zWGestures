# 原版 WGestures 配置格式（勘察记录）

> 原版 `config.json` / `prefs.json` 的字段与语义是怎么一条条核出来的。改配置层之前读这一份。
>
> **这一份是 `ROADMAP.md` 拆分出来的参考文档**（2026-10-06 搬迁，内容原样保留）。
> 路线图里对应的章节只留结论与链接 —— 那里是「接手开发要读的」，「怎么查出来的」都在这里。

---

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

---

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
