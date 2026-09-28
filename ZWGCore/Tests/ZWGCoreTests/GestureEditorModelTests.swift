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

@MainActor
@Suite("设置：手势修饰键与复制手势")
struct GestureModifierTests {
    private func pasteEnter() -> WGIntent {
        // 真实形态：右键触发 → 向下笔画 → 左键修饰（这就是「粘贴并回车」能与「粘贴」共存的原因）
        WGIntent(
            name: "Paste & Enter",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, -50])),
                .keyDown(WGKeyDownStep(key: "MOUSE:0")),
            ],
            command: copyCommand
        )
    }

    @Test("读出现有的手势修饰键")
    func readsExistingModifiers() {
        let model = GestureEditorModel(mode: .existing(index: 0), intent: pasteEnter())
        #expect(model.modifiers == [.mouseButton(.left)])
        #expect(!model.canAddModifier(.mouseButton(.left)), "已经有了就不能重复加")
        #expect(model.canAddModifier(.mouseButton(.right)))
        #expect(model.canAddModifier(.scrollUp))
    }

    @Test("新增修饰键：追加在笔画之后，且不可重复")
    func addsModifiers() {
        let model = GestureEditorModel(mode: .existing(index: 0), intent: pasteEnter())
        #expect(model.addModifier(.scrollUp))
        #expect(model.modifiers == [.mouseButton(.left), .scrollUp])
        #expect(model.addModifier(.scrollUp) == false, "同一修饰键不能加两次")

        // 步骤顺序必须是 [触发, 笔画, 修饰键…]，否则识别器的 triggerSteps/modifierSteps 会读错。
        let steps = model.intent.gesture
        #expect(steps.count == 4)
        #expect(steps[0].keyDown?.key == "MOUSE:1")
        #expect(steps[1].isStroke)
        #expect(steps[2].keyDown?.key == "MOUSE:0")
        #expect(steps[3].keyDown?.key == "VSCROLL:1")

        // 删掉一个。
        model.removeModifier(.mouseButton(.left))
        #expect(model.modifiers == [.scrollUp])
        #expect(model.intent.gesture.count == 3)
    }

    @Test("修饰键的量级用 1（与真实配置一致）")
    func usesTheSameScrollMagnitudeAsTheRealConfig() {
        #expect(WGModifierKind.scrollUp.key == "VSCROLL:1")
        #expect(WGModifierKind.scrollDown.key == "VSCROLL:-1")
        #expect(WGModifierKind.mouseButton(.left).key == "MOUSE:0")
        #expect(WGModifierKind.mouseButton(.center).key == "MOUSE:2")
        #expect(WGModifierKind.scrollUp.localizedName == "向上滚动")
        #expect(WGModifierKind.mouseButton(.left).localizedName == "鼠标左键")
    }

    @Test("横向滚动不提供：识别器会把 HSCROLL 拿竖向位移来比对")
    func doesNotOfferHorizontalScroll() {
        // 已知问题（ROADMAP §7）：areModifiersSatisfied 对 HSCROLL 也只看 deltaY，
        // 于是横向修饰键会被竖向滚动错误满足。界面里不提供，解析也要拒绝。
        #expect(WGModifierKind(key: "HSCROLL:1") == nil)
        #expect(WGModifierKind(key: "HSCROLL:-1") == nil)
        #expect(WGModifierKind.allCases.count == MouseButton.allCases.count + 2)
        #expect(!WGModifierKind.allCases.map(\.key).contains { $0.hasPrefix("HSCROLL") })
    }

    @Test("本版本不认识的修饰键步骤不会被静默删掉")
    func preservesStepsItCannotEdit() {
        // 一个 HSCROLL 修饰键（原版可能就是这种）+ 一个我们认识的。
        let intent = WGIntent(
            name: "旧的",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 50, 0])),
                .keyDown(WGKeyDownStep(key: "HSCROLL:1")),
                .keyDown(WGKeyDownStep(key: "MOUSE:2")),
            ],
            command: copyCommand
        )
        let model = GestureEditorModel(mode: .existing(index: 0), intent: intent)
        // 只列出能编辑的那一个……
        #expect(model.modifiers == [.mouseButton(.center)])
        // ……但保存时必须原样带回 HSCROLL 那一步。
        let steps = model.intent.gesture
        #expect(steps.count == 4)
        #expect(steps[2].keyDown?.key == "HSCROLL:1")
        #expect(steps[3].keyDown?.key == "MOUSE:2")
    }
}

@MainActor
@Suite("设置：复制手势")
struct DuplicateIntentTests {
    private func makeModel() -> SettingsModel {
        SettingsModel(config: WGConfig(general: WGTarget(
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
                ),
                WGIntent(
                    name: "Paste",
                    gesture: [
                        .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                        .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, -50])),
                    ],
                    command: copyCommand
                ),
            ]
        )))
    }

    @Test("复制出来的手势紧跟在原手势后面，名字不重复")
    func duplicatesRightAfterTheOriginal() throws {
        let model = makeModel()
        #expect(model.duplicateIntent(at: 0) == 1)
        #expect(model.rows.map(\.name) == ["Copy", "Copy 副本", "Paste"])
        #expect(model.isDirty)

        // 内容一致（形状、动作、修饰键），只是名字不同。
        let original = try #require(model.intent(at: 0))
        let copy = try #require(model.intent(at: 1))
        #expect(copy.gesture == original.gesture)
        #expect(copy.command == original.command)
        #expect(copy.name != original.name)

        // 再复制一次要产生不同的名字。
        #expect(model.duplicateIntent(at: 0) == 1)
        #expect(model.rows.map(\.name) == ["Copy", "Copy 副本 2", "Copy 副本", "Paste"])
    }

    @Test("越界或选中目标无效时拒绝")
    func refusesInvalidIndexes() {
        let model = makeModel()
        #expect(model.duplicateIntent(at: 9) == nil)
        let stale = SettingsModel(
            config: WGConfig(general: WGTarget(kind: .general, id: "g", name: "General")),
            selection: .app(id: "not-there")
        )
        #expect(stale.duplicateIntent(at: 0) == nil)
        #expect(!stale.isDirty)
    }

    @Test("复制只作用于当前手势集")
    func duplicatesOnlyInTheSelectedTarget() throws {
        var config = makeModel().editedConfig
        config.apps = [WGTarget(
            kind: .app,
            id: "brave",
            name: "Brave",
            bundleId: "com.brave.Browser",
            intents: [
                WGIntent(
                    name: "保存",
                    gesture: [
                        .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                        .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 50, 0])),
                    ],
                    command: copyCommand
                )
            ]
        )]
        let model = SettingsModel(config: config, selection: .app(id: "brave"))
        #expect(model.duplicateIntent(at: 0) == 1)
        #expect(model.editedConfig.apps[0].intents.map(\.name) == ["保存", "保存 副本"])
        #expect(model.editedConfig.general.intents.map(\.name) == ["Copy", "Paste"], "全局不该被动到")
    }
}
