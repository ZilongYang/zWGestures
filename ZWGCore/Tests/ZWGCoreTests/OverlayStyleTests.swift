import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

@Suite("配色：解析")
struct WGColorTests {
    @Test("八位十六进制按 #RRGGBBAA 解析")
    func parsesEightDigitsAsRGBA() throws {
        let color = try #require(WGColor(hex: "#7F7F7FC4"))
        #expect(abs(color.red - 0x7F / 255) < 0.001)
        #expect(abs(color.green - 0x7F / 255) < 0.001)
        #expect(abs(color.blue - 0x7F / 255) < 0.001)
        #expect(abs(color.alpha - 0xC4 / 255) < 0.001)
    }

    @Test("识别色应当是青绿色，而不是浅紫")
    func recognisedColourIsTeal() throws {
        // 若按 AARRGGBB 解析，这里会得到 RGB = D697E6（浅紫），与「已识别」的直觉不符
        let color = try #require(WGColor(hex: "#20D697E6"))
        #expect(abs(color.red - 0x20 / 255) < 0.001)
        #expect(abs(color.green - 0xD6 / 255) < 0.001)
        #expect(abs(color.blue - 0x97 / 255) < 0.001)
        #expect(abs(color.alpha - 0xE6 / 255) < 0.001)
        #expect(color.green > color.red, "青绿色的绿分量应当最高")
        #expect(color.green > color.blue)
    }

    @Test("六位十六进制视为不透明")
    func parsesSixDigits() throws {
        let color = try #require(WGColor(hex: "FF8000"))
        #expect(abs(color.red - 1) < 0.001)
        #expect(abs(color.alpha - 1) < 0.001)
    }

    @Test("非法输入返回 nil，不抛异常")
    func rejectsGarbage() {
        #expect(WGColor(hex: "") == nil)
        #expect(WGColor(hex: "#12345") == nil)
        #expect(WGColor(hex: "zzzzzz") == nil)
        #expect(WGColor(hex: "#GGGGGGGG") == nil)
    }
}

@Suite("配色：偏好映射")
struct OverlayStyleTests {
    @Test("两个「常态」颜色在前六位都是纯灰 —— 这就是判定 #RRGGBBAA 的依据")
    func normalColoursArePureGreys() throws {
        let path = try #require(WGColor(hex: "#7F7F7FC4"))
        let label = try #require(WGColor(hex: "#60606080"))
        #expect(path.red == path.green && path.green == path.blue)
        #expect(label.red == label.green && label.green == label.blue)
        // 两者都是半透明，而不是全不透明
        #expect(path.alpha < 1)
        #expect(label.alpha < 1)
    }

    @Test("标签位置按屏幕高度比例换算")
    func labelPositionIsProportional() {
        let style = OverlayStyle(gesturePosition: 0.25)
        #expect(style.labelCenterY(screenHeight: 1000) == 250)
        #expect(OverlayStyle(gesturePosition: 2).labelCenterY(screenHeight: 1000) == 1000)
        #expect(OverlayStyle(gesturePosition: -1).labelCenterY(screenHeight: 1000) == 0)
    }

    @Test("识别出来就立刻用识别色 —— 绘制途中也要变绿，而不是等松手")
    func recognizedColourAppliesWhileDrawing() {
        let style = OverlayStyle()
        #expect(style.pathColor(recognized: false) == style.pathColorNormal)
        #expect(style.pathColor(recognized: true) == style.pathColorRecognized)
        #expect(style.labelColor(recognized: true) == style.labelColorExecuted)

        // 绘制中且已识别：轨迹与名称都必须是识别色
        let drawing = OverlayState(
            phase: .drawing,
            points: [.zero, CGPoint(x: 10, y: 10)],
            gestureName: "Close",
            isRecognized: true
        )
        #expect(drawing.phase == .drawing)
        #expect(drawing.isRecognized)
        #expect(style.pathColor(recognized: drawing.isRecognized) == style.pathColorRecognized)

        // 绘制中但还没识别出来：常态色，且不该有名字
        let pending = OverlayState(phase: .drawing, points: [.zero], gestureName: nil, isRecognized: false)
        #expect(pending.gestureName == nil)
        #expect(style.pathColor(recognized: pending.isRecognized) == style.pathColorNormal)
    }

    @Test(
        "真实偏好能完整映射成 Overlay 样式",
        .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil)
    )
    func mapsRealPreferences() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
        let preferences = try #require(LegacyConfigImporter.load(from: directory).preferences)
        let style = OverlayStyle(preferences: preferences)

        #expect(style.showPath == preferences.showPath)
        #expect(style.showGestureName == preferences.showGestureName)
        #expect(style.lineWidth == preferences.pathLineWidth)
        #expect(style.gesturePosition == preferences.gesturePos)

        // 四个颜色都必须解析成功（解析失败会回落到默认值，正好能被这个断言抓到）
        #expect(style.pathColorNormal == WGColor(hex: preferences.pathColorNormal))
        #expect(style.pathColorRecognized == WGColor(hex: preferences.pathColorRecognized))
        #expect(style.labelColorNormal == WGColor(hex: preferences.labelColorNormal))
        #expect(style.labelColorExecuted == WGColor(hex: preferences.labelColorExecuted))
    }
}
