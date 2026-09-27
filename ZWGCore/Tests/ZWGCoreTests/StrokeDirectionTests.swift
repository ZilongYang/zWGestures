import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

/// Pins the stroke encoding against the original app's own documentation and against the
/// semantics of the commands each gesture is bound to.
///
/// This file exists because the encoding was got wrong once, in a way that was easy to miss:
///
/// * `P` was read as **reverse** drawing order. It is not — the first pair is where the stroke
///   starts.
/// * `y` was read as growing **downwards**. It grows **upwards** (mathematical convention).
///
/// The two mistakes cancel out for a purely vertical stroke, so `拷贝` ↑ and `粘贴` ↓ appeared
/// to work while every horizontal and multi-segment gesture was silently rotated or mirrored.
/// What catches it:
///
/// * `Back` is bound to ⌘[ and must therefore be a **left** stroke.
/// * The app's own quick-start cards: `拷贝` draws its start circle at the *bottom* of an
///   upward arrow, `关闭标签页` is down-then-right, `退出` is down-then-left.
private func stroke(_ points: [Int], isSimple: Bool = true) -> WGStrokeStep {
    WGStrokeStep(isSimple: isSimple, points: points)
}

@Suite("轨迹编码：方向语义")
struct StrokeDirectionTests {
    @Test("单段手势：方向必须与它绑定的命令语义一致")
    func singleSegmentDirections() {
        // ⌘[ 是后退，画出来必须是向左
        #expect(stroke([50, 0, 0, 0]).directionDescription == "左") // Back
        // ⌘] 是前进，必须是向右
        #expect(stroke([-50, 0, 0, 0]).directionDescription == "右") // Forward
        // ⌘Z 撤销
        #expect(stroke([50, 0, 0, 0]).directionDescription == "左") // Undo
    }

    @Test("拷贝向上、粘贴向下，且起点分别是下方与上方")
    func copyAndPasteOrientation() {
        let copy = stroke([0, -50, 0, 0])
        #expect(copy.directionDescription == "上")
        // 快捷入门图里「拷贝」的圆圈（轨迹起点）画在箭头下方
        let copyPath = copy.drawingOrderPoints
        #expect(copyPath.first!.y > copyPath.last!.y, "拷贝应当从下往上画")

        let paste = stroke([0, 50, 0, 0])
        #expect(paste.directionDescription == "下")
        let pastePath = paste.drawingOrderPoints
        #expect(pastePath.first!.y < pastePath.last!.y, "粘贴应当从上往下画")
    }

    @Test("折线手势：与快捷入门图逐一对照")
    func multiSegmentDirections() {
        // 「关闭标签页」卡片：圆圈在左上，先下后右
        #expect(stroke([-50, 50, -50, 0, 0, 0]).directionDescription == "下→右")
        // 「关闭窗口」是同一条轨迹加一个 ◑ 修饰键
        #expect(stroke([-50, 50, -50, 0, 0, 0]).directionDescription == "下→右")
        // 「退出」卡片：圆圈在右上，先下后左
        #expect(stroke([50, 50, 50, 0, 0, 0]).directionDescription == "下→左")
    }

    @Test("配置里其余折线手势的方向")
    func otherMultiSegmentDirections() {
        #expect(stroke([-50, 50, 0, 50, 0, 0]).directionDescription == "右→下") // New / Reopen Tab
        #expect(stroke([50, 50, 0, 50, 0, 0]).directionDescription == "左→下") // End
        #expect(stroke([50, -50, 0, -50, 0, 0]).directionDescription == "左→上") // Home
        #expect(stroke([-50, -50, 0, -50, 0, 0]).directionDescription == "右→上") // Location Bar
        #expect(stroke([50, -50, 50, 0, 0, 0]).directionDescription == "上→左") // Previous Tab
        #expect(stroke([-50, -50, -50, 0, 0, 0]).directionDescription == "上→右") // Next Tab
        #expect(stroke([0, -50, -50, -50, -50, 0, 0, 0]).directionDescription == "左→上→右") // Reload
    }

    @Test("闭环手势")
    func closedShapes() {
        #expect(stroke([0, 0, 0, 50, 0, 0]).directionDescription == "上→下（闭环）") // Web Search
        #expect(stroke([0, 0, -50, 0, 0, 0]).directionDescription == "左→右（闭环）") // Backspace
        #expect(stroke([0, 0, 50, 0, 0, 0]).directionDescription == "右→左（闭环）") // Delete
    }

    @Test("任意形状的点列是原始屏幕坐标，既不倒序也不翻转 y")
    func arbitraryShapeIsRawScreenCoordinates() {
        // 参考配置里「重新载入」的点列，y 全为正值
        let definition = stroke([969, 546, 1069, 395, 1203, 575], isSimple: false)
        #expect(definition.drawingOrderPoints == [
            CGPoint(x: 969, y: 546),
            CGPoint(x: 1069, y: 395),
            CGPoint(x: 1203, y: 575),
        ])
        // 屏幕坐标系的 y 一定是正数；如果是 y 轴向上存储的，这里就会是负数
        #expect(definition.drawingOrderPoints.allSatisfy { $0.y > 0 })
    }
}

@Suite("轨迹编码：与真实配置对照")
struct RealConfigurationDirectionTests {
    @Test(
        "真实配置里每个手势的方向都能对上手势名",
        .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil)
    )
    func namedDirectionsMatchTheConfiguration() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
        let config = try LegacyConfigImporter.load(from: directory).config

        func directions(_ name: String) -> [String] {
            config.general.intents
                .filter { $0.name == name }
                .compactMap { $0.strokeStep?.directionDescription }
        }

        // 这些都是一眼能判断对错的绑定
        #expect(directions("Copy") == ["上"])
        #expect(directions("Paste") == ["下"])
        #expect(directions("Back") == ["左"], "Back 绑定 ⌘[，必须是向左")
        #expect(directions("Forward") == ["右"], "Forward 绑定 ⌘]，必须是向右")
        #expect(directions("Close") == ["下→右"], "对应快捷入门图的「关闭标签页」卡片")
        #expect(directions("Close Window") == ["下→右"])
        #expect(directions("退出") == ["下→左"], "对应快捷入门图的「退出」卡片")
        #expect(directions("Home") == ["左→上"])
        #expect(directions("Location Bar") == ["右→上"])
        #expect(directions("End") == ["左→下"])
        #expect(directions("New") == ["右→下"])
    }
}
