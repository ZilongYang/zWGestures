import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

private func drawn(
    from start: CGPoint = CGPoint(x: 100, y: 300),
    _ steps: [CGPoint]
) -> [CGPoint] {
    var points = [start]
    var cursor = start
    for step in steps {
        cursor.x += step.x
        cursor.y += step.y
        points.append(cursor)
    }
    return points
}

/// ⌘C 的动作，用于给编辑中的手势配一个合法命令。
private let copyCommand = WGCommand.keySequence(
    WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"])
)

@MainActor
@Suite("设置：整条手势的编辑")
struct GestureEditorModelTests {
    @Test("改笔画：只换笔画，触发键与手势修饰键原样保留")
    func reRecordingKeepsTriggerAndModifiers() {
        // 真实形态：[右键触发, 笔画, 左键修饰]
        let original = WGIntent(
            name: "Paste & Enter",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 50, 0, 0])),
                .keyDown(WGKeyDownStep(key: "MOUSE:0")),
            ],
            command: copyCommand
        )
        let model = GestureEditorModel(mode: .existing(index: 3), intent: original)
        #expect(model.strokeDescription == "下")

        // 用户重画成向右。
        #expect(model.recordStroke(screenPoints: drawn(from: CGPoint(x: 100, y: 100), [CGPoint(x: 200, y: 0)])) == nil)
        #expect(model.strokeDescription == "右")
        #expect(model.canCommit)

        let steps = model.intent.gesture
        #expect(steps.count == 3)
        #expect(steps[0].keyDown?.key == "MOUSE:1", "触发键必须还在最前面")
        #expect(steps[1].isStroke)
        #expect(steps[1].strokeStep?.directionDescription == "右")
        #expect(steps[2].keyDown?.key == "MOUSE:0", "手势修饰键必须还在笔画之后")
        #expect(model.intent.name == "Paste & Enter")
        #expect(model.intent.command == copyCommand)
    }

    @Test("新笔画太短会被拒绝，并保留原来的形状")
    func rejectsTooShortRecordings() {
        let original = WGIntent(
            name: "Copy",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, 50])),
            ],
            command: copyCommand
        )
        let model = GestureEditorModel(mode: .existing(index: 0), intent: original)
        let message = model.recordStroke(screenPoints: drawn(from: CGPoint(x: 10, y: 10), [CGPoint(x: 0, y: -5)]))
        #expect(message != nil)
        #expect(model.strokeDescription == "上", "被拒绝的绘制不能改动已有形状")
    }

    @Test("新建手势：默认右键触发、没有修饰键、必须有笔画和动作才能提交")
    func newGestureDefaults() {
        let model = GestureEditorModel(newGestureNamed: "我的新手势")
        #expect(model.mode == .new)
        #expect(model.effectiveStroke == nil)
        #expect(model.strokeDescription == "（还没画）")

        // 没有笔画 → 不能提交。
        #expect(model.validationError?.contains("画") == true)
        #expect(!model.canCommit)
        #expect(model.gestureSteps.count == 1, "还没画时只保留触发键")

        // 画一个形状。
        #expect(model.recordStroke(screenPoints: drawn(from: CGPoint(x: 50, y: 50), [CGPoint(x: 0, y: 200)])) == nil)
        #expect(model.strokeDescription == "下")
        // 动作还是空的（新建手势给的是空按键序列），仍然不能提交。
        #expect(model.validationError != nil)
        #expect(!model.canCommit)

        // 录一个动作。
        model.commandEditor.appendStep(["Command", "ANSI_C"])
        #expect(model.canCommit)

        let steps = model.intent.gesture
        #expect(steps.count == 2)
        #expect(steps[0].keyDown?.key == "MOUSE:1", "新手势默认用右键触发")
        #expect(steps[1].strokeStep?.directionDescription == "下")
        #expect(model.intent.name == "我的新手势")
    }

    @Test("名字为空不能提交，且会去掉首尾空白")
    func validatesName() {
        let model = GestureEditorModel(newGestureNamed: "  ")
        model.recordStroke(screenPoints: drawn([CGPoint(x: 200, y: 0)]))
        model.commandEditor.appendStep(["Command", "ANSI_V"])
        #expect(model.validationError == "名字不能为空。")

        model.name = "  重命名后的  "
        #expect(model.canCommit)
        #expect(model.intent.name == "重命名后的")
    }

    @Test("实时方向提示与实际录入一致，清空后回到未画状态")
    func livePreviewAndClear() {
        let model = GestureEditorModel(newGestureNamed: "测试")
        let path = drawn(from: CGPoint(x: 300, y: 300), [CGPoint(x: 0, y: 200), CGPoint(x: 200, y: 0)])
        #expect(model.liveDescription(screenPoints: path) == "下→右")
        model.recordStroke(screenPoints: path)
        #expect(model.strokeDescription == "下→右")

        model.discardPendingStroke()
        #expect(model.effectiveStroke == nil)
        #expect(model.liveDescription(screenPoints: []) == "（还没画）")
    }
}

@MainActor
@Suite("设置：把编辑后的手势写回配置")
struct SettingsModelGestureWriteTests {
    private func makeModel() -> SettingsModel {
        SettingsModel(config: WGConfig(
            general: WGTarget(
                kind: .general,
                id: "general-id",
                name: "General",
                intents: [
                    WGIntent(
                        name: "Copy",
                        gesture: [
                            .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                            .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, 50])),
                        ],
                        command: copyCommand
                    )
                ]
            ),
            apps: [WGTarget(kind: .app, id: "finder-id", name: "Finder", intents: [])]
        ))
    }

    @Test("index 为 nil 时新增一条手势")
    func appendsANewGesture() throws {
        let model = makeModel()
        let editor = GestureEditorModel(newGestureNamed: "向下再向右")
        editor.recordStroke(screenPoints: drawn(from: CGPoint(x: 100, y: 100), [CGPoint(x: 0, y: 200), CGPoint(x: 200, y: 0)]))
        editor.commandEditor.appendStep(["Command", "Shift", "ANSI_T"])

        #expect(model.apply(intent: editor.intent, at: nil))
        #expect(model.editedConfig.general.intents.map(\.name) == ["Copy", "向下再向右"])
        #expect(model.isDirty)

        // 新条目能按原格式往返，形状与动作都在。
        let reloaded = try WGConfigCodec.decode(try WGConfigCodec.encode(model.editedConfig)).config
        let added = try #require(reloaded.general.intents.last)
        #expect(added.strokeStep?.directionDescription == "下→右")
        #expect(added.command.summary == "⌘+⇧+T")
        #expect(added.triggerSteps.first?.keyDown?.key == "MOUSE:1")
    }

    @Test("给定 index 时原地替换，不会新增")
    func replacesInPlace() {
        let model = makeModel()
        let existing = model.intent(at: 0)
        #expect(existing?.name == "Copy")

        let editor = GestureEditorModel(mode: .existing(index: 0), intent: existing!)
        editor.name = "复制"
        editor.recordStroke(screenPoints: drawn(from: CGPoint(x: 400, y: 400), [CGPoint(x: 300, y: 0)]))
        #expect(model.apply(intent: editor.intent, at: 0))

        #expect(model.editedConfig.general.intents.count == 1)
        #expect(model.editedConfig.general.intents[0].name == "复制")
        #expect(model.editedConfig.general.intents[0].strokeStep?.directionDescription == "右")
        // Finder 不受影响。
        #expect(model.editedConfig.apps[0].intents.isEmpty)
    }

    @Test("新增手势只进当前选中的手势集")
    func addsOnlyToTheSelectedTarget() {
        let model = makeModel()
        model.selection = .app(id: "finder-id")
        let editor = GestureEditorModel(newGestureNamed: "Finder 专用")
        editor.recordStroke(screenPoints: drawn([CGPoint(x: 200, y: 0)]))
        editor.commandEditor.appendStep(["Command", "ANSI_N"])

        #expect(model.apply(intent: editor.intent, at: nil))
        #expect(model.editedConfig.apps[0].intents.map(\.name) == ["Finder 专用"])
        #expect(model.editedConfig.general.intents.count == 1, "全局手势集不能被动到")
    }

    @Test("选中的手势集不存在时，新增会被拒绝而不是写错地方")
    func refusesWhenSelectionIsStale() {
        let model = makeModel()
        model.selection = .app(id: "not-there")
        let editor = GestureEditorModel(newGestureNamed: "不该出现")
        editor.recordStroke(screenPoints: drawn([CGPoint(x: 200, y: 0)]))
        editor.commandEditor.appendStep(["Command", "ANSI_C"])

        #expect(model.apply(intent: editor.intent, at: nil) == false)
        #expect(!model.isDirty)
        #expect(model.editedConfig.general.intents.count == 1)
    }
}
