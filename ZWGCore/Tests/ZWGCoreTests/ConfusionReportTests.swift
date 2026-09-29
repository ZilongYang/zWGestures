import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

/// Diagnostic only: prints the gesture pairs that are close enough to be confused.
///
/// Hand-tuned shapes in a real configuration can sit surprisingly close together, and a pair that
/// is close to the match threshold will flip between the two depending on exactly how the stroke
/// is drawn. Running this over every gesture finds those pairs instead of discovering them one
/// user complaint at a time.
@Suite("诊断：手势之间的混淆距离")
struct ConfusionReportTests {
    private struct Entry {
        var name: String
        var directions: String
        var isSimple: Bool
        var path: [CGPoint]
    }

    private func entries() throws -> [Entry] {
        let directory = FixtureConfig.directory
        let config = try LegacyConfigImporter.load(from: directory).config
        let settings = GestureRecognizer().settings

        return config.general.intents.compactMap { intent in
            guard let stroke = intent.strokeStep else { return nil }
            return Entry(
                name: intent.name,
                directions: stroke.directionDescription,
                isSimple: stroke.isSimple,
                path: StrokeNormalizer.normalize(
                    stroke.drawingOrderPoints,
                    sampleCount: settings.sampleCount
                )
            )
        }
    }

    @Test(
        "打印参考配置里彼此最接近的手势对"
    )
    func reportsClosePairs() throws {
        let all = try entries()
        let threshold = GestureRecognizer().settings.matchThreshold

        var pairs: [(Entry, Entry, CGFloat)] = []
        for i in all.indices {
            for j in all.indices where j > i {
                let distance = StrokeMatcher.distance(all[i].path, all[j].path)
                if distance < 0.30 {
                    pairs.append((all[i], all[j], distance))
                }
            }
        }
        pairs.sort { $0.2 < $1.2 }

        print("### CONFUSION-BEGIN 阈值=\(threshold)  有轨迹的手势 \(all.count) 条")
        for (a, b, distance) in pairs {
            let mark = distance <= threshold ? "★会被误判" : " 接近"
            print("""
            ### \(mark) 距离=\(String(format: "%.4f", distance)) \
            「\(a.name)」\(a.isSimple ? "简" : "曲")=\(a.directions) \
            与「\(b.name)」\(b.isSimple ? "简" : "曲")=\(b.directions)
            """)
        }
        print("### CONFUSION-END 距离 < 0.30 的共 \(pairs.count) 对")
    }

    @Test(
        "重新载入 与 其他窗口 必须能区分开"
    )
    func reloadAndOtherWindowsStayDistinct() throws {
        let all = try entries()
        let threshold = GestureRecognizer().settings.matchThreshold
        func entry(_ name: String) throws -> Entry {
            try #require(all.first { $0.name == name }, "配置里应有「\(name)」")
        }

        let reload = try entry("重新载入")
        let other = try entry("其他窗口")

        // 用户实际上画的是这两个形状；若 y 轴处理反了，它们会互相变成对方的形状
        #expect(reload.directions == "下右→上右")
        #expect(other.directions == "上右→下右")
        #expect(StrokeMatcher.distance(reload.path, other.path) > threshold * 1.5)
    }

    @Test(
        "打印可疑手势的原始方向"
    )
    func printsTheSuspects() throws {
        let directory = FixtureConfig.directory
        let config = try LegacyConfigImporter.load(from: directory).config

        print("### SUSPECT-BEGIN")
        for intent in config.general.intents {
            guard ["重新载入", "其他窗口", "下一应用", "上一个应用", "Reload", "Force Reload"]
                .contains(intent.name),
                let stroke = intent.strokeStep
            else { continue }

            print("### 「\(intent.name)」 IsSimple=\(stroke.isSimple)")
            print("###    P = \(stroke.points)")
            let path = stroke.drawingOrderPoints
                .map { "(\(Int($0.x)),\(Int($0.y)))" }
                .joined(separator: " -> ")
            print("###    绘制顺序(屏幕坐标) = \(path)")
            print("###    方向 = \(stroke.directionDescription)   总长 = \(Int(StrokeNormalizer.pathLength(stroke.drawingOrderPoints)))")
        }
        print("### SUSPECT-END")
    }
}
