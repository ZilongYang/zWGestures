import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

@MainActor
@Suite("设置：命令编辑器")
struct CommandEditorModelTests {
    @Test("按键序列：能读出步骤、追加步骤、删除步骤")
    func editsKeySequences() {
        // ⌘V 然后 ↩ —— 配置里用 null 当作步骤分隔符。
        let model = CommandEditorModel(command: .keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_V", nil, "Return"])
        ))
        #expect(model.kind == .keySequence)
        #expect(model.keySteps == [["Command", "ANSI_V"], ["Return"]])
        #expect(model.keySequenceSummary == "⌘+V ↩")
        #expect(!model.isDirty)

        // 新录一步：修饰键排在前面，且去重。
        #expect(model.appendStep(["ANSI_C", "Command", "Command"]))
        #expect(model.keySteps == [["Command", "ANSI_V"], ["Return"], ["Command", "ANSI_C"]])
        #expect(model.keySequenceSummary == "⌘+V ↩ ⌘+C")
        #expect(model.isDirty)

        // 空步骤不接受。
        #expect(!model.appendStep([]))

        model.removeStep(at: 1)
        #expect(model.keySteps == [["Command", "ANSI_V"], ["Command", "ANSI_C"]])

        // 越界删除无害。
        model.removeStep(at: 9)
        #expect(model.keySteps.count == 2)

        model.clearKeys()
        #expect(model.keySteps.isEmpty)
        #expect(model.validationError != nil, "空序列不能提交")
        #expect(!model.canCommit)
    }

    @Test("「录制按键」只录一个组合键：整段替换，不会一段段累加")
    func setSingleStepReplacesTheWholeSequence() {
        // ⌘V 然后 ↩ 的多步序列。
        let model = CommandEditorModel(command: .keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_V", nil, "Return"])
        ))
        #expect(model.keySteps.count == 2)

        // 再录一次必须把整段换掉 —— 用户按的是「录制按键」，期待的是一个热键。
        #expect(model.setSingleStep(["Command", "ANSI_W"]))
        #expect(model.keySteps == [["Command", "ANSI_W"]])
        #expect(model.command == .keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_W"])
        ))

        // 连按也不会长出第 2 步。
        #expect(model.setSingleStep(["Command", "ANSI_T"]))
        #expect(model.keySteps == [["Command", "ANSI_T"]])

        // 空输入不接受，调用方可以继续录制。
        #expect(!model.setSingleStep([]))
        #expect(model.keySteps == [["Command", "ANSI_T"]])
    }

    @Test("「添加一步」才会累加，且首步为空时也能作为第 1 步")
    func appendStepAccumulates() {
        let model = CommandEditorModel(command: .shellScript(WGShellScriptCommand(script: "echo hi")))
        model.setKind(.keySequence)
        #expect(model.keySteps.isEmpty)

        // 空序列上 append 得到第 1 步（不会先插入一个前导分隔符）。
        #expect(model.appendStep(["Command", "ANSI_V"]))
        #expect(model.keySteps == [["Command", "ANSI_V"]])
        #expect(model.appendStep(["Return"]))
        #expect(model.keySteps == [["Command", "ANSI_V"], ["Return"]])
        #expect(model.command == .keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_V", nil, "Return"])
        ))
    }

    @Test("按键序列：单独一个修饰键也是合法的一步")
    func modifierOnlyStepIsAllowed() {        let model = CommandEditorModel(command: .keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: [])
        ))
        #expect(model.validationError != nil)
        #expect(model.appendStep(["Command"]))
        #expect(model.canCommit)
        #expect(model.command == .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command"])))
    }

    @Test("系统快捷键开关会写回命令")
    func togglesSystemHotKey() {
        let model = CommandEditorModel(command: .keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"])
        ))
        model.isSystemHotKey = true
        #expect(model.command == .keySequence(
            WGKeySequenceCommand(isSystemHotKey: true, keys: ["Command", "ANSI_C"])
        ))
    }

    @Test("Web 搜索：地址必须非空且含 {0} 占位符")
    func validatesWebSearch() {
        let model = CommandEditorModel(command: .webSearch(
            WGWebSearchCommand(searchEngine: "https://www.google.com/search?q={0}")
        ))
        #expect(model.kind == .webSearch)
        #expect(model.canCommit)
        #expect(model.command == .webSearch(
            WGWebSearchCommand(searchEngine: "https://www.google.com/search?q={0}")
        ))

        model.searchEngine = "   "
        #expect(model.validationError == "搜索地址不能为空。")

        model.searchEngine = "https://example.com/search"
        #expect(model.validationError?.contains("{0}") == true, "缺占位符要拦下来，避免搜索词无处可放")

        // 前后空白会被去掉。
        model.searchEngine = "  https://example.com/?q={0}  "
        #expect(model.canCommit)
        #expect(model.command == .webSearch(
            WGWebSearchCommand(searchEngine: "https://example.com/?q={0}")
        ))
    }

    @Test("Shell 脚本：空白脚本不接受，多行原样保留")
    func validatesShellScript() {
        let model = CommandEditorModel(command: .shellScript(
            WGShellScriptCommand(script: "echo hi")
        ))
        #expect(model.kind == .shellScript)
        #expect(model.canCommit)

        model.script = "\n   \n"
        #expect(model.validationError != nil)

        model.script = "line1\nline2\n"
        #expect(model.canCommit)
        #expect(model.command == .shellScript(WGShellScriptCommand(script: "line1\nline2\n")))
    }

    @Test("系统功能键：索引即命令，非法索引被拦下")
    func validatesSystemFunction() {
        let model = CommandEditorModel(command: .systemFunctionKey(
            WGSystemFunctionKeyCommand(selectedIndex: 5)
        ))
        #expect(model.kind == .systemFunctionKey)
        #expect(model.functionIndex == 5)
        #expect(model.canCommit)

        model.functionIndex = 99
        #expect(model.validationError != nil)

        model.functionIndex = 3
        #expect(model.command == .systemFunctionKey(WGSystemFunctionKeyCommand(selectedIndex: 3)))
    }

    @Test("未知命令类型不会被悄悄覆盖，必须先明确确认")
    func protectsUnknownCommands() {
        let model = CommandEditorModel(command: .unknown(type: "LuaCommand"))
        #expect(model.isReplacingUnknownCommand)
        #expect(model.canCommit == false)
        #expect(model.validationError?.contains("LuaCommand") == true)

        model.beginReplacingUnknownCommand()
        #expect(!model.isReplacingUnknownCommand)
        // 确认后就是普通的空按键序列，还得把序列填上才能提交。
        #expect(model.validationError != nil)
        model.appendStep(["Command", "ANSI_C"])
        #expect(model.canCommit)
    }

    @Test("切换命令类型会给出该类型的可用起点")
    func switchingKindSeedsUsableDefaults() {
        let model = CommandEditorModel(command: .keySequence(
            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"])
        ))
        model.setKind(.webSearch)
        #expect(model.kind == .webSearch)
        #expect(model.searchEngine.contains("{0}"), "切到搜索时要预填可用的地址模板")
        #expect(model.canCommit)

        model.setKind(.keySequence)
        #expect(model.keys.isEmpty, "切回按键序列不应残留上一个类型的数据")
        #expect(model.validationError != nil)
    }

    @Test("isDirty 反映与原始命令的差异")
    func tracksDirtyState() {
        let model = CommandEditorModel(command: .shellScript(WGShellScriptCommand(script: "echo hi")))
        #expect(!model.isDirty)
        model.script = "echo hi\necho bye"
        #expect(model.isDirty)
        model.script = "echo hi"
        #expect(!model.isDirty)
    }

    @Test("键码反查表能把真实按键码换回配置里的名字")
    func reversesKeyCodes() {
        // 用前向表的真值验证反查，而不是另抄一份映射。
        for (name, code) in WGKeyCode.keyCodes {
            #expect(WGKeyCode.name(forKeyCode: code) == name, "\(name) 反查失败")
        }
        #expect(WGKeyCode.name(forKeyCode: 0x09) == "ANSI_V")
        #expect(WGKeyCode.name(forKeyCode: 0x24) == "Return")
        #expect(WGKeyCode.isModifier("Command"))
        #expect(!WGKeyCode.isModifier("ANSI_V"))
    }
}
