import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

/// The recognition index exists to keep per-event work off the event-tap thread. These tests pin the
/// two things that can go wrong with it: a gesture that can never fire must not be scored, and the id
/// a resolution returns must be one the index actually knows — the merge rule for inheriting targets
/// lives in exactly one place (`TargetResolver.effectiveTarget`) for that reason.
@Suite("识别索引：把永不生效的手势提前摘出去")
struct GestureIndexTests {
    private func referenceConfig() throws -> WGConfig {
        let url = FixtureConfig.directory.appendingPathComponent("gestures.json")
        return try WGConfigCodec.decode(try Data(contentsOf: url)).config
    }

    private func identity(for target: WGTarget) -> WGApplicationIdentity {
        WGApplicationIdentity(
            pid: 1,
            bundleIdentifier: target.bundleId,
            executablePath: target.path,
            localizedName: target.name
        )
    }

    @Test("索引只保留真正可能命中的手势，且形状都已归一化")
    func excludesGesturesThatCanNeverFire() throws {
        let config = try referenceConfig()
        let index = GestureIndex(target: config.general)

        // 参考配置里有一部分手势用的是本版本还不支持的触发方式（边角 / 滚轮），还有被禁用的。
        // 它们在构建索引时就被剔除，而不是每个事件都白算一遍再被否决。
        #expect(!index.gestures.isEmpty)
        #expect(index.gestures.count < config.general.intents.count)

        for prepared in index.gestures {
            #expect(prepared.shape.count == index.settings.sampleCount)
            #expect(prepared.intent.enabled)
            #expect(prepared.intent.strokeStep != nil)
        }
    }

    @Test("每个能被解析出来的目标都能在索引里命中 —— 合并规则只有一处实现")
    func everyResolvedTargetIsIndexed() throws {
        let config = try referenceConfig()
        let index = RecognitionIndex(config: config)

        let general = TargetResolver.resolve(config: config, application: nil)
        #expect(index.index(for: general) != nil)

        for target in config.apps {
            let resolved = TargetResolver.resolve(config: config, application: identity(for: target))
            #expect(index.index(for: resolved) != nil, "目标「\(target.name)」解析后找不到索引")
        }

        if !config.specials.isEmpty {
            let desktop = TargetResolver.resolve(config: config, application: nil, isOverDesktop: true)
            #expect(index.index(for: desktop) != nil, "桌面目标解析后找不到索引")
        }
    }

    @Test("继承全局的应用目标：索引里自己的手势排在全局之前")
    func inheritedIndexKeepsOwnGesturesFirst() throws {
        let config = try referenceConfig()
        let index = RecognitionIndex(config: config)

        var checked = 0
        for target in config.apps where target.inheritsGlobal {
            let ownNames = target.intents
                .filter { $0.enabled && $0.strokeStep != nil }
                .map(\.name)
            guard !ownNames.isEmpty else { continue }

            let resolved = TargetResolver.resolve(config: config, application: identity(for: target))
            let prepared = try #require(index.index(for: resolved))
            let names = prepared.gestures.map(\.intent.name)

            // 列表顺序就是优先级，所以应用自己的手势必须排在继承来的前面。
            #expect(Array(names.prefix(ownNames.count)) == ownNames, "「\(target.name)」的优先级顺序错了")
            #expect(names.count == ownNames.count + GestureIndex(target: config.general).gestures.count)
            checked += 1
        }
        #expect(checked > 0, "参考配置里应当至少有一个继承全局的应用目标")
    }
}

/// 2026-10-06：用户报「松手后动作偶尔慢半拍」。根因是性能硬化把整份索引的构建搬进了
/// `updateRecognition`，而它每 3 秒被应用目录刷新触发一次，还跑在主线程上 —— 那正是识别结果
/// 交接给命令执行的那条路。修法是把「规则变了」与「应用目录变了」分开：后者不再重建。
@Suite("识别索引：目录刷新不该重建索引")
struct RecognitionIndexCacheTests {
    private func referenceConfig() throws -> WGConfig {
        let url = FixtureConfig.directory.appendingPathComponent("gestures.json")
        return try WGConfigCodec.decode(try Data(contentsOf: url)).config
    }

    @Test("同一份配置连着问多次只构建一次")
    func sameConfigurationBuildsOnce() throws {
        let config = try referenceConfig()
        var cache = RecognitionIndexCache()

        let first = cache.index(for: config)
        #expect(first.rebuilt)
        #expect(cache.buildCount == 1)

        // 3 秒一次的应用目录刷新走的就是这条：内容相同的配置不该再构建一遍。
        for _ in 0..<20 {
            let next = cache.index(for: config)
            #expect(!next.rebuilt)
            #expect(next.index.gestureCount == first.index.gestureCount)
        }
        #expect(cache.buildCount == 1)
    }

    @Test("配置或识别设置变了才重建")
    func changedInputRebuilds() throws {
        let config = try referenceConfig()
        var cache = RecognitionIndexCache()
        _ = cache.index(for: config)

        var edited = config
        edited.general.intents.removeLast()
        #expect(cache.index(for: edited).rebuilt, "配置变了必须重建")
        #expect(cache.buildCount == 2)

        _ = cache.index(for: edited)
        #expect(!cache.index(for: edited).rebuilt)

        #expect(
            cache.index(for: edited, settings: RecognitionSettings(matchThreshold: 0.2)).rebuilt,
            "阈值变了也必须重建"
        )
        #expect(cache.buildCount == 3)
    }

    @Test("缓存返回的索引仍然是可用的一整份")
    func cachedIndexIsUsable() throws {
        let config = try referenceConfig()
        var cache = RecognitionIndexCache()
        let built = cache.index(for: config).index

        let resolved = TargetResolver.resolve(config: config, application: nil)
        let general = try #require(built.index(for: resolved))
        #expect(!general.gestures.isEmpty)
        // 结构度量与弧长度量都要有：参考配置里既有折线手势，也有闭环手势。
        #expect(general.gestures.contains { $0.metric == .structure })
        #expect(general.gestures.contains { $0.metric == .arcLength })
    }
}
