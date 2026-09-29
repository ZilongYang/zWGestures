import Foundation
import Testing

@testable import ZWGCore

@Suite("出厂默认手势包（随 App 发布的 Resources/Defaults/）")
struct DefaultGesturePackTests {
    /// The pack's exact name set.
    ///
    /// Pinned deliberately: it is what a fresh install shows, so regenerating it against a different
    /// original version — or against somebody's personal configuration — should be a conscious
    /// change that has to be reviewed here, not a silent one.
    private static let expectedNames: Set<String> = [
        "拷贝", "粘贴", "Web 搜索", "粘贴并 Enter", "剪切", "退格", "删除", "Enter", "撤销",
        "音量+", "音量-", "静音", "亮度+", "亮度-", "退出", "强制退出", "切换 App", "后退",
        "前进", "重新载入", "强制重新载入", "关闭", "重开标签", "新建", "地址栏", "上一标签",
        "下一标签", "Home 键", "End 键", "全屏", "最小化", "终端", "活动监视器", "睡眠", "关机",
        "播放/暂停", "上一曲", "下一曲", "关闭窗口", "全部关闭", "移到废纸篓", "弹出",
    ]

    /// Imports the committed pack into a throwaway store and hands both to `body`.
    ///
    /// The temporary directory is removed on the way out, so no test touches the real configuration.
    private func withSeededStore<T>(
        from defaults: URL,
        _ body: (ConfigStore, WGImportResult) throws -> T
    ) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwg-defaults-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(directory: directory)
        let result = try store.importDefaultConfiguration(from: defaults)
        return try body(store, result)
    }

    private func committedDefaults() throws -> URL {
        try #require(
            RepoPaths.appDefaults,
            "找不到 zWGestures/Resources/Defaults —— 先跑 make default-gestures"
        )
    }

    @Test("导入后是 48 条手势，且「拷贝」绑定 ⌘C")
    func seedsTheFactorySet() throws {
        try withSeededStore(from: try committedDefaults()) { store, result in
            #expect(result.statistics.intents == 48)

            let config = try store.loadConfig().config
            #expect(config.allTargets.reduce(0) { $0 + $1.intents.count } == 48)

            let copy = try #require(
                config.general.intents.first { $0.name == "拷贝" },
                "出厂默认里必须有「拷贝」"
            )
            guard case .keySequence(let command) = copy.command else {
                Issue.record("「拷贝」应当是按键序列，实际是 \(copy.command)")
                return
            }
            #expect(command.keys.compactMap { $0 } == ["Command", "ANSI_C"])
        }
    }

    @Test("名册被钉死：48 条、42 个不同的中文名、重名分布与原版出厂一致")
    func nameRosterIsPinned() throws {
        try withSeededStore(from: try committedDefaults()) { store, _ in
            let config = try store.loadConfig().config
            let names = config.allTargets.flatMap { $0.intents.map(\.name) }

            #expect(names.count == 48)
            #expect(Set(names) == Self.expectedNames)

            // These duplicates exist in the original's factory set too: they are told apart by their
            // gesture modifiers, so they are data, not a mistake.
            #expect(names.filter { $0 == "关闭" }.count == 2)
            #expect(names.filter { $0 == "新建" }.count == 2)
            #expect(names.filter { $0 == "上一标签" }.count == 3)
            #expect(names.filter { $0 == "下一标签" }.count == 3)
        }
    }

    @Test("这是原版的出厂手势集，不是维护者自己的配置")
    func isTheFactorySetNotSomeonesOwnConfig() throws {
        // 维护者本机配置里有这几条原版出厂没有的手势。它们出现在默认包里就说明生成时读错了源。
        let personalOnly = ["上一个应用", "下一应用", "其他窗口", "重新打开"]
        try withSeededStore(from: try committedDefaults()) { store, _ in
            let config = try store.loadConfig().config
            let names = Set(config.allTargets.flatMap { $0.intents.map(\.name) })
            for name in personalOnly {
                #expect(!names.contains(name), "默认包里出现了只属于某个人的手势：\(name)")
            }
        }
    }

    @Test("默认偏好：AutoStart 关掉了，SkipVersion 保留为 null")
    func preferencesDisableAutoStart() throws {
        try withSeededStore(from: try committedDefaults()) { store, _ in
            let preferences = store.loadPreferences()
            // 原版的 `AutoStart` 指的是「原版 App 开机自启」。默认包不能替用户去注册登录项 ——
            // 控制器还会拿系统实际状态再纠正一次（见 ConfigController.correctLoginItem）。
            #expect(preferences.autoStart == false)
            // 保留 null 是有意的：它守着 `encodeIfPresent` 那条编码路径。
            #expect(preferences.skipVersion == nil)
            #expect(preferences.targetMode == .focused)
        }
    }

    @Test("逐键往返相等：重新编码不丢键、不改值")
    func roundTripsKeyForKey() throws {
        let data = try Data(contentsOf: try committedDefaults().appendingPathComponent("gestures.json"))
        let decoded = try WGConfigCodec.decode(data)
        let reencoded = try WGConfigCodec.encode(decoded.config)

        let original = try #require(
            try JSONSerialization.jsonObject(with: data) as? NSDictionary
        )
        let round = try #require(
            try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary
        )
        #expect(round == original)
    }

    @Test("没有 unknown 步骤或命令，且按键序列里的键名全部可识别")
    func hasNoUnknownKeys() throws {
        try withSeededStore(from: try committedDefaults()) { store, _ in
            let config = try store.loadConfig().config

            for target in config.allTargets {
                let steps = target.intents.flatMap(\.gesture) + target.triggers.flatMap(\.def)
                for step in steps {
                    if case .unknown(let type) = step {
                        Issue.record("目标「\(target.displayName)」含未知步骤 \(type)")
                    }
                }
                for intent in target.intents {
                    if case .unknown(let type) = intent.command {
                        Issue.record("手势「\(intent.name)」含未知命令 \(type)")
                    }
                    guard case .keySequence(let command) = intent.command else { continue }
                    for name in command.keys.compactMap({ $0 }) {
                        #expect(
                            WGKeyCode.classify(name) != .unknown,
                            "手势「\(intent.name)」里的键名 \(name) 无法识别"
                        )
                    }
                }
            }
        }
    }

    @Test("默认包里没有隐私数据")
    func hasNoPersonalData() throws {
        // 这一类疏漏真的发生过：计划存档里曾经写进了作者邮箱与激活码前缀。
        let data = try Data(contentsOf: try committedDefaults().appendingPathComponent("gestures.json"))
        let text = String(decoding: data, as: UTF8.self)
        for needle in ["license", "Serial", "@gmail", "@163", "/Users/"] {
            #expect(
                !text.localizedCaseInsensitiveContains(needle),
                "默认包里出现了 \(needle)"
            )
        }
    }
}
