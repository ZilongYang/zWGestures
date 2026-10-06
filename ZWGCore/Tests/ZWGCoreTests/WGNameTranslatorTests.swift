import Foundation
import Testing

@testable import ZWGCore

/// 「把英文手势名改成中文」的规则守卫。
///
/// 这是本项目里少数**会改写用户配置数据**的功能，所以边界比功能本身重要：只改表里查得到的名字，
/// 用户自己起的名字一个字都不能动，而且必须幂等。
@Suite("手势名中文化")
struct WGNameTranslatorTests {
    /// 用**真实出厂默认包**的手势当素材，只把名字换成测试需要的。
    ///
    /// 一开始手写 JSON fixture，结果一遍遍地补 `Id`、`IsSimple` 这些必填键 —— 手写的配置永远追不上
    /// 格式。直接用随 App 发布的那份包：不用维护，也顺带保证测试跑在真数据上。
    private func makeConfig(names: [String]) throws -> WGConfig {
        let directory = try #require(
            RepoPaths.appDefaults("zh-Hans"),
            "找不到默认包 —— 先跑 make default-gestures"
        )
        let data = try Data(contentsOf: directory.appendingPathComponent("gestures.json"))
        var config = try WGConfigCodec.decode(data).config

        var intents = Array(config.general.intents.prefix(names.count))
        for (index, name) in names.enumerated() where intents.indices.contains(index) {
            intents[index].name = name
        }
        config.mutateTarget(at: 0) { $0.intents = intents }
        return config
    }

    private let table = ["Copy": "拷贝", "Web Search": "Web 搜索", "Close": "关闭"]

    @Test("只改表里查得到的名字")
    func renamesOnlyKnownNames() throws {
        var config = try makeConfig(names: ["Copy", "My Own Gesture", "Web Search"])
        let renames = WGNameTranslator.renames(in: config, using: table)

        #expect(renames.map(\.from) == ["Copy", "Web Search"])
        #expect(renames.map(\.to) == ["拷贝", "Web 搜索"])
        #expect(renames.map(\.intentIndex) == [0, 2])

        #expect(WGNameTranslator.apply(renames, to: &config) == 2)
        #expect(config.general.intents.map(\.name) == ["拷贝", "My Own Gesture", "Web 搜索"])
    }

    @Test("已经是中文、或名字与译名相同，都不动")
    func skipsAlreadyTranslatedAndIdentical() throws {
        var config = try makeConfig(names: ["拷贝", "Enter"])
        let identityTable = ["Enter": "Enter", "拷贝": "拷贝"]
        #expect(WGNameTranslator.renames(in: config, using: identityTable).isEmpty)
        #expect(WGNameTranslator.apply([], to: &config) == 0)
        #expect(config.general.intents.map(\.name) == ["拷贝", "Enter"])
    }

    @Test("幂等：改完再跑一次没有任何改动")
    func isIdempotent() throws {
        var config = try makeConfig(names: ["Copy", "Close", "Copy"])
        let first = WGNameTranslator.renames(in: config, using: table)
        #expect(first.count == 3)
        #expect(WGNameTranslator.apply(first, to: &config) == 3)
        #expect(config.general.intents.map(\.name) == ["拷贝", "关闭", "拷贝"])
        #expect(WGNameTranslator.renames(in: config, using: table).isEmpty)
    }

    @Test("表为空或越界的索引都安全")
    func emptyTableAndStaleIndexAreSafe() throws {
        var config = try makeConfig(names: ["Copy"])
        #expect(WGNameTranslator.renames(in: config, using: [:]).isEmpty)

        // 陈旧的索引（配置在这之后被编辑过）不该越界崩溃。
        let stale = WGNameTranslator.Rename(
            targetIndex: 9, intentIndex: 9, from: "Copy", to: "拷贝"
        )
        #expect(WGNameTranslator.apply([stale], to: &config) == 0)
        #expect(config.general.intents.map(\.name) == ["Copy"])
    }

    @Test("译名表文件缺失或损坏都当作空表，不让应用起不来")
    func damagedTableLoadsAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwg-names-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(WGNameTranslator.loadTranslations(from: directory.appendingPathComponent("nope.json")).isEmpty)

        let damaged = directory.appendingPathComponent("damaged.json")
        try Data("{ not json".utf8).write(to: damaged)
        #expect(WGNameTranslator.loadTranslations(from: damaged).isEmpty)

        let good = directory.appendingPathComponent("good.json")
        try Data(#"{"Copy":"拷贝"}"#.utf8).write(to: good)
        #expect(WGNameTranslator.loadTranslations(from: good) == ["Copy": "拷贝"])
    }
}
