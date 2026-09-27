import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

private func keyed(_ key: String) -> WGStep { .keyDown(WGKeyDownStep(key: key)) }
private func edge(_ value: Int) -> WGStep {
    .moveToEdgeCorner(WGMoveToEdgeCornerStep(edgeCorner: WGEdgeCorner(value: value)))
}

private func matrix(_ rows: [(signature: [WGStep], enabled: Bool)]) -> WGTriggerMatrix {
    WGTriggerMatrix(
        rows: rows.map {
            WGTriggerRow(
                signature: WGTriggerSignature.make(from: $0.signature) ?? WGTriggerSignature(tokens: []),
                enabled: $0.enabled
            )
        },
        isOverridden: true
    )
}

@Suite("触发矩阵：签名解析")
struct TriggerSignatureTests {
    @Test("鼠标键、滚轮与边角被解析成可比较的记号")
    func parsesTokens() {
        #expect(WGTriggerSignature.make(from: [keyed("MOUSE:1")])?.tokens == [.mouse(.right)])
        #expect(WGTriggerSignature.make(from: [edge(8)])?.tokens == [.edge(.left)])
        #expect(WGTriggerSignature.make(from: [edge(9)])?.tokens == [.edge([.top, .left])])
        #expect(WGTriggerSignature.make(from: [edge(1), keyed("VSCROLL:-13")])?.tokens
            == [.edge(.top), .scroll(isHorizontal: false, direction: -1)])
        // 幅度不参与身份：-1 与 -13 是同一行
        #expect(WGTriggerSignature.make(from: [keyed("VSCROLL:-1")])
            == WGTriggerSignature.make(from: [keyed("VSCROLL:-13")]))
    }

    @Test("无法解释的步骤返回 nil，调用方不应据此拦截")
    func returnsNilForUnknownSteps() {
        #expect(WGTriggerSignature.make(from: [keyed("Command")]) == nil)
        #expect(WGTriggerSignature.make(from: [.stroke(WGStrokeStep(isSimple: true, points: [0, 0]))]) == nil)
    }

    @Test("前缀关系只认从头开始的连续匹配")
    func prefixRelationship() {
        let short = WGTriggerSignature(tokens: [.mouse(.right)])
        let long = WGTriggerSignature(tokens: [.mouse(.right), .scroll(isHorizontal: false, direction: -1)])
        let other = WGTriggerSignature(tokens: [.edge(.top)])
        #expect(short.isPrefix(of: long))
        #expect(!long.isPrefix(of: short))
        #expect(!other.isPrefix(of: long))
    }
}

@Suite("触发矩阵：启用判定")
struct TriggerMatrixTests {
    @Test("最长的匹配行生效：可以只关掉「上边缘 + 滚轮」而保留「上边缘」")
    func longestMatchWins() {
        let m = matrix([
            ([edge(1)], true),
            ([edge(1), keyed("VSCROLL:-1")], false),
        ])
        #expect(m.allows(WGTriggerSignature(tokens: [.edge(.top)])))
        #expect(!m.allows(WGTriggerSignature(tokens: [.edge(.top), .scroll(isHorizontal: false, direction: -1)])))
    }

    @Test("空矩阵不做限制")
    func emptyMatrixAllowsEverything() {
        #expect(WGTriggerMatrix.empty.allows(WGTriggerSignature(tokens: [.mouse(.right)])))
    }

    @Test("矩阵里没有列出该触发方式时不禁用")
    func unlistedTriggersAreAllowed() {
        let m = matrix([([keyed("MOUSE:1")], false)])
        #expect(!m.allows(WGTriggerSignature(tokens: [.mouse(.right)])))
        #expect(m.allows(WGTriggerSignature(tokens: [.mouse(.center)])))
    }

    @Test("目标自己的矩阵覆盖全局；空矩阵表示继承")
    func targetMatrixOverridesOrInherits() {
        var general = WGTarget.makeGeneral()
        general.triggers = [WGTrigger(def: [keyed("MOUSE:1")], enabled: true)]

        var inheriting = WGTarget(kind: .app, name: "A")
        inheriting.triggers = []
        #expect(WGTriggerMatrix.effective(for: inheriting, inheriting: general).isOverridden == false)
        #expect(WGTriggerMatrix.effective(for: inheriting, inheriting: general)
            .allows(WGTriggerSignature(tokens: [.mouse(.right)])))

        var overriding = WGTarget(kind: .app, name: "B")
        overriding.triggers = [WGTrigger(def: [keyed("MOUSE:1")], enabled: false)]
        #expect(WGTriggerMatrix.effective(for: overriding, inheriting: general).isOverridden)
        #expect(!WGTriggerMatrix.effective(for: overriding, inheriting: general)
            .allows(WGTriggerSignature(tokens: [.mouse(.right)])))
    }
}

@Suite("触发矩阵：与真实配置对照")
struct RealConfigurationTriggerTests {
    /// The reference configuration disables the whole top edge and the bottom-edge scroll row.
    /// Without honouring the matrix those gestures would fire — including `睡眠` and `关机`,
    /// which is exactly the kind of accident the matrix exists to prevent.
    @Test(
        "真实配置禁用的触发方式必须真的被禁用",
        .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil)
    )
    func respectsTheRealConfiguration() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
        let config = try LegacyConfigImporter.load(from: directory).config
        let resolved = TargetResolver.resolve(config: config, application: nil)
        let m = resolved.triggerMatrix

        func allows(_ name: String) -> Bool? {
            guard let intent = config.general.intents.first(where: { $0.name == name }),
                  let signature = WGTriggerSignature.make(from: intent.triggerSteps)
            else { return nil }
            return m.allows(signature)
        }

        // 上边缘整条被关闭
        #expect(allows("Volume +") == false)
        #expect(allows("Volume -") == false)
        #expect(allows("Mute") == false)
        #expect(allows("Sleep") == false, "睡眠依赖上边缘 + 右键，必须被矩阵拦下")
        #expect(allows("Shut Down") == false, "关机同理")
        #expect(allows("Play/Pause") == false)

        // 亮度：上边缘本身开着，但「下边缘 + 滚轮」那一行被关了
        #expect(allows("Brightness +") == false)
        #expect(allows("Brightness -") == false)

        // 这些没有被关闭
        #expect(allows("Copy") == true)
        #expect(allows("Paste") == true)
        #expect(allows("Close") == true)
        #expect(allows("Terminal") == true)
        #expect(allows("Activity Monitor") == true)
        #expect(allows("Switch App") == true)
    }
}
