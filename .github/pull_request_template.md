## 这个 PR 做了什么

<!-- 一句话说清楚。修 issue 的话写 "Fixes #123"。 -->

## 怎么验证的

<!-- 写清步骤；涉及手势的话说明画了什么形状、在哪个应用里。 -->

```bash
make lint && make test
```

## 提交前清单

- [ ] `make lint && make test` 通过（**0 failed**）
- [ ] 新增/修改的逻辑有测试覆盖；纯 UI 或环境相关的改动，在下面说明了为什么测不了
- [ ] 可测试的纯逻辑放在 `ZWGCore` 里，而不是 App target（否则 CI 够不着）
- [ ] 我遵守了 [`CONTRIBUTING.md`](../CONTRIBUTING.md) 的三条硬约定
      （AppKit 覆写标 `nonisolated`、不在 `Timer` block 里碰 actor 隔离状态、事件 tap 不捕获键盘）
- [ ] 没有把个人标识（邮箱、主目录绝对路径、激活码）带进代码或文档
- [ ] 改了 `project.yml` 的话，已经跑过 `xcodegen generate` 并把生成的工程一起提交

## 为什么某些改动没有测试

<!-- 例如：需要在实机上画手势才能验证、依赖特定 macOS 版本行为。没有可删掉本节。 -->

## 界面改动

<!-- 有界面变化就贴一张截图。没有可删掉本节。 -->

## 需要 reviewer 特别注意

<!-- 例如：改了并发/线程模型、改了配置格式、动了 EventTap 的行为、有破坏性变更。 -->
