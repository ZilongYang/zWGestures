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

    @Test("任意形状手势保存的是原始屏幕坐标，既不倒序也不翻转 y")
    func arbitraryShapeKeepsRawCoordinates() throws {
        let config = try decodeFixture()
        let stroke = try #require(config.apps[0].intents[0].strokeStep)
        #expect(!stroke.isSimple)
        #expect(stroke.points.count == 6)
        #expect(stroke.drawingOrderPoints.first == CGPoint(x: 969, y: 546))
        #expect(stroke.drawingOrderPoints.allSatisfy { $0.y > 0 }, "屏幕坐标的 y 一定是正数")
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
}

@Suite("配置：版本目录选择")
struct LegacyImportTests {
    @Test("版本号按数值比较，2.10 高于 2.9")
    func comparesVersionsNumerically() {
        #expect(LegacyConfigImporter.compareVersions("2.10", "2.9") == 1)
        #expect(LegacyConfigImporter.compareVersions("2.3.3", "2.3.3") == 0)
        #expect(LegacyConfigImporter.compareVersions("2.3.2", "2.3.3") == -1)
    }

    /// Runs against the real installation when there is one; reported as disabled otherwise,
    /// so a silent skip is impossible.
    @Test(
        "导入本机真实的 WGestures 配置",
        .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil)
    )
    func importsTheRealConfiguration() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
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
        #expect(result.warnings.isEmpty, "真实配置不应该有未知类型：\(result.warnings)")

        // 偏好也要能读出来
        #expect(result.preferences?.startDragTimeout == 250)
        #expect(result.preferences?.showPath == true)
    }

    /// The strongest compatibility check available: read the real files, write them back out,
    /// and require the JSON to be identical key for key. This is what catches a mistyped
    /// coding key or a field dropped by `encodeIfPresent`.
    @Test(
        "真实配置文件重新编码后与原文件逐键一致",
        .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil)
    )
    func reencodesRealFilesWithoutLoss() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
        let result = try LegacyConfigImporter.load(from: directory)

        let originalConfig = try loadJSON(directory.appendingPathComponent("gestures.json"))
        let reencodedConfig = try loadJSON(from: try WGConfigCodec.encode(result.config))
        #expect(reencodedConfig == originalConfig, "gestures.json 重新编码后与原文件不一致")

        let originalPreferences = try loadJSON(directory.appendingPathComponent("prefs.json"))
        let preferences = try #require(result.preferences)
        let reencodedPreferences = try loadJSON(from: try WGConfigCodec.encodePreferences(preferences))
        #expect(reencodedPreferences == originalPreferences, "prefs.json 重新编码后与原文件不一致")
    }

    private func loadJSON(_ url: URL) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? NSDictionary)
    }

    private func loadJSON(from data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}
