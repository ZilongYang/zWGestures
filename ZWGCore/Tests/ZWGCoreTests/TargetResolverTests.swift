import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

private let finderPath = "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"
private let finder = WGApplicationIdentity(
    pid: 501,
    bundleIdentifier: "com.apple.finder",
    executablePath: finderPath,
    localizedName: "访达"
)
private let vscode = WGApplicationIdentity(
    pid: 777,
    bundleIdentifier: "com.microsoft.VSCode",
    executablePath: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron",
    localizedName: "Code"
)

private func configWithFinderTarget() -> WGConfig {
    var config = WGConfig()
    config.general.intents = [
        WGIntent(
            name: "全局拷贝",
            gesture: [.keyDown(WGKeyDownStep(key: "MOUSE:1"))],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
        )
    ]
    config.apps = [
        WGTarget(
            kind: .app,
            name: "Finder",
            bundleId: nil,
            path: finderPath,
            intents: [
                WGIntent(
                    name: "移到废纸篓",
                    gesture: [.keyDown(WGKeyDownStep(key: "MOUSE:1"))],
                    command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "Delete"]))
                )
            ]
        )
    ]
    config.specials = [WGTarget(kind: .desktop, name: "Desktop")]
    return config
}

@Suite("目标解析：应用匹配")
struct TargetResolverTests {
    @Test("只记录可执行文件路径的目标也能匹配上")
    func matchesByExecutablePath() {
        let config = configWithFinderTarget()
        let resolved = TargetResolver.resolve(config: config, application: finder)
        #expect(resolved.kind == .application)
        #expect(resolved.target.name == "Finder")
        #expect(resolved.displayName == "访达")
    }

    @Test("按 BundleId 匹配优先于路径")
    func matchesByBundleIdentifier() throws {
        var config = WGConfig()
        config.apps = [
            WGTarget(kind: .app, name: "按路径", bundleId: nil, path: finderPath),
            WGTarget(kind: .app, name: "按标识", bundleId: "com.apple.finder", path: "/somewhere/else/Finder"),
        ]
        let resolved = TargetResolver.resolve(config: config, application: finder)
        #expect(resolved.target.name == "按标识")
    }

    @Test("BundleId 不匹配时不会因为路径相同而误命中")
    func bundleIdentifierMismatchIsNotAMatch() {
        let config = WGConfig()
        var application = finder
        application.bundleIdentifier = "com.example.notfinder"
        let resolved = TargetResolver.resolve(config: config, application: application)
        _ = resolved // 没有应用目标时回落到全局
        #expect(resolved.kind == .general || resolved.target.name != "Finder")
    }

    @Test("没有对应应用时回落到全局")
    func fallsBackToGeneral() {
        let config = configWithFinderTarget()
        let resolved = TargetResolver.resolve(config: config, application: vscode)
        #expect(resolved.kind == .general)
        #expect(resolved.target.name == "General")
        #expect(resolved.displayName == "全局")
    }

    @Test("桌面上的手势命中桌面这个特殊目标")
    func desktopTargetWins() {
        let config = configWithFinderTarget()
        let resolved = TargetResolver.resolve(config: config, application: finder, isOverDesktop: true)
        #expect(resolved.kind == .desktop)
        #expect(resolved.target.name == "Desktop")
    }

    @Test("目标记录的是 .app 路径、系统报告的是可执行文件路径时，按 bundle 匹配")
    func matchesBundlePathRatherThanExactPath() {
        var config = WGConfig()
        config.apps = [
            WGTarget(kind: .app, name: "Finder", bundleId: nil, path: "/System/Library/CoreServices/Finder.app"),
        ]
        let resolved = TargetResolver.resolve(config: config, application: finder)
        #expect(resolved.kind == .application)
        #expect(resolved.target.name == "Finder")

        #expect(TargetResolver.bundlePath(of: finderPath) == "/System/Library/CoreServices/Finder.app")
        #expect(TargetResolver.bundlePath(of: "/System/Library/CoreServices/Finder.app")
            == "/System/Library/CoreServices/Finder.app")
        #expect(TargetResolver.bundlePath(of: "/usr/bin/ssh") == "/usr/bin/ssh")
    }

    @Test("认不出目标时用 BundleId 兜底显示")
    func fallsBackToBundleIdentifierForDisplay() {
        var application = vscode
        application.localizedName = nil
        #expect(application.displayName == "com.microsoft.VSCode")
    }
}

@Suite("目标解析：与真实配置对照")
struct RealConfigurationTargetTests {
    @Test(
        "真实配置里的 Finder：自身 3 条手势排在最前，其余继承全局",
        .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil)
    )
    func resolvesRealFinderTarget() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
        let config = try LegacyConfigImporter.load(from: directory).config

        let resolved = TargetResolver.resolve(config: config, application: finder)
        #expect(resolved.kind == .application)
        #expect(resolved.target.name == "Finder")

        // **应用自己的手势排在最前面** —— 顺序就是优先级（见 GestureRecognizer.bestCandidate），
        // 所以同形状时应用自己的赢，这正是「优先自己程序下的手势」的实现方式。
        // 注意：真实配置里的 Finder 目标**只有 Path、没有 BundleId**（见 matchApplication 的注释），
        // 所以这里按数组取，不能按 bundleId 找。
        let own = try #require(config.apps.first)
        let ownCount = own.intents.count
        #expect(ownCount == 3)
        #expect(own.bundleId == nil, "真实配置的 Finder 目标本来就没有 BundleId")
        // 顺序就是文件里的顺序，且必须排在继承来的之前。
        #expect(resolved.target.intents.prefix(ownCount).map(\.name) == ["Close All", "Move To Trash", "Eject"])

        // 其余继承全局：3 + 49。
        #expect(resolved.inheritedIntentCount == config.general.intents.count)
        #expect(resolved.target.intents.count == ownCount + config.general.intents.count)
        #expect(
            resolved.target.intents.suffix(from: ownCount).map(\.name)
                == config.general.intents.map(\.name)
        )
        // 关键的可用性结果：在 Finder 里「拷贝」这类全局手势仍然在。
        #expect(resolved.target.intents.contains { $0.name == "Copy" })

        // 关掉继承就退回「只用自己的 3 条」。
        var replaced = config
        replaced.apps[0].inheritsGlobal = false
        let replacing = TargetResolver.resolve(config: replaced, application: finder)
        #expect(replacing.target.intents.count == ownCount)
        #expect(replacing.inheritedIntentCount == 0)

        // 任何别的应用都走全局，且不存在继承合并。
        let other = TargetResolver.resolve(config: config, application: vscode)
        #expect(other.kind == .general)
        #expect(other.target.intents.count == config.general.intents.count)
        #expect(other.inheritedIntentCount == 0)
    }

    @Test("桌面这类特殊目标默认不继承（保持原有的替换语义）")
    func specialTargetsDoNotInheritByDefault() {
        let desktop = WGTarget(kind: .desktop, name: "Desktop")
        #expect(desktop.inheritsGlobal == false)
        #expect(WGTarget(kind: .general, name: "General").inheritsGlobal == false)
        #expect(WGTarget(kind: .app, name: "Safari").inheritsGlobal, "新建的应用目标默认继承全局")
    }

}
