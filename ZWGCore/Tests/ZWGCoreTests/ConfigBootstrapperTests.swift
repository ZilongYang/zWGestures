import Foundation
import Testing

@testable import ZWGCore

@Suite("首启决策：已有配置 > 原版安装 > 内置默认")
struct ConfigBootstrapperTests {
    private let legacy = URL(fileURLWithPath: "/tmp/legacy/2.3.3")
    private let defaults = URL(fileURLWithPath: "/tmp/Defaults")

    @Test("已有配置就原样载入：不导入、也不播种")
    func existingConfigWins() {
        let source = ConfigBootstrapper.decide(
            hasConfig: true,
            legacyDirectory: legacy,
            defaultsDirectory: defaults
        )
        #expect(source == .existingConfig)
    }

    @Test("没有配置但装了原版：优先导入原版，而不是内置默认")
    func legacyBeatsFactoryDefaults() {
        let source = ConfigBootstrapper.decide(
            hasConfig: false,
            legacyDirectory: legacy,
            defaultsDirectory: defaults
        )
        #expect(source == .legacyInstall(legacy))
    }

    @Test("既没配置也没原版：播种内置默认 —— 这正是下载版用户的路径")
    func fallsBackToFactoryDefaults() {
        let source = ConfigBootstrapper.decide(
            hasConfig: false,
            legacyDirectory: nil,
            defaultsDirectory: defaults
        )
        #expect(source == .factoryDefault(defaults))
    }

    @Test("两个来源都没有时返回 nil，由调用方决定怎么提示")
    func nothingAvailable() {
        #expect(ConfigBootstrapper.decide(
            hasConfig: false,
            legacyDirectory: nil,
            defaultsDirectory: nil
        ) == nil)
    }

    @Test("即使没有任何来源，已有配置也不会被顶掉")
    func existingConfigStillWinsWithoutSources() {
        #expect(ConfigBootstrapper.decide(
            hasConfig: true,
            legacyDirectory: nil,
            defaultsDirectory: nil
        ) == .existingConfig)
    }
}
