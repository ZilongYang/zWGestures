import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

/// Guards the recognition hot path, which runs **on the event-tap thread**.
///
/// The tap callback is synchronous: the system waits for it before delivering the next event, and if
/// it misses the deadline often enough the tap is disabled — that is the mechanism behind the
/// machine-wide input freeze recorded in docs/ROADMAP.md §13. Recognition runs there for every preview
/// tick (~20 Hz while a gesture is being drawn) and again when the stroke completes, so its cost is a
/// safety property, not a nicety.
///
/// The measurements are taken against a `GestureIndex` — the form the tap thread actually uses. The
/// target-based convenience methods rebuild the index on every call, which is fine for tests and
/// diagnostics but exactly what must never happen on the tap thread; `indexPathBeatsRebuilding`
/// pins that distinction down.
///
/// Bounds are loose enough not to flap on a busy machine, but tight enough to catch a return to the
/// per-candidate work this suite was written for (which measured ~1.5 ms per call).
@Suite("识别热路径的性能守卫（跑在拦截器线程上）")
struct RecognitionPerformanceTests {
    /// A hand-drawn-looking arc: a few hundred screen points long.
    private func makeStroke(pointCount: Int = 200) -> Stroke {
        var stroke = Stroke(start: .zero, timestamp: 0)
        for index in 1..<pointCount {
            let t = CGFloat(index) / CGFloat(pointCount - 1)
            let point = CGPoint(x: 400 * t, y: 120 * sin(t * .pi))
            stroke.append(point, timestamp: Double(index) * 0.004, minDistance: 0, minInterval: 0)
        }
        return stroke
    }

    private func referenceConfig() throws -> WGConfig {
        let url = FixtureConfig.directory.appendingPathComponent("gestures.json")
        return try WGConfigCodec.decode(try Data(contentsOf: url)).config
    }

    private func referenceIndex() throws -> GestureIndex {
        GestureIndex(target: try referenceConfig().general)
    }

    /// Runs `body` `iterations` times and returns microseconds per call.
    private func microsecondsPerCall(iterations: Int = 200, _ body: () -> Void) -> Double {
        for _ in 0..<10 { body() }  // 预热
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { body() }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        return Double(elapsed) / Double(iterations) / 1000
    }

    @Test("一次候选评分要远低于回调预算")
    func scoringStaysCheap() throws {
        let index = try referenceIndex()
        let recognizer = GestureRecognizer(settings: index.settings)
        let stroke = makeStroke()

        let perCall = microsecondsPerCall {
            _ = recognizer.scoredCandidates(
                stroke: stroke, button: .right, modifiers: [], in: index
            )
        }
        print("  scoredCandidates: \(String(format: "%.0f", perCall)) µs/次"
              + "（\(index.gestures.count) 个手势 × \(stroke.points.count) 点）")

        #expect(perCall < 800, "单次候选评分超过 0.8 ms —— 拦截器回调的预算是毫秒级")
    }

    @Test("「没匹配上」的完整路径只遍历一次")
    func missPathIsSinglePass() throws {
        let index = try referenceIndex()
        let recognizer = GestureRecognizer(settings: index.settings)
        let stroke = makeStroke()

        let perCall = microsecondsPerCall {
            _ = recognizer.recognizeWithNearest(
                stroke: stroke, button: .right, modifiers: [], in: index
            )
        }
        print("  recognizeWithNearest: \(String(format: "%.0f", perCall)) µs/次")

        #expect(perCall < 1200, "未命中的完整路径超过 1.2 ms")
    }

    @Test("索引路径必须明显快于「每次重建索引」的便捷路径")
    func indexPathBeatsRebuilding() throws {
        let config = try referenceConfig()
        let index = GestureIndex(target: config.general)
        let recognizer = GestureRecognizer(settings: index.settings)
        let stroke = makeStroke()

        let viaIndex = microsecondsPerCall(iterations: 100) {
            _ = recognizer.scoredCandidates(stroke: stroke, button: .right, modifiers: [], in: index)
        }
        let viaTarget = microsecondsPerCall(iterations: 100) {
            _ = recognizer.scoredCandidates(stroke: stroke, button: .right, modifiers: [], in: config.general)
        }
        print("  索引 \(String(format: "%.0f", viaIndex)) µs vs 每次重建 \(String(format: "%.0f", viaTarget)) µs")

        // 索引路径必须明显快于每次重建。实测：评分约 400 µs，重建索引另加约 350 µs —— 所以这里
        // 只要求「快 25% 以上」，而不是某个夸张的倍数（我一开始按「重建占大头」写了「快一倍」，
        // 被这组数字推翻了）。重建在主线程上做没问题，做在拦截器线程上就是当初回调变慢的原因。
        #expect(viaIndex < viaTarget * 0.75, "索引路径的收益消失了 —— 检查是否又在每次事件里重建索引")
    }

    @Test("实时笔画只归一化一次：耗时不该随「点数 × 候选数」增长")
    func liveStrokeIsNormalisedOnce() throws {
        let index = try referenceIndex()
        let recognizer = GestureRecognizer(settings: index.settings)

        let short = makeStroke(pointCount: 50)
        let long = makeStroke(pointCount: 800)

        let shortCost = microsecondsPerCall(iterations: 80) {
            _ = recognizer.scoredCandidates(stroke: short, button: .right, modifiers: [], in: index)
        }
        let longCost = microsecondsPerCall(iterations: 80) {
            _ = recognizer.scoredCandidates(stroke: long, button: .right, modifiers: [], in: index)
        }
        print("  50 点: \(String(format: "%.0f", shortCost)) µs   800 点: \(String(format: "%.0f", longCost)) µs"
              + "   比值 \(String(format: "%.2f", longCost / shortCost))")

        // 16 倍点数只允许带来 6 倍以内的增长。若实时笔画被每个候选重新归一化，这一项会接近 16 倍。
        #expect(longCost < shortCost * 6, "笔画变长带来的耗时增长过大，说明实时笔画被反复归一化")
    }
}
