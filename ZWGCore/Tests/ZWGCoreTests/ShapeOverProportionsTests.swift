import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

/// The user's report of 2026-10-06, turned into tests.
///
/// Two symptoms, one cause: the matcher compared arc-length-parameterised point sets, so a stroke's
/// *proportions* were part of its "shape".
///
/// 1. 「关闭」is `下→右`. Drawn with a vertical 2.2× the horizontal (the screenshot) it scored
///    0.109 against its own definition and was **not recognised**; drawn with a longer horizontal
///    it instead matched the three-segment `Enter`, because one dominating segment drowned out the
///    direction information of the short ones.
/// 2. A three-segment `Enter` drawn with a long middle segment scored 0.120 and was missed
///    altogether.
@Suite("识别：先看形状，再看笔画长度")
struct ShapeOverProportionsTests {
    // MARK: - Fixtures

    private func referenceConfig() throws -> WGConfig {
        let url = FixtureConfig.directory.appendingPathComponent("gestures.json")
        return try WGConfigCodec.decode(try Data(contentsOf: url)).config
    }

    private func generalTarget() throws -> WGTarget {
        try referenceConfig().general
    }

    /// A stroke made of the given corners, sampled every few points — what a real drag produces.
    private func stroke(_ corners: [CGPoint], step: CGFloat = 3) -> Stroke {
        var points: [CGPoint] = [corners[0]]
        for (from, to) in zip(corners, corners.dropFirst()) {
            let length = distance(from, to)
            let count = max(1, Int(length / step))
            for index in 1...count {
                let t = CGFloat(index) / CGFloat(count)
                points.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            }
        }
        var stroke = Stroke(start: points[0], timestamp: 0)
        for point in points.dropFirst() {
            stroke.append(point, timestamp: 0.01, minDistance: 0, minInterval: 0)
        }
        return stroke
    }

    /// A「下→右」with the given arm lengths, drawn at a plausible place on screen.
    private func lShape(vertical: CGFloat, horizontal: CGFloat) -> Stroke {
        stroke([
            CGPoint(x: 800, y: 300),
            CGPoint(x: 800, y: 300 + vertical),
            CGPoint(x: 800 + horizontal, y: 300 + vertical),
        ])
    }

    private func recognize(
        _ stroke: Stroke,
        button: MouseButton = .right,
        in target: WGTarget
    ) throws -> (match: RecognitionMatch?, passing: [RecognitionMatch]) {
        let index = GestureIndex(target: target)
        let recognizer = GestureRecognizer(settings: index.settings)
        return score(stroke, button: button, in: index, recognizer: recognizer)
    }

    private func score(
        _ stroke: Stroke,
        button: MouseButton,
        in index: GestureIndex,
        recognizer: GestureRecognizer
    ) -> (match: RecognitionMatch?, passing: [RecognitionMatch]) {
        let scored = recognizer.scoredCandidates(
            stroke: stroke, button: button, modifiers: [], in: index
        )
        let passing = scored.filter { $0.distance <= index.settings.threshold(for: $0.metric) }
        return (recognizer.recognize(stroke: stroke, button: button, modifiers: [], in: index), passing)
    }

    private func winner(_ result: (match: RecognitionMatch?, passing: [RecognitionMatch])) -> String? {
        result.match?.name
    }

    // MARK: - 1. 截图那条 L

    @Test("截图那条 L（竖 467 / 横 210）命中「关闭」")
    func screenshotStrokeMatchesClose() throws {
        let result = try recognize(lShape(vertical: 467, horizontal: 210), in: try generalTarget())
        #expect(
            winner(result) == "Close",
            "应当命中「关闭」，实际 \(winner(result) ?? "未识别")，通过阈值的是 \(result.passing.map(\.name))"
        )
        let close = try #require(result.passing.first { $0.name == "Close" })
        #expect(close.distance < RecognitionSettings().structureThreshold / 2, "不应当是勉强压线命中")
    }

    @Test("竖横比从 0.4 到 4.0 都命中「关闭」，而且不再滑向 Enter / Minimize / Paste")
    func anyArmRatioStillMatchesClose() throws {
        let target = try generalTarget()
        let forbidden = ["Enter", "Minimize", "Fullscreen", "Paste", "Paste & Enter", "Web Search"]
        for ratio in [0.4, 0.5, 0.7, 1.0, 1.5, 2.2, 3.0, 4.0] as [CGFloat] {
            let result = try recognize(lShape(vertical: 200, horizontal: 200 / ratio), in: target)
            #expect(
                winner(result) == "Close",
                "竖横比 \(ratio) 时命中的是 \(winner(result) ?? "未识别")"
            )
            let wrong = result.passing.map(\.name).filter { forbidden.contains($0) }
            #expect(wrong.isEmpty, "竖横比 \(ratio) 时被判给了 \(wrong) —— 两段的 L 不该像任何三段手势")
        }
    }

    // MARK: - 2. 三段的 Enter

    @Test("三段的「下→右→下」：中间那段 0.4×~3× 都命中 Enter，不会滑到 Minimize")
    func enterSurvivesALongMiddleSegment() throws {
        let target = try generalTarget()
        for horizontal in [40, 60, 100, 150, 200, 300] as [CGFloat] {
            let shape = stroke([
                CGPoint(x: 700, y: 300),
                CGPoint(x: 700, y: 400),
                CGPoint(x: 700 + horizontal, y: 400),
                CGPoint(x: 700 + horizontal, y: 500),
            ])
            let result = try recognize(shape, in: target)
            #expect(
                winner(result) == "Enter",
                "中间横长 \(horizontal) 时命中的是 \(winner(result) ?? "未识别")，通过阈值的是 \(result.passing.map(\.name))"
            )
            #expect(!result.passing.contains { $0.name == "Minimize" }, "「下→右→下」不该命中 Minimize")
        }
    }

    @Test("「下→右→上」是 Minimize、「上→右→下」是 Fullscreen，方向不能被长度带跑")
    func threeSegmentDirectionStillDecides() throws {
        let target = try generalTarget()
        for horizontal in [60, 140, 260] as [CGFloat] {
            // 参考配置里 Minimize = 下→右→上，Fullscreen = 上→右→下。
            let minimize = stroke([
                CGPoint(x: 700, y: 300),
                CGPoint(x: 700, y: 400),
                CGPoint(x: 700 + horizontal, y: 400),
                CGPoint(x: 700 + horizontal, y: 300),
            ])
            let fullscreen = stroke([
                CGPoint(x: 700, y: 300),
                CGPoint(x: 700, y: 200),
                CGPoint(x: 700 + horizontal, y: 200),
                CGPoint(x: 700 + horizontal, y: 300),
            ])
            #expect(winner(try recognize(minimize, in: target)) == "Minimize")
            #expect(winner(try recognize(fullscreen, in: target)) == "Fullscreen")
        }
    }

    // MARK: - 3. 手绘失真回归

    /// Deterministic RNG: a recognition test whose outcome depends on `SystemRandomNumberGenerator`
    /// is a flaky test, and a flaky test gets deleted instead of fixed.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed | 1 }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    /// Mimics a hand: every arm drawn at a slightly different length, the whole shape a little
    /// rotated, and a touch of tremor on top.
    ///
    /// The envelope is deliberately wider than a careful drawing — 2× between the longest and the
    /// shortest arm — because that is the user's complaint: a「下→右」is obviously「关闭」even when
    /// the vertical is drawn twice as long as the horizontal. (Against a *harsher* replica envelope
    /// — arms 0.35–2.5×, ±12°, 2.5 px — a Python recomputation measured the old arc-length metric
    /// at 21% correct and the structure metric at 86%.)
    private func handDrawn(
        _ corners: [CGPoint],
        using generator: inout SeededGenerator,
        segmentScale: ClosedRange<CGFloat> = 0.5...2.0,
        tiltDegrees: CGFloat = 8,
        tremor: CGFloat = 2
    ) -> Stroke {
        var scaled: [CGPoint] = [corners[0]]
        for (from, to) in zip(corners, corners.dropFirst()) {
            let length = distance(from, to)
            guard length > 0 else { continue }
            let angle = atan2(to.y - from.y, to.x - from.x)
                + CGFloat.random(in: -tiltDegrees...tiltDegrees, using: &generator) * .pi / 180
            let scaledLength = length * CGFloat.random(in: segmentScale, using: &generator)
            let previous = scaled[scaled.count - 1]
            scaled.append(CGPoint(
                x: previous.x + cos(angle) * scaledLength,
                y: previous.y + sin(angle) * scaledLength
            ))
        }
        let jittered = scaled.map { point in
            CGPoint(
                x: point.x + CGFloat.random(in: -tremor...tremor, using: &generator),
                y: point.y + CGFloat.random(in: -tremor...tremor, using: &generator)
            )
        }
        return stroke(jittered)
    }

    /// Gestures whose stored shape is byte-identical can never be told apart — the engine resolves
    /// them by list order (and gesture modifiers). A drawing of one may legitimately be reported as
    /// another.
    private func duplicateGroup(of intent: WGIntent, in target: WGTarget) -> Set<String> {
        let points = intent.strokeStep?.points ?? []
        return Set(target.intents.filter { $0.strokeStep?.points == points }.map(\.name))
    }

    @Test("真实手绘失真下，参考配置里每条折线手势都仍然过得了阈值")
    func handDrawnDistortionsStillMatch() throws {
        let target = try generalTarget()
        let index = GestureIndex(target: target)
        let recognizer = GestureRecognizer(settings: index.settings)
        var generator = SeededGenerator(seed: 0x5EED_2026)

        var checked = 0
        var failures: [String] = []
        var details: [String] = []
        var stolen: [String] = []

        // 直接遍历识别索引里的候选：它已经替我们筛掉了「本版本触发不了」（边角/滚轮触发）与
        // 「被禁用」的手势，也带着每条手势真正的触发键与手势修饰键要求 —— 照着 target.intents
        // 自己写一遍筛选，测的就不是引擎的实际行为了。
        for prepared in index.gestures {
            // 闭环手势（画出去再原路返回）用的是刻意保留的弧长容差，单独在下面测 —— 它们本来就
            // 是按「画成细长环」调过的。
            guard prepared.metric == .structure else { continue }
            // 需要手势修饰键的（例如「剪切」要靠画线时按住左键）这一轮不模拟：声明了就必须真实发生，
            // 否则识别器会（正确地）拒绝它。
            guard prepared.modifierRequirements.isEmpty else { continue }
            let intent = prepared.intent
            let button = prepared.triggerButton
            guard let definition = intent.strokeStep else { continue }
            // 存储定义是 50 一格的（坐标系单位），而人真正画的时候是屏幕上的几百点。把它缩到
            // 一个真实手势的尺度再失真，否则 2 点的抖动会变成 4% 的噪声、8 点的简化下限也会变成
            // 手臂长度的 16% —— 那测的就不是识别器，而是坐标系单位。
            let stored = definition.drawingOrderPoints
            let storedLength = StrokeNormalizer.pathLength(stored)
            guard stored.count >= 2, storedLength >= 30 else { continue }
            let scale = 400 / storedLength
            let corners = stored.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
            let group = duplicateGroup(of: intent, in: target)

            for _ in 0..<8 {
                let drawn = handDrawn(corners, using: &generator)
                let result = score(drawn, button: button, in: index, recognizer: recognizer)
                let scored = recognizer.scoredCandidates(
                    stroke: drawn, button: button, modifiers: [], in: index
                )
                let passing = result.passing
                checked += 1
                guard passing.contains(where: { $0.name == intent.name }) else {
                    failures.append("「\(intent.name)」")
                    if details.count < 6, let own = scored.first(where: { $0.name == intent.name }) {
                        let live = StrokeStructure.make(from: drawn.points, settings: index.settings.structure)
                        let fractions = live?.segments.map { String(format: "%.2f", $0.lengthFraction) } ?? []
                        details.append("\(intent.name) 自己=\(String(format: "%.3f", own.distance))"
                            + " 段数=\(live?.segments.count ?? -1) 占比=\(fractions)")
                    }
                    continue
                }
                if let best = result.match, !group.contains(best.name) {
                    stolen.append("「\(intent.name)」被「\(best.name)」抢走")
                }
            }
        }

        #expect(checked > 100, "样本太少（\(checked)），说明夹具没被读到")
        if !failures.isEmpty {
            print("### 失真后过不了自己阈值的手势：\(Set(failures).sorted().joined(separator: "、"))")
        }
        #expect(
            failures.isEmpty,
            "这些手势在失真后连自己的阈值都过不了：\(Set(failures).sorted())  详情：\(details.joined(separator: " | "))"
        )
        // 形状本来就几乎一样的自由形状手势（重新载入 / 下一应用 / 上一个应用）互相抢是既存事实，
        // 这里只保证「自己的阈值过得了」，所以这一条允许它们出现，但不允许别的手势被抢。
        let unexpected = stolen.filter { !$0.contains("下一应用") && !$0.contains("上一个应用") }
        #expect(unexpected.isEmpty, "失真后形状被别的折线手势抢走了：\(unexpected)")
    }

    @Test("闭环手势（Web 搜索 / 退格 / 删除）仍然按弧长容差工作")
    func loopGesturesKeepTheirCalibratedTolerance() throws {
        let target = try generalTarget()
        // 细长环：从下往上画出去再原路返回（与配置里「Web 搜索」的笔顺一致），宽度 6。
        let loop = stroke([
            CGPoint(x: 700, y: 500),
            CGPoint(x: 703, y: 400),
            CGPoint(x: 706, y: 300),
            CGPoint(x: 703, y: 400),
            CGPoint(x: 700, y: 500),
        ])
        let result = try recognize(loop, in: target)
        #expect(winner(result) == "Web Search", "细长上环应当命中 Web 搜索，实际 \(winner(result) ?? "未识别")")
    }
}
