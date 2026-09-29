import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

private let fixture = """
{
  "General": {
    "Id": "4O9RKu8cgkWeA3_G2-tIsg",
    "Name": "General",
    "Intents": [
      {
        "Name": "Copy",
        "ExecuteOnRecognize": false,
        "Gesture": [
          { "$type": "KeyDownStep", "Key": "MOUSE:1" },
          { "$type": "StrokeStep", "IsSimple": true, "P": [0, -50, 0, 0] }
        ],
        "Command": { "$type": "KeySeqCommand", "IsSystemHotKey": false, "Keys": ["Command", "ANSI_C"] }
      },
      {
        "Name": "Paste & Enter",
        "ExecuteOnRecognize": true,
        "Gesture": [
          { "$type": "KeyDownStep", "Key": "MOUSE:1" },
          { "$type": "StrokeStep", "IsSimple": true, "P": [0, 50, 0, 0] },
          { "$type": "KeyDownStep", "Key": "MOUSE:0" }
        ],
        "Command": { "$type": "KeySeqCommand", "IsSystemHotKey": false, "Keys": ["Command", "ANSI_V", null, "Return"] }
      },
      {
        "Name": "Volume +",
        "ExecuteOnRecognize": false,
        "Gesture": [
          { "$type": "MoveToEdgeCornerStep", "EdgeCorner": { "Value": 1 } },
          { "$type": "KeyDownStep", "Key": "VSCROLL:-1" }
        ],
        "Command": { "$type": "SystemFunctionKeyCommand", "SelectedIndex": 7 }
      },
      {
        "Name": "Summon",
        "ExecuteOnRecognize": false,
        "Gesture": [
          { "$type": "MoveToEdgeCornerStep", "EdgeCorner": { "Value": 4 } },
          { "$type": "ScrollStep", "IsHorizontal": false }
        ],
        "Command": { "$type": "ShellScriptCommand", "Script": "open \\"/Applications/Terminal.app\\"" }
      }
    ],
    "Triggers": [
      { "Def": [ { "$type": "KeyDownStep", "Key": "MOUSE:1" } ], "Enabled": true },
      { "Def": [ { "$type": "KeyDownStep", "Key": "MOUSE:0" } ], "Enabled": false },
      { "Def": [
          { "$type": "MoveToEdgeCornerStep", "EdgeCorner": { "Value": 9 } },
          { "$type": "KeyDownStep", "Key": "MOUSE:2" }
        ], "Enabled": true }
    ]
  },
  "Groups": [],
  "Apps": [
    {
      "$type": "MacAppTarget",
      "BundleId": null,
      "Path": "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
      "Id": "IYY0_CDFdUqbqST2s-Hrng",
      "Name": "Finder",
      "Intents": [
        {
          "Name": "Web Search",
          "ExecuteOnRecognize": false,
          "Gesture": [
            { "$type": "KeyDownStep", "Key": "MOUSE:1" },
            { "$type": "StrokeStep", "IsSimple": false, "P": [969, 546, 1069, 395, 1203, 575] }
          ],
          "Command": { "$type": "WebSearchCommand", "SearchEngine": "https://www.google.com/search?q={0}" }
        }
      ],
      "Triggers": []
    }
  ],
  "Specials": [
    { "$type": "MacDesktopTarget", "Id": "2Lw_wzJNfEmPH3L1hcoZgw", "Name": "Desktop", "Intents": [], "Triggers": [] }
  ]
}
"""

// swiftlint:disable:next force_try
private func decodeFixture() throws -> WGConfig {
    try WGConfigCodec.decode(Data(fixture.utf8)).config
}

@Suite("配置：编解码与格式兼容")
struct WGConfigCodecTests {
    @Test("解析出全部目标与手势")
    func decodesTargetsAndIntents() throws {
        let config = try decodeFixture()
        #expect(config.general.kind == .general)
        #expect(config.general.intents.count == 4)
        #expect(config.apps.count == 1)
        #expect(config.apps[0].kind == .app)
        #expect(config.apps[0].name == "Finder")
        #expect(config.apps[0].bundleId == nil)
        #expect(config.apps[0].intents.count == 1)
        #expect(config.specials.count == 1)
        #expect(config.specials[0].kind == .desktop)
        #expect(config.allTargets.count == 3)
    }

    @Test("编解码往返不丢失任何字段")
    func roundTripsLosslessly() throws {
        let original = try decodeFixture()
        let data = try WGConfigCodec.encode(original)
        let reloaded = try WGConfigCodec.decode(data).config
        #expect(reloaded == original)

        // 再走一遍，确保编码结果是稳定不动点
        let again = try WGConfigCodec.encode(reloaded)
        #expect(again == data)
    }

    @Test("General 不写 $type，应用目标写 MacAppTarget 与 Path")
    func encodesTypeDiscriminator() throws {
        let data = try WGConfigCodec.encode(try decodeFixture())
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"General\" : {\n    \"$type\""))
        #expect(json.contains("MacAppTarget"))
        #expect(json.contains("MacDesktopTarget"))
    }

    @Test("未知的对象类型会被报告出来，而不是静默丢弃")
    func reportsUnknownTypes() throws {
        let json = """
        { "General": { "Id": "a", "Name": "General", "Intents": [ {
            "Name": "X", "ExecuteOnRecognize": false,
            "Gesture": [ { "$type": "TeleportStep", "Where": "mars" } ],
            "Command": { "$type": "LuaCommand", "Script": "return 1" } } ], "Triggers": [] },
          "Groups": [], "Apps": [], "Specials": [] }
        """
        let result = try WGConfigCodec.decode(Data(json.utf8))
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].contains("LuaCommand"))
        #expect(result.warnings[0].contains("TeleportStep"))
    }

    @Test("带 UTF-8 BOM 的配置也能解析")
    func toleratesByteOrderMark() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(fixture.utf8))
        #expect(try WGConfigCodec.decode(data).config.general.intents.count == 4)
    }
}

@Suite("配置：轨迹编码")
struct WGStrokeEncodingTests {
    @Test("P 就是绘制顺序：第一对点才是笔画起点")
    func firstPointIsTheStart() throws {
        let config = try decodeFixture()
        let copy = try #require(config.general.intents[0].strokeStep)
        #expect(copy.points == [0, -50, 0, 0])
        #expect(copy.isSimple)
        // 存储用的 y 轴向上为正，转成屏幕坐标要取反：起点 (0,-50) 变成屏幕上的下方
        #expect(copy.drawingOrderPoints == [CGPoint(x: 0, y: 50), CGPoint(x: 0, y: 0)])
        #expect(copy.directionDescription == "上")
        // 快捷入门图里「拷贝」的圆圈（起笔点）画在箭头下方
        #expect(copy.drawingOrderPoints.first!.y > copy.drawingOrderPoints.last!.y)
    }

    @Test("闭合轨迹的首尾点相同")
    func detectsClosedStrokes() {
        let stroke = WGStrokeStep(isSimple: true, points: [0, 0, 0, 50, 0, 0])
        let points = stroke.drawingOrderPoints
        #expect(points.count == 3)
        #expect(points.first == points.last)
    }

    @Test("任意形状手势的 y 同样是向上为正，与简单手势一致")
    func arbitraryShapeUsesTheSameAxisAsSimpleStrokes() throws {
        let config = try decodeFixture()
        let stroke = try #require(config.apps[0].intents[0].strokeStep)
        #expect(!stroke.isSimple)
        #expect(stroke.points == [969, 546, 1069, 395, 1203, 575])
        #expect(stroke.drawingOrderPoints.first == CGPoint(x: 969, y: -546))
        // 屏幕坐标下是「先向右下、再向右上」
        #expect(stroke.directionDescription == "下右→上右")
    }

    @Test("能区分出触发前缀、轨迹与后缀修饰步骤")
    func splitsGestureIntoSections() throws {
        let config = try decodeFixture()
        let paste = config.general.intents[1]
        #expect(paste.executeOnRecognize)
        #expect(paste.triggerSteps.count == 1)
        #expect(paste.triggerSteps[0].keyDown?.key == "MOUSE:1")
        #expect(paste.strokeStep != nil)
        #expect(paste.modifierSteps.count == 1)
        #expect(paste.modifierSteps[0].keyDown?.key == "MOUSE:0")
    }
}

@Suite("配置：命令编码")
struct WGCommandEncodingTests {
    @Test("null 分隔的按键序列被拆成多步")
    func splitsKeySequenceIntoSteps() throws {
        let config = try decodeFixture()
        guard case .keySequence(let command) = config.general.intents[1].command else {
            Issue.record("应为 KeySeqCommand")
            return
        }
        #expect(command.keys == ["Command", "ANSI_V", nil, "Return"])
        #expect(command.steps == [["Command", "ANSI_V"], ["Return"]])
        #expect(!command.isSystemHotKey)
    }

    @Test("系统功能键索引映射到正确的功能")
    func mapsSystemFunctionIndex() throws {
        let config = try decodeFixture()
        guard case .systemFunctionKey(let command) = config.general.intents[2].command else {
            Issue.record("应为 SystemFunctionKeyCommand")
            return
        }
        #expect(command.selectedIndex == 7)
        #expect(command.function == .volumeUp)
        #expect(WGSystemFunction(rawValue: 0) == .brightnessDown)
        #expect(WGSystemFunction.allCases.count == 8)
    }

    @Test("Shell 脚本与 Web 搜索原样保留")
    func keepsScriptAndSearchEngine() throws {
        let config = try decodeFixture()
        guard case .shellScript(let shell) = config.general.intents[3].command else {
            Issue.record("应为 ShellScriptCommand")
            return
        }
        #expect(shell.script.contains("Terminal.app"))

        guard case .webSearch(let search) = config.apps[0].intents[0].command else {
            Issue.record("应为 WebSearchCommand")
            return
        }
        #expect(search.searchEngine == "https://www.google.com/search?q={0}")
    }
}

@Suite("配置：边角位掩码")
struct WGEdgeCornerTests {
    @Test("单值代表一条边，两个相邻位的组合代表一个角")
    func classifiesEdgesAndCorners() {
        let edges: [WGEdgeCornerMask] = [.top, .right, .bottom, .left]
        #expect(edges.allSatisfy { $0.isEdge && !$0.isCorner && $0.isValid })

        // 现有配置里出现的四个角值
        for value in [3, 6, 9, 12] {
            let mask = WGEdgeCornerMask(rawValue: value)
            #expect(mask.isCorner, "值 \(value) 应该是角")
            #expect(mask.isValid)
            #expect(!mask.isEdge)
        }
    }

    @Test("每个角都由两条相邻的边组成")
    func cornersAreAdjacentEdgePairs() {
        #expect(WGEdgeCornerMask(rawValue: 3) == [.top, .right])
        #expect(WGEdgeCornerMask(rawValue: 6) == [.right, .bottom])
        #expect(WGEdgeCornerMask(rawValue: 12) == [.bottom, .left])
        #expect(WGEdgeCornerMask(rawValue: 9) == [.top, .left])
    }

    @Test("无效组合被识别为非法")
    func rejectsNonsenseCombinations() {
        #expect(!WGEdgeCornerMask(rawValue: 0).isValid)
        #expect(!WGEdgeCornerMask(rawValue: 5).isValid) // 上 + 下，两条对边
        #expect(!WGEdgeCornerMask(rawValue: 16).isValid)
    }

    @Test("边角位掩码与原版快捷入门图逐一对照")
    func edgeMaskMatchesTheOriginalArtwork() {
        // 音量（EDGE1）的卡片在监视器图标顶部画黑条 -> 上边缘
        #expect(WGEdgeCornerMask(rawValue: 1) == .top)
        // 亮度（EDGE4）的卡片在监视器图标底部画黑条 -> 下边缘
        #expect(WGEdgeCornerMask(rawValue: 4) == .bottom)
        // 切换任务（EDGE9）的卡片角括号在屏幕左上角 -> 9 = 1|8 = 上|左，故 8 = 左
        #expect(WGEdgeCornerMask(rawValue: 9) == [.top, .left])
        #expect(WGEdgeCornerMask(rawValue: 8) == .left)
        // 终端（EDGE8）与活动监视器（EDGE2）是互为镜像的一对
        #expect(WGEdgeCornerMask(rawValue: 2) == .right)
    }

    @Test("边角也有自己的中文名")
    func hasLocalizedNames() {
        #expect(WGEdgeCornerMask(rawValue: 3).localizedName == "屏幕右上角")
        #expect(WGEdgeCornerMask(rawValue: 9).localizedName == "屏幕左上角")
        #expect(WGEdgeCornerMask(rawValue: 1).localizedName == "屏幕上边缘")
    }
}

@Suite("配置：偏好")
struct WGPreferencesTests {
    @Test("偏好解析并能换算成秒")
    func decodesPreferences() throws {
        let json = """
        { "AutoStart": true, "StartDragTimeout": 250, "ShowStartDragTimeoutIndicator": true,
          "ShowPath": true, "ShowGestureName": true, "ShowStatusIcon": true,
          "PathColorNormal": "#7F7F7FC4", "PathColorRecognized": "#20D697E6",
          "LabelColorNormal": "#60606080", "LabelExecuted": "#20D697E6",
          "TargetMode": "Focused", "PathLineWidth": 2.25, "GesturePos": 0.25, "SkipVersion": null }
        """
        let preferences = try WGConfigCodec.decodePreferences(Data(json.utf8))
        #expect(preferences.startDragTimeout == 250)
        #expect(abs(preferences.startDragTimeoutSeconds - 0.25) < 0.0001)
        #expect(preferences.targetMode == .focused)
        #expect(preferences.skipVersion == nil)
    }

    @Test("缺失字段回落到默认值")
    func fallsBackToDefaults() throws {
        let preferences = try WGConfigCodec.decodePreferences(Data("{}".utf8))
        #expect(preferences == WGPreferences())
        #expect(preferences.startDragTimeout == 250)
        #expect(preferences.targetMode == .focused)
    }

    @Test("编码时保留 EveryKey，包括值为 null 的 SkipVersion")
    func encodesEveryKeyIncludingNulls() throws {
        let data = try WGConfigCodec.encodePreferences(WGPreferences())
        let dictionary = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(dictionary.keys) == [
            "AutoStart", "StartDragTimeout", "ShowStartDragTimeoutIndicator",
            "ShowPath", "ShowGestureName", "ShowStatusIcon",
            "PathColorNormal", "PathColorRecognized",
            "LabelColorNormal", "LabelColorExecuted",
            "TargetMode", "PathLineWidth", "GesturePos", "SkipVersion",
        ])
        #expect(dictionary["SkipVersion"] is NSNull, "SkipVersion 必须写成 null，而不是被省略")
    }

    @Test("偏好编解码往返稳定")
    func preferencesRoundTrip() throws {
        let original = WGPreferences(startDragTimeout: 400, showPath: false, skipVersion: "9.9")
        let data = try WGConfigCodec.encodePreferences(original)
        #expect(try WGConfigCodec.decodePreferences(data) == original)
    }

    /// 菜单栏的开机自启开关会把这个字段写回 `prefs.json`，所以要保证它能原样往返。
    @Test("AutoStart 能原样解码并写回，不被默认值顶掉")
    func preservesAutoStart() throws {
        let off = try WGConfigCodec.decodePreferences(Data(#"{ "AutoStart": false }"#.utf8))
        #expect(off.autoStart == false)

        let written = try WGConfigCodec.encodePreferences(off)
        let dictionary = try #require(
            try JSONSerialization.jsonObject(with: written) as? [String: Any]
        )
        #expect(dictionary["AutoStart"] as? Bool == false, "AutoStart 必须写出 false 而不是被省略")
        #expect(try WGConfigCodec.decodePreferences(written).autoStart == false)
    }
}

@Suite("配置：版本目录选择")
struct LegacyImportTests {
    @Test("版本号按数值比较，2.10 高于 2.9")
    func comparesVersionsNumerically() {
        #expect(LegacyConfigImporter.compareVersions("2.10", "2.9") == 1)
        #expect(LegacyConfigImporter.compareVersions("2.3.3", "2.3.3") == 0)
        #expect(LegacyConfigImporter.compareVersions("2.3.2", "2.3.3") == -1)
    }

    /// 跑在提交进仓库的参考配置上（`Fixtures/legacy/2.3.3`），所以任何机器、以及 CI 上都会真的
    /// 执行。下面的数字是这份文件的基线 —— 换 fixture 就要一起改，见 `Fixtures/README.md`。
    @Test("导入参考配置")
    func importsTheReferenceConfiguration() throws {
        let directory = FixtureConfig.directory
        let result = try LegacyConfigImporter.load(from: directory)

        // 现有这份配置的实际内容：全局 49 条、Finder 3 条、桌面目标 0 条
        #expect(result.config.general.intents.count == 49)
        #expect(result.config.apps.count == 1)
        #expect(result.config.apps[0].name == "Finder")
        #expect(result.config.apps[0].intents.count == 3)
        #expect(result.config.specials.count == 1)
        #expect(result.statistics.intents == 52)
        #expect(result.statistics.stepsByType["StrokeStep"] == 39)
        #expect(result.statistics.stepsByType["MoveToEdgeCornerStep"] == 50)
        #expect(result.statistics.commandsByType["KeySeqCommand"] == 38)
        #expect(result.warnings.isEmpty, "参考配置不应该有未知类型：\(result.warnings)")

        // 偏好也要能读出来
        #expect(result.preferences?.startDragTimeout == 250)
        #expect(result.preferences?.showPath == true)
    }

    /// The strongest compatibility check available: read the reference files, write them back out,
    /// and require the JSON to be identical key for key. This is what catches a mistyped
    /// coding key or a field dropped by `encodeIfPresent`.
    @Test("参考配置重新编码后与原文件逐键一致")
    func reencodesReferenceFilesWithoutLoss() throws {
        let directory = FixtureConfig.directory
        let result = try LegacyConfigImporter.load(from: directory)

        let originalConfig = try loadJSON(directory.appendingPathComponent("gestures.json"))
        let reencodedConfig = try loadJSON(from: try WGConfigCodec.encode(result.config))
        #expect(reencodedConfig == originalConfig, "gestures.json 重新编码后与原文件不一致")

        let originalPreferences = try loadJSON(directory.appendingPathComponent("prefs.json"))
        let preferences = try #require(result.preferences)
        let reencodedPreferences = try loadJSON(from: try WGConfigCodec.encodePreferences(preferences))
        #expect(reencodedPreferences == originalPreferences, "prefs.json 重新编码后与原文件不一致")
    }

    /// 唯一一条仍然读**本机安装**的测试：用来发现真实世界里出现了仓库副本没覆盖到的版本或格式。
    /// 没装原版的机器上它被明确标为**跳过**（不是静默通过），所以不会让 CI 变红。
    ///
    /// 这里刻意只断言结构性事实 —— 具体条数随每台机器的配置而变，写死必然误报。
    @Test(
        "本机安装的原版配置能读进来（可选）",
        .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil)
    )
    func loadsALocalInstallWhenThereIsOne() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
        let result = try LegacyConfigImporter.load(from: directory)

        #expect(!result.config.general.intents.isEmpty)
        #expect(result.warnings.isEmpty, "本机配置里出现了无法识别的类型：\(result.warnings)")
    }

    private func loadJSON(_ url: URL) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? NSDictionary)
    }

    private func loadJSON(from data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}

@Suite("配置：按手势禁用（本项目扩展字段）")
struct IntentEnabledTests {
    private func intent(enabled: Bool) -> WGIntent {
        WGIntent(
            name: "Copy",
            gesture: [
                .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                .stroke(WGStrokeStep(isSimple: true, points: [0, 0, 0, 50])),
            ],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"])),
            enabled: enabled
        )
    }

    @Test("启用的手势不写 Enabled，和原版文件逐键一致")
    func enabledIntentsOmitTheKey() throws {
        let data = try WGConfigCodec.encode(WGConfig(general: WGTarget(
            kind: .general, id: "g", name: "General", intents: [intent(enabled: true)]
        )))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let general = try #require(json["General"] as? [String: Any])
        let intents = try #require(general["Intents"] as? [[String: Any]])
        let first = try #require(intents.first)
        #expect(first["Enabled"] == nil, "启用状态不写键，否则参考配置往返就不再逐键一致")
        #expect(Set(first.keys) == ["Name", "ExecuteOnRecognize", "Gesture", "Command"])
    }

    @Test("禁用的手势写出 Enabled: false，并能读回")
    func disabledIntentsRoundTrip() throws {
        let original = WGConfig(general: WGTarget(
            kind: .general, id: "g", name: "General", intents: [intent(enabled: false)]
        ))
        let data = try WGConfigCodec.encode(original)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let general = try #require(json["General"] as? [String: Any])
        let intents = try #require(general["Intents"] as? [[String: Any]])
        #expect(try #require(intents.first)["Enabled"] as? Bool == false)

        #expect(try WGConfigCodec.decode(data).config == original)
    }

    @Test("缺少 Enabled 键当作启用（所有现存配置都是这样）")
    func missingKeyMeansEnabled() throws {
        let json = """
        { "General": { "Id": "g", "Name": "General", "Intents": [
          { "Name": "Copy", "ExecuteOnRecognize": false,
            "Gesture": [ { "$type": "KeyDownStep", "Key": "MOUSE:1" },
                         { "$type": "StrokeStep", "IsSimple": true, "P": [0, 0, 0, 50] } ],
            "Command": { "$type": "KeySeqCommand", "IsSystemHotKey": false, "Keys": ["Command", "ANSI_C"] } } ],
          "Triggers": [] }, "Groups": [], "Apps": [], "Specials": [] }
        """
        let config = try WGConfigCodec.decode(Data(json.utf8)).config
        #expect(config.general.intents.first?.enabled == true)
    }
}

@Suite("配置：保存前自动备份")
struct ConfigStoreBackupTests {
    private func makeStore() throws -> ConfigStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwg-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ConfigStore(directory: directory)
    }

    private func config(named name: String) -> WGConfig {
        WGConfig(general: WGTarget(kind: .general, id: "g", name: name))
    }

    @Test("第一次保存没有旧文件，所以不产生备份")
    func firstSaveHasNothingToBackUp() throws {
        let store = try makeStore()
        try store.saveConfig(config(named: "一"))
        #expect(store.backups(for: "config").isEmpty)
    }

    @Test("第二次保存会先备份上一份内容")
    func backsUpThePreviousContents() throws {
        let store = try makeStore()
        try store.saveConfig(config(named: "旧"))
        try store.saveConfig(config(named: "新"))

        let backups = store.backups(for: "config")
        #expect(backups.count == 1)
        let restored = try WGConfigCodec.decode(try Data(contentsOf: try #require(backups.first))).config
        #expect(restored.general.name == "旧", "备份里必须是被覆盖掉的上一版")
        #expect(try store.loadConfig().config.general.name == "新")
    }

    @Test("备份放在子目录里，不影响加载与首次导入判断")
    func backupsDoNotDisturbLoading() throws {
        let store = try makeStore()
        try store.saveConfig(config(named: "一"))
        try store.saveConfig(config(named: "二"))
        #expect(store.hasConfig)
        #expect(try store.loadConfig().config.general.name == "二")
        // 备份目录里的是完整的配置文件，但名字不是 config.json，不会被误当成主配置。
        #expect(store.backupsDirectory.lastPathComponent == "Backups")
        #expect(FileManager.default.fileExists(atPath: store.configURL.path))
    }

    @Test("同一秒内连续保存不会互相覆盖备份")
    func sameSecondSavesKeepBothBackups() throws {
        let store = try makeStore()
        for name in ["一", "二", "三"] {
            try store.saveConfig(config(named: name))
        }
        // 三次保存 → 两份备份（第一次无旧文件），即使它们的时间戳相同也必须都在。
        #expect(store.backups(for: "config").count == 2)
    }

    @Test("备份数量上限为 10，淘汰最旧的")
    func prunesOldBackups() throws {
        let store = try makeStore()
        for index in 0..<15 {
            try store.saveConfig(config(named: "第\(index)版"))
        }
        let backups = store.backups(for: "config")
        #expect(backups.count == ConfigStore.backupLimit)

        // 15 次保存产生 14 份备份（第 0–13 版），保留最新的 10 份 = 第 4–13 版。
        // 逐份读内容检查 —— 只数数量看不出「是不是删错了哪一份」。
        var names: [String] = []
        for url in backups {
            names.append(try WGConfigCodec.decode(try Data(contentsOf: url)).config.general.name)
        }
        #expect(names.first == "第13版", "最新的一份备份必须是被覆盖掉的上一版，实际 \(names.first ?? "nil")")
        #expect(names.last == "第4版", "保留的下界应是第 4 版，实际 \(names.last ?? "nil")")
        #expect(!names.contains("第3版"), "更旧的必须被淘汰")
        // 名字序 = 时间序（这正是零填充后缀要保证的）。
        #expect(backups.map(\.lastPathComponent) == backups.map(\.lastPathComponent).sorted(by: >))
    }

    @Test("同一毫秒内连续保存：备份不互相顶掉，名字序仍是时间序")
    func sameMillisecondSavesStayOrdered() throws {
        // 把时钟钉死在同一毫秒，让撞名路径**必然**发生 —— 不然这个 bug 每 8 次才露一次
        // （它曾把新备份当成旧备份淘汰掉：撞名后缀 "-02" 排在基础名之前，因为 "-" < "."）。
        let store = try makeStore()
        let fixed = Date(timeIntervalSince1970: 1_800_000_000.123)
        store.now = { fixed }

        for index in 0..<15 {
            try store.saveConfig(config(named: "第\(index)版"))
        }

        let backups = store.backups(for: "config")
        #expect(backups.count == ConfigStore.backupLimit)
        // 名字形状必须完全一致，排序才等价于按时间排序。
        let names = backups.map(\.lastPathComponent)
        #expect(names == names.sorted(by: >), "名字序必须是时间序（降序）")
        let stampShape = /^config-\d{8}-\d{6}-\d{3}\.json$/
        #expect(names.allSatisfy { $0.wholeMatch(of: stampShape) != nil }, "不得出现带后缀的变体名：\(names)")

        // 15 次保存 → 14 份备份，保留最新 10 份 = 第 4–13 版。
        var versions: [String] = []
        for url in backups {
            versions.append(try WGConfigCodec.decode(try Data(contentsOf: url)).config.general.name)
        }
        #expect(versions.first == "第13版")
        #expect(versions.last == "第4版")
        #expect(!versions.contains("第3版"))
        #expect(Set(versions).count == versions.count, "不该有重复的版本")
    }

    @Test("偏好文件也各自独立备份")
    func preferencesGetTheirOwnBackups() throws {
        let store = try makeStore()
        try store.savePreferences(WGPreferences(startDragTimeout: 250))
        #expect(store.backups(for: "prefs").isEmpty)
        try store.savePreferences(WGPreferences(startDragTimeout: 400))
        #expect(store.backups(for: "prefs").count == 1)
        #expect(store.backups(for: "config").isEmpty, "两类备份不能混在一起")
        #expect(store.loadPreferences().startDragTimeout == 400)
    }
}

@Suite("配置：颜色格式往返")
struct WGColorHexRoundTripTests {
    @Test("解析后原样写回，大小写与位数都不变")
    func roundTripsTheOriginalFormat() {
        for hex in ["#7F7F7FC4", "#20D697E6", "#60606080", "#00000000", "#FFFFFFFF"] {
            let color = try? #require(WGColor(hex: hex))
            #expect(color?.hexString == hex, "\(hex) 往返后变了：\(color?.hexString ?? "nil")")
        }
    }

    @Test("六位形式按不透明处理，写回为八位")
    func sixDigitFormGetsFullAlpha() throws {
        let color = try #require(WGColor(hex: "20D697"))
        #expect(color.alpha == 1)
        #expect(color.hexString == "#20D697FF")
    }

    @Test("非法输入返回 nil，而不是崩掉覆盖层")
    func rejectsGarbage() {
        #expect(WGColor(hex: "") == nil)
        #expect(WGColor(hex: "#12345") == nil)
        #expect(WGColor(hex: "不是颜色") == nil)
    }

    @Test("越界的通道值会被夹住，不会写出非法十六进制")
    func clampsOutOfRangeChannels() {
        #expect(WGColor(red: 2, green: -1, blue: 0.5, alpha: 5).hexString == "#FF0080FF")
    }
}

@MainActor
@Suite("设置：偏好编辑模型")
struct PreferencesModelTests {
    /// 和用户真实 prefs.json 同形，但带一个非默认值便于区分「改过」与「没改」。
    private func makePreferences() -> WGPreferences {
        WGPreferences(
            autoStart: true,
            startDragTimeout: 250,
            showPath: true,
            showGestureName: true,
            showStatusIcon: true,
            pathColorNormal: "#7F7F7FC4",
            pathColorRecognized: "#20D697E6",
            labelColorNormal: "#60606080",
            labelColorExecuted: "#20D697E6",
            targetMode: .focused,
            pathLineWidth: 2.25,
            gesturePos: 0.25,
            skipVersion: "9.9"
        )
    }

    @Test("刚载入时没有改动，往返字段完全一致")
    func loadingIsNotADirtyState() {
        let model = PreferencesModel(preferences: makePreferences())
        #expect(!model.isDirty)
        #expect(model.editedPreferences == makePreferences(), "载入后立刻写回必须与原值一模一样")
        #expect(model.canSave)
    }

    @Test("改一项就算有改动，改回原值又变干净")
    func tracksDirtyStatePerField() {
        let model = PreferencesModel(preferences: makePreferences())

        model.startDragTimeout = 400
        #expect(model.isDirty)
        model.startDragTimeout = 250
        #expect(!model.isDirty)

        model.targetMode = .underCursor
        #expect(model.isDirty)
        model.targetMode = .focused
        #expect(!model.isDirty)

        model.showPath = false
        model.showGestureName = false
        #expect(model.isDirty)
        model.showPath = true
        model.showGestureName = true
        #expect(!model.isDirty)

        model.pathLineWidth = 4
        model.gesturePos = 0.6
        #expect(model.isDirty)
        model.pathLineWidth = 2.25
        model.gesturePos = 0.25
        #expect(!model.isDirty)
    }

    /// 关键：`AutoStart` 归系统（登录项）管，`SkipVersion` 是原版遗留，面板都不编辑，
    /// 但保存时**必须原样带回去**，否则会把手改的字段抹掉。
    @Test("面板不编辑的字段在写回时原样保留")
    func preservesFieldsThePaneDoesNotEdit() {
        let model = PreferencesModel(preferences: makePreferences())
        model.showPath = false
        let written = model.editedPreferences
        #expect(written.autoStart == true)
        #expect(written.skipVersion == "9.9")
        #expect(written.showStatusIcon == true, "未实现的开关也要原样保留，不能因为面板没有就写回默认值")
        #expect(written.showStartDragTimeoutIndicator == true)
        #expect(written.showPath == false)
    }

    @Test("颜色只在用户改动时才重写其十六进制串")
    func coloursAreOnlyRewrittenWhenChanged() {
        let model = PreferencesModel(preferences: makePreferences())
        #expect(model.pathColorNormalHex == "#7F7F7FC4", "未改动就保持原字符串")
        // 解析出来的是同一个颜色。
        #expect(model.pathColorNormal.hexString == "#7F7F7FC4")

        model.pathColorRecognized = WGColor(red: 1, green: 0, blue: 0, alpha: 1)
        #expect(model.pathColorRecognizedHex == "#FF0000FF")
        #expect(model.isDirty)
    }

    @Test("非法的手写值会被拦下，而不是写回一个坏文件")
    func validatesHandEditedValues() {
        var broken = makePreferences()
        broken.startDragTimeout = 5_000
        #expect(PreferencesModel(preferences: broken).canSave == false)
        #expect(PreferencesModel(preferences: broken).validationError?.contains("起始超时") == true)

        var narrow = makePreferences()
        narrow.pathLineWidth = 0.1
        #expect(PreferencesModel(preferences: narrow).canSave == false)

        var offscreen = makePreferences()
        offscreen.gesturePos = 3
        #expect(PreferencesModel(preferences: offscreen).canSave == false)

        // 颜色坏掉时不崩，界面上退回一个可显示的灰色……
        var badColour = makePreferences()
        badColour.pathColorNormal = "#ZZZ"
        let model = PreferencesModel(preferences: badColour)
        #expect(model.canSave, "颜色有问题不该阻止保存其它项")
        #expect(model.pathColorNormal.alpha > 0.7, "解析失败要退回一个可显示的默认色，而不是崩掉")
        // ……但**绝不能在用户没碰它的时候改写原字符串**：那等于悄悄改掉用户手写的文件。
        model.showPath = false
        #expect(model.editedPreferences.pathColorNormal == "#ZZZ", "没改的颜色必须原样带回去")
    }

    @Test("revert 丢弃改动，markSaved 把当前状态定为基准")
    func revertAndMarkSaved() {
        let model = PreferencesModel(preferences: makePreferences())
        model.startDragTimeout = 800
        #expect(model.isDirty)

        model.revert()
        #expect(!model.isDirty)
        #expect(model.startDragTimeout == 250)

        model.startDragTimeout = 800
        model.markSaved()
        #expect(!model.isDirty)
        #expect(model.editedPreferences.startDragTimeout == 800)
    }

    @Test("重新载入会回到磁盘上的值")
    func reloadsFromDisk() {
        let model = PreferencesModel(preferences: makePreferences())
        model.startDragTimeout = 800
        model.showPath = false

        model.load(preferences: makePreferences())
        #expect(model.startDragTimeout == 250)
        #expect(model.showPath)
        #expect(!model.isDirty)
    }

    @Test("线宽取整到 1/4，保持 prefs.json 可读")
    func roundsLineWidth() {
        #expect(PreferencesModel.roundedLineWidth(2.26) == 2.25)
        #expect(PreferencesModel.roundedLineWidth(2.9) == 3.0)
        #expect(PreferencesModel.roundedLineWidth(2.25) == 2.25)
    }
}
