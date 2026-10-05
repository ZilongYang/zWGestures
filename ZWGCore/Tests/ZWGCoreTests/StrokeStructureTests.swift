import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

/// The structure descriptor is what makes recognition depend on the *shape* of a gesture instead of
/// on how long each of its arms happens to be drawn.
///
/// The user's report that started this (2026-10-06): a「下→右」drawn with a vertical 2.2× the
/// horizontal — obviously the「关闭」shape — was not recognised, because the old arc-length metric
/// scored it 0.109 against its own definition (threshold 0.10). Drawn with a horizontal 2× the
/// vertical, the *same* two-segment stroke instead matched the three-segment `Enter`, because a
/// dominating segment drowns out the direction information of the short ones.
@Suite("识别：形状结构描述子")
struct StrokeStructureTests {
    private func structure(_ points: [CGPoint]) -> StrokeStructure {
        guard let value = StrokeStructure.make(from: points) else {
            Issue.record("点列 \(points) 应当能算出结构")
            return StrokeStructure(segments: [], pathLength: 0)
        }
        return value
    }

    private func lShape(vertical: CGFloat, horizontal: CGFloat, from origin: CGPoint = .zero) -> [CGPoint] {
        [
            origin,
            CGPoint(x: origin.x, y: origin.y + vertical),
            CGPoint(x: origin.x + horizontal, y: origin.y + vertical),
        ]
    }

    /// Samples a polyline every `step` points, the way the engine records a real stroke.
    private func densified(_ points: [CGPoint], step: CGFloat = 3) -> [CGPoint] {
        var result: [CGPoint] = [points[0]]
        for (from, to) in zip(points, points.dropFirst()) {
            let length = distance(from, to)
            let count = max(1, Int(length / step))
            for index in 1...count {
                let t = CGFloat(index) / CGFloat(count)
                result.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            }
        }
        return result
    }

    @Test("直线是一段，拐角是两段，圆是很多段")
    func segmentCountFollowsTheShape() {
        let line = structure(densified([.zero, CGPoint(x: 0, y: 400)]))
        #expect(line.segments.count == 1, "一条直线应当简化成一段")
        #expect(abs(abs(line.segments[0].direction.dy) - 1) < 0.05, "方向应当朝下")

        let corner = structure(densified(lShape(vertical: 400, horizontal: 180)))
        #expect(corner.segments.count == 2, "一个拐角应当简化成两段，实测 \(corner.segments.count)")
        #expect(abs(corner.segments[0].lengthFraction
            - 400 / 580) < 0.05)

        let circle = structure(densified((0...64).map { index -> CGPoint in
            let angle = CGFloat(index) / 64 * 2 * .pi
            return CGPoint(x: 600 + cos(angle) * 120, y: 600 + sin(angle) * 120)
        }, step: 12))
        #expect(circle.segments.count >= 4, "圆不应该被简化成两条线段，实测 \(circle.segments.count)")
    }

    @Test("手抖与圆角不会制造出多余的拐角")
    func tremorAndRoundedCornersStayOneCorner() {
        // 直线上的抖动：交替偏移 ±3 点。
        let wobbly = densified([.zero, CGPoint(x: 0, y: 300)]).enumerated().map { index, point in
            CGPoint(x: point.x + (index % 2 == 0 ? 3 : -3), y: point.y)
        }
        #expect(structure(wobbly).segments.count == 1, "抖动 3 点的直线仍应是一段")

        // 圆角：拐角处插入一段 1/4 圆弧。
        var rounded: [CGPoint] = [.zero]
        for step in 0...8 {
            let angle = CGFloat(step) / 8 * .pi / 2
            rounded.append(CGPoint(x: 0 + 30 - 30 * cos(angle), y: 300 - 30 + 30 * sin(angle)))
        }
        rounded.append(CGPoint(x: 200, y: 300))
        #expect(structure(densified(rounded)).segments.count == 2, "半径 30 的圆角应当仍是一个拐角")
    }

    @Test("长度比例不同的同一形状，距离很小")
    func proportionsDoNotDominateTheDistance() {
        let stored = structure(densified(lShape(vertical: 200, horizontal: 200)))
        for ratio in [0.4, 0.6, 1.0, 1.5, 2.2, 3.0, 4.0] as [CGFloat] {
            let drawn = structure(densified(lShape(vertical: 200, horizontal: 200 / ratio)))
            let value = StrokeStructure.distance(drawn, stored)
            #expect(value < RecognitionSettings().structureThreshold, "竖横比 \(ratio) 时距离 \(value)")

            // 与「一条向下的直线」必须仍然分得开：这正是旧度量做不到的（2.2:1 时只要 0.075）。
            let line = structure(densified([CGPoint(x: 0, y: -20), CGPoint(x: 0, y: 200)]))
            #expect(StrokeStructure.distance(drawn, line) > 0.3, "L 形不该靠近一条直线（比值 \(ratio)）")
        }
    }

    @Test("段数不同就是不同的形状：两段的 L 不能当成三段的 Enter")
    func differentCornerCountsStayApart() {
        let l = structure(densified(lShape(vertical: 200, horizontal: 200)))
        let enter = structure(densified([
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 200),
            CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 400),
        ]))
        #expect(StrokeStructure.distance(l, enter) > RecognitionSettings().structureThreshold * 2)

        // 方向相反的两条：方向代价必须拉满（第一段 180° → 1.0，除以 2 段后仍有 0.375）。
        let mirrored = structure(densified([
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: -200), CGPoint(x: 200, y: -200),
        ]))
        #expect(StrokeStructure.distance(mirrored, l) > RecognitionSettings().structureThreshold * 2,
                "上下镜像必须远大于阈值")
    }

    @Test("存储侧是「原路返回」时就归到弧长度量")
    func retracingStoredShapesUseTheArcMetric() {
        // 参考配置里的真实写法：上 50 再回原点。
        let webSearch: [CGPoint] = [.zero, CGPoint(x: 0, y: -50), .zero, .zero]
        let backspace: [CGPoint] = [.zero, CGPoint(x: -50, y: 0), .zero, .zero]
        #expect(StrokeMatching.metric(forStoredPoints: webSearch) == .arcLength)
        #expect(StrokeMatching.metric(forStoredPoints: backspace) == .arcLength)

        // 折线类（含任意形状的手写轨迹）走结构度量。
        let close: [CGPoint] = [CGPoint(x: 0, y: -50), .zero, CGPoint(x: 50, y: 0)]
        #expect(StrokeMatching.metric(forStoredPoints: close) == .structure)
        let reload: [CGPoint] = [
            CGPoint(x: 969, y: -546),
            CGPoint(x: 1069, y: -395),
            CGPoint(x: 1203, y: -575),
        ]
        #expect(StrokeMatching.metric(forStoredPoints: reload) == .structure)
    }
}
