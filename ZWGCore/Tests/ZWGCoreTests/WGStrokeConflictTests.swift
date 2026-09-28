import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

/// 一条向上、一条向下、一条向右 —— 互不冲突。
private func threeDistinctGestures() -> [WGIntent] {
    [
        WGIntent(
            name: "Copy",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, 50])),
            ],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
        ),
        WGIntent(
            name: "Paste",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, -50])),
            ],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_V"]))
        ),
        WGIntent(
            name: "Forward",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 50, 0])),
            ],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_RightBracket"]))
        ),
    ]
}

@MainActor
@Suite("设置：形状冲突检测")
struct WGStrokeConflictTests {
    @Test("形状没人占用时返回 nil")
    func freeShapeHasNoTwin() {
        let stroke = WGStrokeStep(isSimple: true, points: [0, 0, -50, 0])
        let candidate = WGIntent(
            name: "Left",
            gesture: [.keyDown(WGKeyDownStep(key: "MOUSE:1")), .stroke(stroke)],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
        )
        #expect(WGStrokeConflict.nearestTwin(toCandidate: candidate, in: threeDistinctGestures()) == nil)
    }

    /// **最重要的一条不变量。** 用户原版配置里 `Copy` 与 `Cut` 都是「上」、`Paste` 与
    /// `Paste & Enter` 都是「下」，靠手势修饰键（鼠标左键）区分。这种重复是**合法的**，
    /// 绝不能被判成冲突，否则用户连「把 Copy 改回上」都做不到。
    ///
    /// 断言的是规则本身（任何被报出来的冲突，两条手势的触发与修饰键签名必须完全一致），
    /// 所以用户继续编辑配置也不会让这条测试失效。
    @Test("真实配置：报出来的冲突一律是「触发与修饰键都相同」的", .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil))
    func realConfigOnlyReportsSameSignatureCollisions() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
        let intents = try LegacyConfigImporter.load(from: directory).config.general.intents

        let collisions = WGStrokeConflict.collisions(in: intents)
        for (index, twinName) in collisions {
            let subject = intents[index]
            let twin = try #require(intents.first { $0.name == twinName })
            #expect(
                WGStrokeConflict.triggerSignature(subject.triggerSteps)
                    == WGStrokeConflict.triggerSignature(twin.triggerSteps),
                "\(subject.name) 与 \(twinName) 的触发方式不同，不该算冲突"
            )
            #expect(
                WGStrokeConflict.modifierSignature(subject.modifierSteps)
                    == WGStrokeConflict.modifierSignature(twin.modifierSteps),
                "\(subject.name) 与 \(twinName) 的修饰键要求不同，不该算冲突"
            )
        }

        // 同形状但修饰键不同的一对，不能互相标记。
        if let copyIndex = intents.firstIndex(where: { $0.name == "Copy" }),
           let cutIndex = intents.firstIndex(where: { $0.name == "Cut" }),
           intents[copyIndex].strokeStep?.points == intents[cutIndex].strokeStep?.points
        {
            #expect(collisions[copyIndex] != "Cut")
            #expect(collisions[cutIndex] != "Copy")
        }
    }

    /// 这一条把上面查到的**既存事实**固化下来：用户从原版导入的配置里本来就有同形且同样不带
    /// 修饰键的手势（`P` 逐字节相同），任何匹配算法都不可能区分它们，所以其中一条永远抢不到。
    /// 记录成测试是为了以后有人「顺手删掉一段看似多余的代码」时立刻被拦下。
    @Test("真实配置里确实存在导入时就有的同形重复", .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil))
    func realConfigHasPreExistingDuplicates() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
        let intents = try LegacyConfigImporter.load(from: directory).config.general.intents

        func intent(_ name: String) throws -> WGIntent {
            try #require(intents.first { $0.name == name })
        }
        // 逐字节相同的两对，且都不带修饰键 —— 恰好可以独立复算。
        for (first, second) in [("Close", "Sleep"), ("Terminal", "Activity Monitor")] {
            let lhs = try intent(first)
            let rhs = try intent(second)
            #expect(lhs.strokeStep?.points == rhs.strokeStep?.points, "\(first)/\(second) 应当同形")
            #expect(lhs.modifierSteps.isEmpty && rhs.modifierSteps.isEmpty)
        }

        let collisions = WGStrokeConflict.collisions(in: intents)
        #expect(!collisions.isEmpty, "这份配置里本来就有重复，检测应当能发现")
        for (first, second) in [("Close", "Sleep"), ("Terminal", "Activity Monitor")] {
            let lhsIndex = try #require(intents.firstIndex { $0.name == first })
            let rhsIndex = try #require(intents.firstIndex { $0.name == second })
            #expect(
                collisions[lhsIndex] == second || collisions[rhsIndex] == first,
                "\(first)/\(second) 至少有一边要被指出来"
            )
        }
    }

    /// 这就是用户实际遇到的问题：把「拷贝」重画成向右，而「Forward」本来就是向右、也都不带修饰键。
    @Test("重画成已被占用的形状时，必须指出占用者")
    func detectsTheRealCollision() throws {
        let gestures = threeDistinctGestures()
        let recordedRight = try WGStrokeRecorder.encode(
            screenPoints: [CGPoint(x: 100, y: 300), CGPoint(x: 320, y: 300)]
        )
        // 重画的形状与 Forward 同向，必须被发现。
        let recordedIntent = WGIntent(
            name: "重画的 Copy",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(recordedRight),
            ],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
        )
        let twin = try #require(WGStrokeConflict.nearestTwin(toCandidate: recordedIntent, in: gestures))
        #expect(twin.name == "Forward")
        #expect(twin.index == 2)
        #expect(twin.distance <= RecognitionSettings().matchThreshold)

        // 编辑第 0 条（Copy）时不能拿它自己和自己比 —— 它现在的形状是「上」，换成「右」就是冲突。
        let copy = gestures[0]
        let model = GestureEditorModel(mode: .existing(index: 0), intent: copy, siblings: gestures)
        #expect(model.shapeConflict == nil, "原始的上笔画不冲突")

        #expect(model.recordStroke(
            screenPoints: [CGPoint(x: 100, y: 300), CGPoint(x: 320, y: 300)]
        ) == nil)
        #expect(model.shapeConflict?.name == "Forward")
        // 冲突**不再阻止提交**：谁生效由列表顺序决定（靠前的优先），用户可以保留两条再调整顺序。
        #expect(model.canCommit)
        #expect(model.shapeConflictDescription?.contains("Forward") == true)
        #expect(model.shapeConflictDescription?.contains("靠前的一条优先") == true)

        // 换一个没人用的形状（左下）就不再冲突。
        #expect(model.recordStroke(
            screenPoints: [CGPoint(x: 300, y: 100), CGPoint(x: 120, y: 260)]
        ) == nil)
        #expect(model.shapeConflict == nil)
        model.commandEditor.appendStep(["Command", "ANSI_C"])
        #expect(model.canCommit)
    }

    @Test("编辑带修饰键的手势时，只与同修饰键的手势竞争")
    func modifierRequirementScopesTheComparison() throws {
        // Cut：向上 + 左键修饰。Forward：向右 + 无修饰。
        let cut = WGIntent(
            name: "Cut",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, 50])),
                .keyDown(WGKeyDownStep(key: "MOUSE:0")),
            ],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_X"]))
        )
        let plainUp = WGIntent(
            name: "PlainUp",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, 50])),
            ],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
        )
        let gestyres = [cut, plainUp]
        // 两条形状相同但修饰键不同 → 不冲突。
        #expect(WGStrokeConflict.collisions(in: gestyres).isEmpty)

        // 编辑 Cut 时把形状保持「上」，也不该与 PlainUp 冲突。
        let model = GestureEditorModel(mode: .existing(index: 0), intent: cut, siblings: gestyres)
        #expect(model.shapeConflict == nil)

        // 若把 Cut 的修饰键去掉（改成普通向上），就会与 PlainUp 冲突。
        let cutWithoutModifier = WGIntent(
            name: "Cut",
            gesture: cut.triggerSteps + [.stroke(try #require(cut.strokeStep))],
            command: cut.command
        )
        let model2 = GestureEditorModel(
            mode: .existing(index: 0),
            intent: cutWithoutModifier,
            siblings: [cutWithoutModifier, plainUp]
        )
        #expect(model2.shapeConflict?.name == "PlainUp")
    }

    @Test("编辑同一条手势时不会与自己冲突")
    func doesNotCompareWithItself() {
        let gestures = threeDistinctGestures()
        let model = GestureEditorModel(
            mode: .existing(index: 2),
            intent: gestures[2],
            siblings: gestures
        )
        #expect(model.effectiveStroke?.directionDescription == "右")
        #expect(model.shapeConflict == nil, "Forward 不该和自己冲突")
        model.commandEditor.appendStep(["Command", "ANSI_C"])
        #expect(model.canCommit)
    }

    @Test("新建手势也要避开已占用的形状")
    func newGestureChecksSiblings() {
        let gestures = threeDistinctGestures()
        let model = GestureEditorModel(newGestureNamed: "新右", siblings: gestures)
        #expect(model.recordStroke(
            screenPoints: [CGPoint(x: 100, y: 300), CGPoint(x: 320, y: 300)]
        ) == nil)
        #expect(model.shapeConflict?.name == "Forward")

        model.commandEditor.appendStep(["Command", "ANSI_T"])
        // 冲突只是警告，动作齐了就能添加 —— 生效顺序交给列表排序。
        #expect(model.canCommit)
        #expect(model.shapeConflict?.name == "Forward")

        #expect(model.recordStroke(screenPoints: [CGPoint(x: 100, y: 300), CGPoint(x: 100, y: 80)]) == nil)
        #expect(model.shapeConflict?.name == "Copy", "向上同样是 Copy 的形状")
    }

    @Test("列表能列出所有冲突，并指出各自被谁抢走")
    func listsEveryCollision() {
        let gestures = threeDistinctGestures()
        #expect(WGStrokeConflict.collisions(in: gestures).isEmpty)

        // 再加一条向右、并且同样不带修饰键的：Forward 与它互抢。
        var colliding = gestures
        colliding.append(WGIntent(
            name: "另一条向右",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 50, 0])),
            ],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_T"]))
        ))

        let collisions = WGStrokeConflict.collisions(in: colliding)
        #expect(collisions.count == 2)
        #expect(collisions[2] == "另一条向右")
        #expect(collisions[3] == "Forward")
        // 向上、向下两条不受影响。
        #expect(collisions[0] == nil)
        #expect(collisions[1] == nil)
    }

    @Test("滚动的幅度不同但方向相同，视为同一要求")
    func scrollModifiersCollapseToDirection() {
        func scrollGesture(_ name: String, _ token: String) -> WGIntent {
            WGIntent(
                name: name,
                gesture: [
                    .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                    .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 50, 0])),
                    .keyDown(WGKeyDownStep(key: token)),
                ],
                command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_T"]))
            )
        }
        // VSCROLL:11 与 VSCROLL:12 都被识别成「向上滚动」（ROADMAP §7 里量级分档未定），
        // 所以它们争同一份输入 → 冲突。
        let sameDirection = [scrollGesture("A", "VSCROLL:11"), scrollGesture("B", "VSCROLL:12")]
        #expect(WGStrokeConflict.collisions(in: sameDirection).count == 2)

        // 方向相反就是两份不同的输入 → 不冲突。
        let opposite = [scrollGesture("A", "VSCROLL:11"), scrollGesture("B", "VSCROLL:-11")]
        #expect(WGStrokeConflict.collisions(in: opposite).isEmpty)
    }
}

@MainActor
@Suite("设置：冲突会出现在列表行上")
struct SettingsModelCollisionTests {
    private func makeConfig() -> WGConfig {
        WGConfig(general: WGTarget(kind: .general, id: "g", name: "General", intents: threeDistinctGestures()))
    }

    @Test("正常的配置没有任何冲突标记")
    func cleanConfigHasNoWarnings() {
        let model = SettingsModel(config: makeConfig())
        #expect(model.shapeCollisions.isEmpty)
        #expect(model.rows.allSatisfy { $0.collidingGestureName == nil })
    }

    @Test("存进去的重复形状会在这两行上标出对方名字")
    func marksBothRowsOfACollision() {
        var config = makeConfig()
        // 用户实际做过的操作：把 Copy 的笔画改成向右。
        config.general.intents[0].gesture = [
            .keyDown(WGKeyDownStep(key: "MOUSE:1")),
            .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 50, 0])),
        ]
        let model = SettingsModel(config: config)
        #expect(model.shapeCollisions.count == 2)
        let rows = model.rows
        #expect(rows[0].name == "Copy")
        #expect(rows[0].collidingGestureName == "Forward")
        #expect(rows[2].name == "Forward")
        #expect(rows[2].collidingGestureName == "Copy")
        #expect(rows[1].collidingGestureName == nil)
    }

    @Test("搜索过滤不会漏掉冲突标记")
    func collisionsSurviveFiltering() {
        var config = makeConfig()
        config.general.intents[0].gesture = [
            .keyDown(WGKeyDownStep(key: "MOUSE:1")),
            .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 50, 0])),
        ]
        let model = SettingsModel(config: config)
        model.setQuery("Copy")
        #expect(model.rows.count == 1)
        #expect(model.rows[0].collidingGestureName == "Forward")
    }

    @Test("禁用的手势不再算冲突（它本来就不会生效）")
    func disabledGesturesAreNotConflicts() {
        // 两条同形、同修饰键；把其中一条禁用后，另一条不再被判成冲突。
        func up(_ name: String, enabled: Bool) -> WGIntent {
            WGIntent(
                name: name,
                gesture: [
                    .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                    .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, 50])),
                ],
                command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"])),
                enabled: enabled
            )
        }

        let bothLive = [up("A", enabled: true), up("B", enabled: true)]
        #expect(WGStrokeConflict.collisions(in: bothLive).count == 2)

        let oneDisabled = [up("A", enabled: false), up("B", enabled: true)]
        #expect(WGStrokeConflict.collisions(in: oneDisabled).isEmpty, "禁用的一条不能算冲突")

        // 编辑器里也不该再警告。
        let editor = GestureEditorModel(
            mode: .existing(index: 1),
            intent: oneDisabled[1],
            siblings: oneDisabled
        )
        #expect(editor.shapeConflict == nil)
    }
}
