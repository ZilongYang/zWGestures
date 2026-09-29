# 测试用的参考配置

`legacy/2.3.3/` 是一份**真实的 WGestures 2.3.3 配置副本**：原版的默认手势集，加上作者自己的
少量改动（删掉 `Quit`/`Kill`，多了 `退出`/`重新打开`/`重新载入`/`其他窗口`/`上一应用`/`下一应用`
六条中文手势）。它没有任何个人信息 —— 已确认不含邮箱、激活码、个人路径。

## 为什么提交进仓库

兼容性测试原先直接读本机安装：

```
~/Library/Application Support/com.yingdev.wgestures/<版本>/
```

这有两个后果：没装过原版的机器上，带 `.enabled(if:)` 的 15 条测试**静默跳过**（其中包含抓过两个
真实缺陷的「逐键往返相等」守卫，等于 CI 完全没有兼容性保障），而 `SettingsModelTests` 里那条漏了
门控的测试会直接**失败**。改成读这份副本之后，`make test` 在任何机器上都跑同一套断言。

请通过 `FixtureConfig.directory` 访问，不要写死路径：

```swift
let directory = FixtureConfig.directory
let config = try LegacyConfigImporter.load(from: directory).config
```

## ⚠️ 改了这个副本，就要同步改断言

那些测试里的具体数字（全局 49 条、Finder 3 条、统计 52 条、`StrokeStep` 39、
`KeySeqCommand` 38、`StartDragTimeout` 250 …）都是**针对这份文件**的基线。换文件必然要一起改，
否则失败信息会指向正确的地方。

## 来源与重新抓取

来源目录只允许是原版的**版本子目录**：

```
~/Library/Application Support/com.yingdev.wgestures/2.3.3/{gestures.json,prefs.json,Version}
```

⚠️ **绝对不要拷上一级目录**：`~/Library/Application Support/com.yingdev.wgestures/` 下的
`license.json` 含购买者的邮箱与激活码，`LastLaunchedVersion` 是机器状态。拷完立刻检查：

```bash
# 把两个占位符换成真实值（购买者邮箱前缀、激活码前缀）后再跑
grep -rniE "<邮箱前缀>|Serial|<激活码前缀>|/Users/" ZWGCore/Tests/ZWGCoreTests/Fixtures/
```

`Version` 文件带 UTF-8 BOM（导入器靠它判版本号），拷贝时要保持原样。

## 生产环境用的出厂默认不在这里

给新用户的**出厂默认手势包**是另一份文件（`zWGestures/Resources/Defaults/`），由
`scripts/make-default-gestures.py` 从原版 App 内自带的 `Contents/Resources/gestures.json`
生成，名字来自原版自带的中文译名表。两者用途不同，不要合并。
