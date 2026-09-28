import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

/// Screen-coordinate helpers: the recorder's input is "y grows downwards", the configuration's
/// convention is "y grows upwards", and the whole point of these tests is to pin that down.
private func stroke(from start: CGPoint, _ steps: [CGPoint]) -> [CGPoint] {
    var points = [start]
    var cursor = start
    for step in steps {
        cursor.x += step.x
        cursor.y += step.y
        points.append(cursor)
    }
    return points
}

@Suite("设置：录制手势笔画")
struct WGStrokeRecorderTests {
    @Test("向上画 → 上（屏幕 y 向下，向上就是 y 变小）")
    func encodesAnUpStroke() throws {
        let drawn = stroke(from: CGPoint(x: 100, y: 300), [CGPoint(x: 0, y: -200)])
        let encoded = try WGStrokeRecorder.encode(screenPoints: drawn)
        #expect(encoded.directionDescription == "上")
        // 简单手势：50 网格上两点，且 y 取反（配置 y 向上）。
        #expect(encoded.isSimple)
        #expect(encoded.points == [0, 0, 0, 50])
    }

    @Test("向下画 → 下")
    func encodesADownStroke() throws {
        let drawn = stroke(from: CGPoint(x: 100, y: 100), [CGPoint(x: 0, y: 200)])
        let encoded = try WGStrokeRecorder.encode(screenPoints: drawn)
        #expect(encoded.directionDescription == "下")
        #expect(encoded.isSimple)
        #expect(encoded.points == [0, 0, 0, -50])
    }

    @Test("向右画 → 右；向左画 → 左")
    func encodesHorizontalStrokes() throws {
        let right = try WGStrokeRecorder.encode(
            screenPoints: stroke(from: CGPoint(x: 50, y: 50), [CGPoint(x: 200, y: 0)])
        )
        #expect(right.directionDescription == "右")
        #expect(right.points == [0, 0, 50, 0])

        let left = try WGStrokeRecorder.encode(
            screenPoints: stroke(from: CGPoint(x: 250, y: 50), [CGPoint(x: -200, y: 0)])
        )
        #expect(left.directionDescription == "左")
        #expect(left.points == [0, 0, -50, 0])
    }

    @Test("折线：下→右 与 右→下 都要保留顺序")
    func encodesTwoSegmentStrokes() throws {
        let downRight = try WGStrokeRecorder.encode(
            screenPoints: stroke(
                from: CGPoint(x: 100, y: 100),
                [CGPoint(x: 0, y: 150), CGPoint(x: 150, y: 0)]
            )
        )
        #expect(downRight.directionDescription == "下→右")
        #expect(downRight.isSimple)
        #expect(downRight.points == [0, 0, 0, -50, 50, -50])

        let rightDown = try WGStrokeRecorder.encode(
            screenPoints: stroke(
                from: CGPoint(x: 100, y: 100),
                [CGPoint(x: 150, y: 0), CGPoint(x: 0, y: 150)]
            )
        )
        #expect(rightDown.directionDescription == "右→下")
        #expect(rightDown.points == [0, 0, 50, 0, 50, -50])
    }

    @Test("闭环（先上再回下）也能编码，并且标出闭环")
    func encodesAClosedLoop() throws {
        let drawn = stroke(
            from: CGPoint(x: 200, y: 400),
            [CGPoint(x: 0, y: -150), CGPoint(x: 0, y: 150)]
        )
        let encoded = try WGStrokeRecorder.encode(screenPoints: drawn)
        #expect(encoded.directionDescription == "上→下（闭环）")
        #expect(encoded.isSimple)
        // 与真实配置里 Web Search（`[0,0,0,50,0,0]`）同形。
        #expect(encoded.points == [0, 0, 0, 50, 0, 0])
    }

    @Test("太短的笔画会被拒绝，并给出可读原因")
    func rejectsShortStrokes() {
        let drawn = stroke(from: CGPoint(x: 10, y: 10), [CGPoint(x: 0, y: -8)])
        #expect(throws: WGStrokeRecorder.Failure.tooShort(length: 8, minimum: 30)) {
            try WGStrokeRecorder.encode(screenPoints: drawn)
        }
        // 一个点都不算笔画。
        #expect(throws: WGStrokeRecorder.Failure.empty) {
            try WGStrokeRecorder.encode(screenPoints: [CGPoint(x: 1, y: 1)])
        }
        // 提示文字里带数字，便于用户知道差多少。
        let message = WGStrokeRecorder.Failure
            .tooShort(length: 8, minimum: 30).errorDescription ?? ""
        #expect(message.contains("8") && message.contains("30"))
    }

    @Test("手抖的直线仍然编码成简单手势")
    func noisyStraightLineStaysSimple() throws {
        // 一条向上、带 ±2 点抖动的 12 点直线。
        var points: [CGPoint] = []
        for index in 0..<12 {
            let jitter: CGFloat = index % 2 == 0 ? 2 : -2
            points.append(CGPoint(x: 200 + jitter, y: 400 - CGFloat(index) * 20))
        }
        let encoded = try WGStrokeRecorder.encode(screenPoints: points)
        #expect(encoded.isSimple)
        #expect(encoded.points == [0, 0, 0, 50])
    }

    @Test("真正的曲线不会被硬掰成直角")
    func curvedStrokesStayFreehand() throws {
        // 向右的大弧度曲线：任何直角近似都会差得远。
        var points: [CGPoint] = []
        for index in 0...30 {
            let t = CGFloat(index) / 30
            points.append(CGPoint(x: 100 + 300 * t, y: 300 - 220 * sin(t * .pi)))
        }
        let encoded = try WGStrokeRecorder.encode(screenPoints: points)
        #expect(!encoded.isSimple, "曲线必须原样保留，不能被掰成简单手势")
        #expect(encoded.points.count >= 6)
        #expect(encoded.points.count % 2 == 0)
        // 起点被移到原点，配置侧 y 取反。
        #expect(encoded.points[0] == 0 && encoded.points[1] == 0)
    }

    @Test("任意形状也不会存成上千个点")
    func decimatesFreehandStrokes() throws {
        var points: [CGPoint] = []
        for index in 0...400 {
            let t = CGFloat(index) / 400
            points.append(CGPoint(x: 100 + 250 * t, y: 300 - 180 * sin(t * .pi * 1.5)))
        }
        let encoded = try WGStrokeRecorder.encode(screenPoints: points)
        let storedPoints = encoded.points.count / 2
        #expect(storedPoints <= WGStrokeRecorder.maximumFreehandPoints)
        #expect(storedPoints >= 2)
    }

    /// 最重要的一条：录一个向上笔画，必须与原版配置里真实的「Copy」定义几乎重合。
    /// 这一条直接钉住 y 轴方向与绘制顺序 —— 历史上这两点各错过一次。
    @Test("录出来的向上笔画 ≈ 真实配置里的「拷贝」", .enabled(if: LegacyConfigImporter.locateVersionDirectory() != nil))
    func recordedUpStrokeMatchesTheRealCopyGesture() throws {
        let directory = try #require(LegacyConfigImporter.locateVersionDirectory())
        let config = try LegacyConfigImporter.load(from: directory).config
        let copy = try #require(config.general.intents.first { $0.name == "Copy" })
        let copyStroke = try #require(copy.strokeStep)
        #expect(copyStroke.directionDescription == "上", "真实配置里的 Copy 必须是向上")

        // 用户在画布上向上画（屏幕坐标 y 变小）。
        let drawn = stroke(from: CGPoint(x: 500, y: 600), [CGPoint(x: 0, y: -250)])
        let recorded = try WGStrokeRecorder.encode(screenPoints: drawn)

        let mine = StrokeNormalizer.normalize(recorded.drawingOrderPoints, sampleCount: 32)
        let theirs = StrokeNormalizer.normalize(copyStroke.drawingOrderPoints, sampleCount: 32)
        let distance = StrokeMatcher.distance(mine, theirs)
        #expect(
            distance <= RecognitionSettings().matchThreshold,
            "录出来的向上笔画必须能匹配真实 Copy 定义，实际距离 \(distance)"
        )
    }

    @Test("录制预览与实际编码一致")
    func previewAgreesWithEncoding() throws {
        let drawn = stroke(
            from: CGPoint(x: 300, y: 300),
            [CGPoint(x: 0, y: 200), CGPoint(x: 200, y: 0)]
        )
        let encoded = try WGStrokeRecorder.encode(screenPoints: drawn)
        #expect(WGStrokeRecorder.directionPreview(screenPoints: drawn) == encoded.directionDescription)
        #expect(WGStrokeRecorder.directionPreview(screenPoints: drawn) == "下→右")
        #expect(WGStrokeRecorder.directionPreview(screenPoints: []) == "（还没画）")
    }

    @Test("编码结果能按原格式写盘并读回")
    func encodedStrokeRoundTripsThroughTheCodec() throws {
        let drawn = stroke(from: CGPoint(x: 40, y: 40), [CGPoint(x: 180, y: 0)])
        let encoded = try WGStrokeRecorder.encode(screenPoints: drawn)
        let intent = WGIntent(
            name: "录制的",
            gesture: [.keyDown(WGKeyDownStep(key: "MOUSE:1")), .stroke(encoded)],
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
        )
        let config = WGConfig(general: WGTarget(kind: .general, name: "General", intents: [intent]))
        let reloaded = try WGConfigCodec.decode(try WGConfigCodec.encode(config)).config
        #expect(reloaded.general.intents[0].strokeStep == encoded)
        #expect(reloaded.general.intents[0].strokeStep?.directionDescription == "右")
    }
}
