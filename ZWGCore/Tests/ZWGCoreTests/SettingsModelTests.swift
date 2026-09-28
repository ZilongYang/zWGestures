import Foundation
import Testing

@testable import ZWGCore

/// A configuration shaped like the user's real one: a large `General` set plus a small app
/// override and an empty special target.
private func makeFixtureConfig() -> WGConfig {
    WGConfig(
        general: WGTarget(
            kind: .general,
            id: "general-id",
            name: "General",
            intents: [
                WGIntent(
                    name: "Copy",
                    gesture: [
                        .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                        // 两段折线：先向右再向下 —— 屏幕方向「右→下」。
                        .stroke(WGStrokeStep(isSimple: false, points: [0, 0, 500, 0, 500, -500])),
                    ],
                    command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
                ),
                WGIntent(
                    name: "Paste & Enter",
                    gesture: [
                        .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                        // 单一向下笔画（P 用 y 轴向上为正，屏幕上就是向下）。
                        .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, -500])),
                        .keyDown(WGKeyDownStep(key: "MOUSE:0")),
                    ],
                    command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_V"]))
                ),
                WGIntent(
                    name: "Volume Up",
                    gesture: [
                        .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                        .stroke(WGStrokeStep(isSimple: true, points: [-400, 300])),
                    ],
                    command: .systemFunctionKey(WGSystemFunctionKeyCommand(selectedIndex: 7))
                ),
                WGIntent(
                    name: "Reopen Tab",
                    gesture: [
                        .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                        .stroke(WGStrokeStep(isSimple: true, points: [500, 500])),
                    ],
                    command: .keySequence(
                        WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "Shift", "ANSI_T"])
                    )
                ),
            ]
        ),
        apps: [
            WGTarget(
                kind: .app,
                id: "finder-id",
                name: "Finder",
                bundleId: "com.apple.finder",
                path: "/System/Library/CoreServices/Finder.app",
                intents: [
                    WGIntent(
                        name: "New Finder Window",
                        gesture: [
                            .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                            .stroke(WGStrokeStep(isSimple: true, points: [500, 0])),
                        ],
                        command: .keySequence(
                            WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_N"])
                        )
                    )
                ]
            )
        ],
        specials: [
            WGTarget(kind: .desktop, id: "desktop-id", name: "Desktop")
        ]
    )
}

@MainActor
@Suite("设置：编辑模型")
struct SettingsModelTests {
    @Test("侧栏按 全局→分组→应用→特殊 的顺序列出所有目标")
    func listsEveryTarget() {
        let model = SettingsModel(config: makeFixtureConfig())
        #expect(model.targets.map(\.displayName) == ["全局", "Finder", "Desktop"])
        #expect(model.countsByTargetId == ["general-id": 4, "finder-id": 1, "desktop-id": 0])
        #expect(model.totalIntentCount == 5)
    }

    @Test("切换目标会换掉手势列表，并且只数当前目标")
    func selectionDrivesTheList() throws {
        let model = SettingsModel(config: makeFixtureConfig())
        #expect(model.selection == .general)
        #expect(model.rows.count == 4)
        #expect(model.selectedTargetName == "全局")

        model.selection = .app(id: "finder-id")
        // 应用目标默认继承全局：先列自己的，再列继承来的（只读）。
        #expect(model.rows.first?.name == "New Finder Window")
        #expect(model.rows.first?.isInherited == false)
        #expect(model.inheritedRowCount == 4)
        #expect(model.rows.count == 1 + 4)
        #expect(model.rows.dropFirst().allSatisfy { $0.isInherited })
        // id 必须全局唯一 —— 重复 id 会让 SwiftUI 的 ForEach 渲染错乱。
        #expect(Set(model.rows.map(\.id)).count == model.rows.count)
        #expect(model.selectedTargetName == "Finder")

        // 关掉继承后只剩自己的。
        #expect(model.setInheritsGlobal(false))
        #expect(model.rows.map(\.name) == ["New Finder Window"])
        #expect(model.inheritedRowCount == 0)
        #expect(model.setInheritsGlobal(true))

        model.selection = .special(id: "desktop-id")
        #expect(model.rows.isEmpty)
        #expect(model.selectedTargetName == "Desktop")
    }

    @Test("行里带方向、命令摘要与手势修饰键，并按原顺序排列")
    func rowsCarryDisplayFields() throws {
        let model = SettingsModel(config: makeFixtureConfig())
        let copy = try #require(model.rows.first)
        #expect(copy.name == "Copy")
        // P=[0,0, 500,0, 500,-500] 解码成屏幕坐标 (0,0)→(500,0)→(500,500)：先向右再向下。
        #expect(copy.direction == "右→下")
        #expect(copy.commandSummary == "⌘+C")
        #expect(copy.modifiers.isEmpty)
        #expect(copy.points.count == 3)
        #expect(!copy.isClosed)

        // 「Paste & Enter」是单一向下笔画，后面跟一个左键修饰步骤。
        let paste = model.rows[1]
        #expect(paste.direction == "下")
        #expect(paste.commandSummary == "⌘+V")
        #expect(paste.modifiers == ["鼠标左键"])

        // 功能键用自己的中文名。
        #expect(model.rows[2].commandSummary == "增加音量")
    }

    @Test("搜索同时匹配名称、方向与命令，且清空后恢复")
    func searchMatchesNameDirectionAndCommand() {
        let model = SettingsModel(config: makeFixtureConfig())

        model.setQuery("copy")
        #expect(model.rows.map(\.name) == ["Copy"])
        #expect(model.hiddenByFilterCount == 3)

        // 方向：Copy 是「右→下」，Paste 是「下」，两条都含「下」。
        model.setQuery("下")
        #expect(model.rows.map(\.name) == ["Copy", "Paste & Enter"])

        // 命令摘要：三条 ⌘ 组合键（Volume Up 是系统功能键，不带 ⌘）。
        model.setQuery("⌘")
        #expect(model.rows.count == 3)

        // 功能键的中文名。
        model.setQuery("音量")
        #expect(model.rows.map(\.name) == ["Volume Up"])

        // 手势修饰键也参与搜索。
        model.setQuery("鼠标左键")
        #expect(model.rows.map(\.name) == ["Paste & Enter"])

        // 清空后恢复。
        model.setQuery("   ")
        #expect(model.rows.count == 4)
        #expect(model.hiddenByFilterCount == 0)

        model.setQuery("没有这个东西")
        #expect(model.rows.isEmpty)
    }

    @Test("改名：去掉首尾空白、空名字被拒、会标记为有未保存改动")
    func renamesAnIntent() {
        let model = SettingsModel(config: makeFixtureConfig())
        #expect(!model.isDirty)

        #expect(model.renameIntent(at: 0, to: "  复制  "))
        #expect(model.rows[0].name == "复制")
        #expect(model.isDirty)
        #expect(model.editedConfig.general.intents[0].name == "复制")

        // 空名字/纯空白不接受，调用方可以据此保留输入框里的旧值。
        #expect(!model.renameIntent(at: 0, to: "   "))
        #expect(model.rows[0].name == "复制")
        // 越界索引也不接受。
        #expect(!model.renameIntent(at: 99, to: "X"))
    }

    @Test("删除手势后计数与列表同步，并只动当前目标")
    func deletesAnIntent() {
        let model = SettingsModel(config: makeFixtureConfig())
        #expect(model.deleteIntent(at: 1))
        #expect(model.rows.map(\.name) == ["Copy", "Volume Up", "Reopen Tab"])
        #expect(model.editedConfig.general.intents.count == 3)
        // Finder 不受影响。
        #expect(model.editedConfig.apps[0].intents.count == 1)

        #expect(model.deleteIntent(at: 5) == false)

        // 删空之后列表为空，但选中目标不变。
        #expect(model.deleteIntent(at: 0))
        #expect(model.deleteIntent(at: 0))
        #expect(model.deleteIntent(at: 0))
        #expect(model.rows.isEmpty)
        #expect(model.selection == .general)
    }

    @Test("revert 丢弃改动，markSaved 把当前状态定为基准")
    func tracksDirtyState() {
        let model = SettingsModel(config: makeFixtureConfig())
        #expect(!model.isDirty)

        model.renameIntent(at: 0, to: "改过的名字")
        #expect(model.isDirty)

        model.revert()
        #expect(!model.isDirty)
        #expect(model.rows[0].name == "Copy")

        model.renameIntent(at: 0, to: "存下来的名字")
        model.markSaved()
        #expect(!model.isDirty)
        #expect(model.rows[0].name == "存下来的名字")
    }

    @Test("改完的配置能按原格式写盘并读回")
    func editedConfigRoundTrips() throws {
        let model = SettingsModel(config: makeFixtureConfig())
        model.renameIntent(at: 0, to: "复制")
        model.deleteIntent(at: 3)

        let data = try WGConfigCodec.encode(model.editedConfig)
        let reloaded = try WGConfigCodec.decode(data).config
        #expect(reloaded == model.editedConfig)
        #expect(reloaded.general.intents.map(\.name) == ["复制", "Paste & Enter", "Volume Up"])
        #expect(reloaded.apps[0].bundleId == "com.apple.finder")
    }

    @Test("选中一个已不存在的目标时，编辑安全失败而不是崩溃")
    func editingAMissingTargetIsSafe() {
        let config = makeFixtureConfig()
        var withoutFinder = config
        withoutFinder.apps = []
        let model = SettingsModel(config: withoutFinder, selection: .app(id: "finder-id"))
        #expect(model.selectedTarget == nil)
        #expect(model.rows.isEmpty)

        // 编辑不存在的目标不生效，也不抛错。
        #expect(model.renameIntent(at: 0, to: "复制") == false)
        #expect(model.deleteIntent(at: 0) == false)
        #expect(model.editedConfig.general.intents[0].name == "Copy")
        #expect(!model.isDirty)
    }

    @Test("上移 / 下移会改变优先级顺序，越界时拒绝")
    func reordersGestures() {
        let model = SettingsModel(config: makeFixtureConfig())
        #expect(model.rows.map(\.name) == ["Copy", "Paste & Enter", "Volume Up", "Reopen Tab"])

        // 把第 3 条（Volume Up）上移一位。
        #expect(model.moveIntent(at: 2, by: -1))
        #expect(model.rows.map(\.name) == ["Copy", "Volume Up", "Paste & Enter", "Reopen Tab"])
        #expect(model.isDirty)

        // 第 0 条不能再上移，最后一条不能再下移。
        #expect(model.canMoveIntent(at: 0, by: -1) == false)
        #expect(model.moveIntent(at: 0, by: -1) == false)
        #expect(model.canMoveIntent(at: 3, by: 1) == false)
        #expect(model.moveIntent(at: 3, by: 1) == false)
        // 顺序没被越界操作改坏。
        #expect(model.rows.map(\.name) == ["Copy", "Volume Up", "Paste & Enter", "Reopen Tab"])

        // 下移回去。
        #expect(model.moveIntent(at: 1, by: 1))
        #expect(model.rows.map(\.name) == ["Copy", "Paste & Enter", "Volume Up", "Reopen Tab"])
    }

    @Test("排序只作用于当前手势集，并且能写盘读回")
    func reorderIsScopedAndPersists() throws {
        let model = SettingsModel(config: makeFixtureConfig())
        #expect(model.moveIntent(at: 0, by: 1))
        #expect(model.editedConfig.general.intents.map(\.name) == ["Paste & Enter", "Copy", "Volume Up", "Reopen Tab"])
        // Finder 不受影响。
        #expect(model.editedConfig.apps[0].intents.map(\.name) == ["New Finder Window"])

        let reloaded = try WGConfigCodec.decode(try WGConfigCodec.encode(model.editedConfig)).config
        #expect(reloaded.general.intents.map(\.name) == ["Paste & Enter", "Copy", "Volume Up", "Reopen Tab"])
    }

    @Test("选中目标不存在时排序安全失败")
    func refusesReorderWithoutTarget() {
        let model = SettingsModel(config: makeFixtureConfig(), selection: .app(id: "not-there"))
        #expect(model.canMoveIntent(at: 0, by: 1) == false)
        #expect(model.moveIntent(at: 0, by: 1) == false)
        #expect(!model.isDirty)
    }

    @Test("拖拽：按目标下标直接移动（前移 / 后移 / 拒绝原地不动）")
    func movesByDestinationIndex() {
        let model = SettingsModel(config: makeFixtureConfig())
        let original = ["Copy", "Paste & Enter", "Volume Up", "Reopen Tab"]
        #expect(model.rows.map(\.name) == original)

        // 把第 1 条拖到最后。
        #expect(model.moveIntent(from: 0, to: 3))
        #expect(model.rows.map(\.name) == ["Paste & Enter", "Volume Up", "Reopen Tab", "Copy"])

        // 把最后一条拖回最前。
        #expect(model.moveIntent(from: 3, to: 0))
        #expect(model.rows.map(\.name) == ["Copy", "Paste & Enter", "Volume Up", "Reopen Tab"])

        // 拖到自己身上是空操作，且不算改动。
        let clean = SettingsModel(config: makeFixtureConfig())
        #expect(clean.moveIntent(from: 2, to: 2) == false)
        #expect(!clean.isDirty)

        // 越界拒绝。
        #expect(model.moveIntent(from: 0, to: 9) == false)
        #expect(model.moveIntent(from: 9, to: 0) == false)
        #expect(model.rows.map(\.name) == original)
    }

    @Test("拖拽顺序能写盘读回，并且只动当前手势集")
    func draggedOrderPersists() throws {
        let model = SettingsModel(config: makeFixtureConfig())
        #expect(model.moveIntent(from: 3, to: 1))
        #expect(model.editedConfig.general.intents.map(\.name) == ["Copy", "Reopen Tab", "Paste & Enter", "Volume Up"])
        #expect(model.editedConfig.apps[0].intents.map(\.name) == ["New Finder Window"])

        let reloaded = try WGConfigCodec.decode(try WGConfigCodec.encode(model.editedConfig)).config
        #expect(reloaded.general.intents.map(\.name) == ["Copy", "Reopen Tab", "Paste & Enter", "Volume Up"])
    }

    @Test("移到最前 / 移到最后：一步到位（长列表里拖拽不好操作的替代）")
    func movesToTheExtremes() {
        let model = SettingsModel(config: makeFixtureConfig())
        let original = ["Copy", "Paste & Enter", "Volume Up", "Reopen Tab"]
        #expect(model.rows.map(\.name) == original)

        // 「移到最前」= 目标下标 0。
        #expect(model.moveIntent(from: 2, to: 0))
        #expect(model.rows.map(\.name) == ["Volume Up", "Copy", "Paste & Enter", "Reopen Tab"])

        // 「移到最后」= 目标下标 count-1。
        #expect(model.moveIntent(from: 0, to: 3))
        #expect(model.rows.map(\.name) == ["Copy", "Paste & Enter", "Reopen Tab", "Volume Up"])

        // 已经在最前 / 最后时不产生改动。
        let clean = SettingsModel(config: makeFixtureConfig())
        #expect(clean.moveIntent(from: 0, to: 0) == false)
        #expect(clean.moveIntent(from: 3, to: 3) == false)
        #expect(!clean.isDirty)
    }

    @Test("单个手势时移到最前/最后都是空操作")
    func extremesAreNoOpsForASingleGesture() {
        let config = WGConfig(general: WGTarget(
            kind: .general,
            id: "one",
            name: "General",
            intents: makeFixtureConfig().general.intents.prefix(1).map { $0 }
        ))
        let model = SettingsModel(config: config)
        #expect(model.rows.count == 1)
        #expect(model.moveIntent(from: 0, to: 0) == false)
        #expect(!model.isDirty)
    }

    @Test("禁用 / 启用某条手势：会标记改动，行状态跟着变")
    func togglesEnabledState() throws {
        let model = SettingsModel(config: makeFixtureConfig())
        #expect(model.rows.allSatisfy { $0.isEnabled })
        #expect(model.disabledCount == 0)

        #expect(model.setEnabled(at: 1, to: false))
        #expect(model.rows[1].isEnabled == false)
        #expect(model.rows[0].isEnabled)
        #expect(model.disabledCount == 1)
        #expect(model.isDirty)
        #expect(model.editedConfig.general.intents[1].enabled == false)

        #expect(model.isDirty)
        model.markSaved()
        #expect(!model.isDirty)
        #expect(model.setEnabled(at: 1, to: true))
        #expect(model.disabledCount == 0)
        #expect(model.editedConfig.general.intents[1].enabled == true)

        // 越界索引拒绝。
        #expect(model.setEnabled(at: 99, to: false) == false)
    }
}

@MainActor
@Suite("设置：应用目标管理")
struct SettingsModelAppTargetTests {
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
                        command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
                    )
                ]
            ),
            apps: [
                WGTarget(
                    kind: .app,
                    id: "finder-id",
                    name: "Finder",
                    bundleId: "com.apple.finder",
                    path: "/System/Library/CoreServices/Finder.app",
                    intents: []
                )
            ],
            specials: [WGTarget(kind: .desktop, id: "desktop-id", name: "Desktop")]
        ))
    }

    @Test("按 Bundle ID 新增应用目标，并返回新目标供界面选中")
    func addsAnAppTarget() throws {
        let model = makeModel()
        let result = model.addApplicationTarget(WGAppCandidate(
            name: "Safari",
            bundleId: "com.apple.Safari",
            path: "/Applications/Safari.app"
        ))
        let selection = try #require(try? result.get())
        #expect(model.targets.map(\.displayName) == ["全局", "Finder", "Safari", "Desktop"])
        #expect(model.isDirty)

        // 新目标自己没有手势，但默认继承全局，所以列表里是「继承来的那几条」。
        model.selection = selection
        #expect(model.rows.allSatisfy { $0.isInherited })
        #expect(model.rows.count == model.inheritedRowCount)
        #expect(model.setInheritsGlobal(false))
        #expect(model.rows.isEmpty)
        #expect(model.setInheritsGlobal(true))
        let added = try #require(model.editedConfig.apps.last)
        #expect(added.bundleId == "com.apple.Safari")
        #expect(added.path == "/Applications/Safari.app")
        #expect(added.name == "Safari")
        #expect(added.kind == .app)
        #expect(added.id.count == 22, "与原版一样生成短 GUID")

        // 能按原格式写盘读回。
        let reloaded = try WGConfigCodec.decode(try WGConfigCodec.encode(model.editedConfig)).config
        #expect(reloaded.apps.last?.bundleId == "com.apple.Safari")
    }

    @Test("同一个应用不能有两个目标 —— 否则第二个永远不会被用到")
    func refusesDuplicates() {
        let model = makeModel()
        // 同 bundleId。
        let duplicate = model.addApplicationTarget(WGAppCandidate(
            name: "Finder 再来一个",
            bundleId: "com.apple.finder",
            path: "/System/Library/CoreServices/Finder.app"
        ))
        #expect(duplicate == .failure(.duplicate(existingName: "Finder")))
        #expect(model.editedConfig.apps.count == 1)
        #expect(!model.isDirty)

        // 没有 bundleId 时按路径判重（与 TargetResolver 的规则一致）。
        let byPath = model.addApplicationTarget(WGAppCandidate(
            name: "Finder",
            path: "/System/Library/CoreServices/Finder.app"
        ))
        #expect(byPath == .failure(.duplicate(existingName: "Finder")))
    }

    @Test("没有 Bundle ID 的应用靠路径识别，也同样能新增")
    func addsByPathOnly() throws {
        let model = makeModel()
        let result = model.addApplicationTarget(WGAppCandidate(
            name: "某个无 ID 的应用",
            path: "/Applications/NoIdentifier.app"
        ))
        let selection = try #require(try? result.get())
        model.selection = selection
        let added = try #require(model.editedConfig.apps.last)
        #expect(added.bundleId == nil)
        #expect(added.path == "/Applications/NoIdentifier.app")
    }

    @Test("既没有 ID 也没有路径时拒绝，而不是建一个永远匹配不到的目标")
    func refusesTargetsThatCannotBeMatched() {
        let model = makeModel()
        #expect(model.addApplicationTarget(WGAppCandidate(name: "啥都没有")) == .failure(.noIdentity))
        #expect(model.addApplicationTarget(WGAppCandidate(name: "", bundleId: "  ")) == .failure(.noIdentity))
        #expect(!model.isDirty)
    }

    @Test("名称为空时从 Bundle ID 或文件名推导")
    func derivesAMissingName() throws {
        #expect(SettingsModel.targetName(for: WGAppCandidate(name: "", bundleId: "com.apple.Safari")) == "Safari")
        #expect(SettingsModel.targetName(for: WGAppCandidate(name: "  ", path: "/Applications/微信.app")) == "微信")
        #expect(SettingsModel.targetName(for: WGAppCandidate(name: " 早就有名字了 ")) == "早就有名字了")
    }

    @Test("删除应用目标会连同它的手势一起删掉，并且能选中回到全局")
    func removesAnAppTarget() throws {
        let model = makeModel()
        model.selection = .app(id: "finder-id")
        #expect(model.canRemoveTarget(.app(id: "finder-id")))
        #expect(model.removeTarget(.app(id: "finder-id")))
        #expect(model.editedConfig.apps.isEmpty)
        #expect(model.targets.map(\.displayName) == ["全局", "Desktop"])
        // 当前选中项被删掉后自动回到全局，而不是停在一个不存在的目标上。
        #expect(model.selection == .general)
        #expect(model.rows.count == 1)
    }

    @Test("全局目标不允许删除（它是一切的后备）")
    func refusesToRemoveTheGeneralSet() {
        let model = makeModel()
        #expect(model.canRemoveTarget(.general) == false)
        #expect(model.removeTarget(.general) == false)
        #expect(!model.isDirty)
    }

    @Test("删除桌面目标允许，但只删它自己")
    func removesTheDesktopTarget() {
        let model = makeModel()
        #expect(model.removeTarget(.special(id: "desktop-id")))
        #expect(model.editedConfig.specials.isEmpty)
        #expect(model.editedConfig.apps.count == 1, "不能误删应用目标")
        #expect(model.editedConfig.general.intents.count == 1)
    }

    @Test("对不存在的目标删除会被拒绝")
    func refusesUnknownTargets() {
        let model = makeModel()
        #expect(model.canRemoveTarget(.app(id: "not-there")) == false)
        #expect(model.removeTarget(.app(id: "not-there")) == false)
        #expect(!model.isDirty)
    }
}
