import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

@Suite("命令：按键序列映射")
struct KeySequencePlanningTests {
    @Test("⌘C 被映射成带 Command 修饰的 C 键")
    func mapsCommandC() throws {
        let plan = WGCommandPlanner.plan(.keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"])
        ))
        #expect(plan.problems.isEmpty)
        #expect(plan.actions == [
            .keyStroke(modifiers: [0x37], flags: .maskCommand, keyCode: 0x08),
        ])
    }

    @Test("null 分隔的序列被拆成多次独立按键")
    func splitsMultiStepSequence() {
        let plan = WGCommandPlanner.plan(.keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_V", nil, "Return"])
        ))
        #expect(plan.actions == [
            .keyStroke(modifiers: [0x37], flags: .maskCommand, keyCode: 0x09),
            .keyStroke(modifiers: [], flags: [], keyCode: 0x24),
        ])
    }

    @Test("修饰键的顺序不影响结果")
    func modifierOrderDoesNotMatter() {
        let first = WGCommandPlanner.plan(.keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "Shift", "ANSI_T"])
        ))
        let second = WGCommandPlanner.plan(.keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Shift", "Command", "ANSI_T"])
        ))
        #expect(first.actions.count == 1)
        #expect(first.actions.first == second.actions.first)
    }

    @Test("无法识别的键名会被报告，不会静默丢弃")
    func reportsUnknownKeyNames() {
        let plan = WGCommandPlanner.plan(.keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_NotAKey"])
        ))
        #expect(plan.problems.count == 1)
        #expect(plan.problems[0].contains("ANSI_NotAKey"))
        // 仍然发送能识别的那部分
        #expect(plan.actions.isEmpty || plan.actions.count == 1)
    }

    @Test("IsSystemHotKey 为真时不激活目标应用，为假时激活")
    func systemHotKeyControlsActivation() {
        let normal = WGCommandPlanner.plan(.keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"])
        ))
        #expect(normal.activateTargetFirst)

        let global = WGCommandPlanner.plan(.keySequence(
            WGKeySequenceCommand(isSystemHotKey: true, keys: ["Command", "ANSI_C"])
        ))
        #expect(!global.activateTargetFirst)
    }

    @Test("空序列不产生动作")
    func emptySequenceProducesNothing() {
        let plan = WGCommandPlanner.plan(.keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: [])
        ))
        #expect(!plan.isExecutable)
        #expect(!plan.activateTargetFirst)
    }
}

@Suite("命令：其它类型")
struct OtherCommandPlanningTests {
    @Test("系统功能键索引映射到 NX 键值，且不激活目标应用")
    func mapsSystemFunctions() {
        let expected: [Int: (WGSystemFunction, Int)] = [
            0: (.brightnessDown, 3),
            1: (.brightnessUp, 2),
            2: (.previousTrack, 18),
            3: (.playPause, 16),
            4: (.nextTrack, 17),
            5: (.mute, 7),
            6: (.volumeDown, 1),
            7: (.volumeUp, 0),
        ]
        for (index, pair) in expected {
            let plan = WGCommandPlanner.plan(.systemFunctionKey(
                WGSystemFunctionKeyCommand(selectedIndex: index)
            ))
            #expect(plan.actions == [.systemFunction(pair.0)], "索引 \(index)")
            #expect(pair.0.nxKeyType == pair.1, "索引 \(index) 的 NX 键值")
            #expect(!plan.activateTargetFirst)
        }
    }

    @Test("越界的系统功能键索引会被报告")
    func rejectsOutOfRangeSystemFunction() {
        let plan = WGCommandPlanner.plan(.systemFunctionKey(
            WGSystemFunctionKeyCommand(selectedIndex: 99)
        ))
        #expect(!plan.isExecutable)
        #expect(!plan.problems.isEmpty)
    }

    @Test("Shell 脚本原样传入")
    func passesShellScriptThrough() {
        let plan = WGCommandPlanner.plan(.shellScript(
            WGShellScriptCommand(script: "open \"/Applications/Utilities/Terminal.app\"")
        ))
        #expect(plan.actions == [.runShellScript("open \"/Applications/Utilities/Terminal.app\"")])
        #expect(!plan.activateTargetFirst)
    }

    @Test("Web 搜索保留 URL 模板")
    func keepsSearchTemplate() {
        let plan = WGCommandPlanner.plan(.webSearch(
            WGWebSearchCommand(searchEngine: "https://www.google.com/search?q={0}")
        ))
        #expect(plan.actions == [.webSearch(template: "https://www.google.com/search?q={0}")])
    }

    @Test("不支持的命令类型被明确报告")
    func reportsUnsupportedCommand() {
        let plan = WGCommandPlanner.plan(.unknown(type: "LuaCommand"))
        #expect(!plan.isExecutable)
        #expect(plan.problems.first?.contains("LuaCommand") == true)
    }
}

@Suite("命令：与参考配置的一致性")
struct RealConfigurationKeyTests {
    /// The strongest check available for the key table: every key name that appears in the
    /// real configuration must resolve to an actual key code. A gap here would silently break
    /// a gesture the user already relies on.
    @Test(
        "参考配置里出现的每个键名都能映射到键码"
    )
    func everyKeyNameInTheRealConfigurationResolves() throws {
        let directory = FixtureConfig.directory
        let config = try LegacyConfigImporter.load(from: directory).config

        var keyNames: Set<String> = []
        var unknownKeys: [String] = []
        for target in config.allTargets {
            for intent in target.intents {
                guard case .keySequence(let sequence) = intent.command else { continue }
                for key in sequence.keys.compactMap({ $0 }) {
                    keyNames.insert(key)
                    if case .unknown = WGKeyCode.classify(key) {
                        unknownKeys.append(key)
                    }
                }
            }
        }

        #expect(keyNames.count > 20, "参考配置里应当有相当数量的键名，实测 \(keyNames.count)")
        #expect(unknownKeys.isEmpty, "以下键名没有对应键码：\(Set(unknownKeys).sorted())")
    }

    @Test(
        "参考配置里的每条命令都能规划出动作"
    )
    func everyCommandInTheRealConfigurationIsExecutable() throws {
        let directory = FixtureConfig.directory
        let config = try LegacyConfigImporter.load(from: directory).config

        var failures: [String] = []
        var count = 0
        for target in config.allTargets {
            for intent in target.intents {
                count += 1
                let plan = WGCommandPlanner.plan(intent.command)
                if !plan.isExecutable {
                    failures.append("\(intent.name)：\(plan.problems.joined(separator: "；"))")
                } else if !plan.problems.isEmpty {
                    failures.append("\(intent.name)（部分）：\(plan.problems.joined(separator: "；"))")
                }
            }
        }

        #expect(count == 52, "参考配置有 52 条手势，实测 \(count)")
        #expect(failures.isEmpty, "以下手势无法执行：\(failures)")
    }
}

@Suite("命令：摘要文案")
struct CommandSummaryTests {
    @Test("按键序列渲染成可读的组合键")
    func rendersKeySequences() {
        let summary = WGCommandPlanner.summary(of: .keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "Shift", "ANSI_T"])
        ))
        #expect(summary == "⌘+⇧+T")
    }

    @Test("系统功能键用自己的名字")
    func rendersSystemFunctions() {
        let summary = WGCommandPlanner.summary(of: .systemFunctionKey(
            WGSystemFunctionKeyCommand(selectedIndex: 7)
        ))
        #expect(summary == "增加音量")
    }

    @Test("鼠标与滚动步骤渲染成中文输入名")
    func describesInputKeys() {
        #expect(WGCommand.describe(inputKey: "MOUSE:1") == "鼠标右键")
        #expect(WGCommand.describe(inputKey: "MOUSE:0") == "鼠标左键")
        #expect(WGCommand.describe(inputKey: "Command") == "⌘")
        #expect(WGCommand.describe(inputKey: "ANSI_C") == "C")

        // 滚动的正负号方向：正值向上/向左，与配置文件里 VSCROLL:±n 的写法一致。
        // 注意 ROADMAP §7 仍把「量级如何分档」列为未验证，这里只断言方向。
        #expect(WGCommand.describe(inputKey: "VSCROLL:11") == "滚动↑")
        #expect(WGCommand.describe(inputKey: "VSCROLL:-11") == "滚动↓")
        #expect(WGCommand.describe(inputKey: "HSCROLL:5") == "滚动←")
        #expect(WGCommand.describe(inputKey: "HSCROLL:-5") == "滚动→")
    }
}

/// 2026-10-06：主线程曾被「取目标窗口标题」的辅助功能调用卡了 47 秒（ROADMAP §22）。
/// 那次之后 `WGCommandPlan.needsTargetWindowTitle` 决定要不要去问这件事 —— 只有 shell 脚本
/// 用得到 `WG_TARGET_WIN_NAME`，其余动作一个都不需要，这个性质必须钉住。
@Suite("动作规划：谁才需要目标窗口标题")
struct TargetWindowTitleRequirementTests {
    @Test("只有 shell 脚本需要窗口标题，其余动作都不需要")
    func onlyShellScriptsNeedTheWindowTitle() {
        let shell = WGCommandPlanner.plan(.shellScript(WGShellScriptCommand(script: "echo hi")))
        #expect(shell.needsTargetWindowTitle)

        let keys = WGCommandPlanner.plan(.keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"])
        ))
        #expect(!keys.needsTargetWindowTitle)

        let search = WGCommandPlanner.plan(.webSearch(
            WGWebSearchCommand(searchEngine: "https://example.com/?q={0}")
        ))
        #expect(!search.needsTargetWindowTitle)

        let systemKey = WGCommandPlanner.plan(.systemFunctionKey(
            WGSystemFunctionKeyCommand(selectedIndex: 4)
        ))
        #expect(!systemKey.needsTargetWindowTitle)

        let unknown = WGCommandPlanner.plan(.unknown(type: "LuaCommand"))
        #expect(!unknown.needsTargetWindowTitle)
    }

    @Test("shell 脚本与其它动作混不进同一份计划，所以这个标志不会漏")
    func planNeverMixesShellScriptsWithOtherActions() {
        // 一个命令只会规划出一类动作（见 WGCommandPlanner.plan），所以「有没有 shell 脚本」
        // 就是「要不要取标题」。
        for command: WGCommand in [
            .shellScript(WGShellScriptCommand(script: "true")),
            .keySequence(WGKeySequenceCommand(isSystemHotKey: true, keys: ["Command", "ANSI_V"])),
            .webSearch(WGWebSearchCommand(searchEngine: "https://example.com/?q={0}")),
        ] {
            let plan = WGCommandPlanner.plan(command)
            let hasShell = plan.actions.contains { if case .runShellScript = $0 { true } else { false } }
            #expect(plan.needsTargetWindowTitle == hasShell, "\(command.typeName) 的判断不一致")
        }
    }
}
