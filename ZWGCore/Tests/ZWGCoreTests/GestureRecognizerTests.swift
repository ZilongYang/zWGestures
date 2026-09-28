import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

// MARK: - Fixtures

/// Builds a stored `StrokeStep` from a shape expressed in *drawing order* using screen
/// coordinates, applying the real encoding rule: `P` is written in drawing order and its y axis
/// points upwards, so screen y is negated. Writing the raw arrays by hand produced a mirrored
/// fixture once already, so the rule lives in one place instead.
private func storedSimple(_ drawingOrder: [CGPoint]) -> WGStrokeStep {
    WGStrokeStep(
        isSimple: true,
        points: drawingOrder.flatMap { [Int($0.x), Int(-$0.y)] }
    )
}

/// Builds a live stroke from the same grid-space shape, scaled up and moved to a plausible
/// place on screen. One grid unit is 50 points, so `scale: 4` draws it 200 points long.
private func live(
    _ drawingOrder: [CGPoint],
    scale: CGFloat = 4,
    origin: CGPoint = CGPoint(x: 800, y: 600)
) -> Stroke {
    polyline(drawingOrder.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) })
}

private func polyline(_ points: [CGPoint]) -> Stroke {
    var stroke = Stroke(start: points[0], timestamp: 0)
    for point in points.dropFirst() {
        stroke.append(point, timestamp: 0.05, minDistance: 0, minInterval: 0)
    }
    return stroke
}

/// Shapes in drawing order, in grid units (50 points per unit, y growing downwards).
private enum Unit {
    static let up: [CGPoint] = [.zero, CGPoint(x: 0, y: -50)]
    static let down: [CGPoint] = [.zero, CGPoint(x: 0, y: 50)]
    static let left: [CGPoint] = [.zero, CGPoint(x: -50, y: 0)]
    static let right: [CGPoint] = [.zero, CGPoint(x: 50, y: 0)]
    static let upRight: [CGPoint] = [.zero, CGPoint(x: 50, y: -50)]
    static let downLeft: [CGPoint] = [.zero, CGPoint(x: -50, y: 50)]
    static let loopVertical: [CGPoint] = [.zero, CGPoint(x: 0, y: 50), .zero]
    static let loopHorizontal: [CGPoint] = [.zero, CGPoint(x: -50, y: 0), .zero]
    static let downThenRight: [CGPoint] = [.zero, CGPoint(x: 0, y: 50), CGPoint(x: 50, y: 50)]
    static let upThenRight: [CGPoint] = [.zero, CGPoint(x: 0, y: -50), CGPoint(x: 50, y: -50)]
    static let leftThenDown: [CGPoint] = [.zero, CGPoint(x: -50, y: 0), CGPoint(x: -50, y: 50)]

    /// The trajectory of the reference configuration's `重新载入` gesture, in drawing order.
    /// `P` for arbitrary shapes is exactly this list.
    static let reloadCurve: [CGPoint] = [
        CGPoint(x: 969, y: 546),
        CGPoint(x: 1069, y: 395),
        CGPoint(x: 1203, y: 575),
    ]

    static let all: [(String, [CGPoint])] = [
        ("上", up), ("下", down), ("左", left), ("右", right),
        ("右上", upRight), ("左下", downLeft),
        ("竖闭环", loopVertical), ("横闭环", loopHorizontal),
        ("下再右", downThenRight), ("上再右", upThenRight), ("左再下", leftThenDown),
    ]
}

/// Mimics an unsteady hand: alternating offsets of a few points.
private func jittered(_ shape: [CGPoint], by amount: CGFloat) -> [CGPoint] {
    shape.enumerated().map { index, point in
        let offset = index % 2 == 0 ? amount : -amount
        return CGPoint(x: point.x + offset, y: point.y - offset)
    }
}

/// A live stroke with hand jitter applied in *screen* points, after scaling — which is how a
/// real hand behaves. Jittering the grid-space shape instead would be scaled up with it.
private func liveJittered(
    _ shape: [CGPoint],
    screenJitter: CGFloat,
    scale: CGFloat = 4,
    origin: CGPoint = CGPoint(x: 800, y: 600)
) -> Stroke {
    polyline(jittered(live(shape, scale: scale, origin: origin).points, by: screenJitter))
}

private func distanceBetween(_ drawn: [CGPoint], _ stored: WGStrokeStep) -> CGFloat {
    StrokeMatcher.distance(stroke: live(drawn), definition: stored, sampleCount: 32)
}

// MARK: - Threshold calibration

/// The match threshold is not a guess. These tests measure the two quantities it has to sit
/// between, so a future change to the metric shows up as a failure rather than as gestures
/// that mysteriously stop working.
@Suite("识别：阈值标定")
struct RecognitionCalibrationTests {
    /// Distance from each shape to every *other* shape; the smallest value is the floor that
    /// separates a correct match from the nearest confusion.
    private func confusionFloor() -> (floor: CGFloat, pair: String, diagonal: CGFloat) {
        var floor = CGFloat.greatestFiniteMagnitude
        var pair = ""
        var diagonal: CGFloat = 0
        for (drawnName, drawn) in Unit.all {
            for (definitionName, definition) in Unit.all {
                let value = distanceBetween(drawn, storedSimple(definition))
                if drawnName == definitionName {
                    diagonal = max(diagonal, value)
                } else if value < floor {
                    floor = value
                    pair = "\(drawnName) vs \(definitionName)"
                }
            }
        }
        return (floor, pair, diagonal)
    }

    /// Measured distances to the vertical retrace `(0,0) → (0,50) → (0,0)`, over a 200-point
    /// tall loop. This is what fixes the threshold's upper bound.
    ///
    /// | 画出来的形状          | 距离   | 阈值 0.10 |
    /// |----------------------|--------|-----------|
    /// | 细长环 宽 6–60        | 0.004–0.039 | 命中 |
    /// | 椭圆 120×200 (宽高 0.6) | 0.079  | 命中 |
    /// | 椭圆 160×200 (宽高 0.8) | 0.103  | 不命中 |
    /// | 正圆                  | ≥0.143 | 不命中 |
    ///
    /// A true circle must stay unrecognised: where a circle lands depends on where the user
    /// started drawing it, so accepting it would make the same circle trigger `Web 搜索` or
    /// `退格` at random. The loop gestures have to be drawn elongated, which is exactly what
    /// the original app's quick-start teaches.
    @Test("闭环手势必须画成细长环；圆形不能被接受")
    func loopShapeToleranceMatchesTheDesign() {
        let settings = GestureRecognizer().settings
        let vertical = storedSimple(Unit.loopVertical)
        let horizontal = storedSimple(Unit.loopHorizontal)

        // 细长环命中
        for width in [6, 20, 45] as [CGFloat] {
            let value = loopDistance(width: width, height: 200)
            #expect(value < settings.matchThreshold, "细长环宽 \(width) 距离 \(value)，应当命中")
        }
        // 椭圆稍宽仍可命中
        #expect(loopDistance(width: 120, height: 200) < settings.matchThreshold)

        // 正圆不应被接受，而且它离两个闭环都不近
        let circle = circleStroke(diameter: 240)
        let toVertical = StrokeMatcher.distance(stroke: circle, definition: vertical, sampleCount: 32)
        let toHorizontal = StrokeMatcher.distance(stroke: circle, definition: horizontal, sampleCount: 32)
        #expect(min(toVertical, toHorizontal) > settings.matchThreshold)
        #expect(min(toVertical, toHorizontal) < 0.15, "0.15 的阈值就会把圆形误判给「退格」")
    }

    private func loopDistance(width: CGFloat, height: CGFloat) -> CGFloat {
        let oval = polyline([
            CGPoint(x: 800, y: 600),
            CGPoint(x: 800 + width / 2, y: 600 + height / 2),
            CGPoint(x: 800, y: 600 + height),
            CGPoint(x: 800 - width / 2, y: 600 + height / 2),
            CGPoint(x: 800, y: 600),
        ])
        return StrokeMatcher.distance(
            stroke: oval,
            definition: storedSimple(Unit.loopVertical),
            sampleCount: 32
        )
    }

    private func circleStroke(diameter: CGFloat) -> Stroke {
        polyline((0...64).map { step -> CGPoint in
            let angle = CGFloat(step) / 64 * 2 * .pi
            return CGPoint(
                x: 800 + cos(angle) * diameter / 2,
                y: 600 + sin(angle) * diameter / 2
            )
        })
    }

    @Test("同一形状必然命中，不同形状之间留有安全余量")
    func thresholdSitsBetweenMatchAndConfusion() {
        let settings = GestureRecognizer().settings
        let (floor, pair, diagonal) = confusionFloor()

        #expect(diagonal < 0.01, "同一形状之间的距离应该接近 0，实测 \(diagonal)")
        #expect(
            floor > settings.matchThreshold * 1.5,
            "最近的一组混淆形状「\(pair)」距离为 \(floor)，与阈值 \(settings.matchThreshold) 余量不足"
        )
    }

    @Test("真实手抖幅度下仍然命中，且不会滑向最近的非目标形状")
    func realisticJitterStaysWithinThreshold() {
        let settings = GestureRecognizer().settings
        // 200 点长的轨迹上抖动 6 点，约 3%，比正常人手画线更抖
        let jitter: CGFloat = 6

        for (name, shape) in Unit.all {
            let value = StrokeMatcher.distance(
                stroke: liveJittered(shape, screenJitter: jitter),
                definition: storedSimple(shape),
                sampleCount: settings.sampleCount
            )
            #expect(value < settings.matchThreshold, "「\(name)」在抖动后距离为 \(value)，超过了阈值")
        }

        // 向上画但手抖，仍然不应该滑向「上再右」
        let wobblyUp = StrokeMatcher.distance(
            stroke: liveJittered(Unit.up, screenJitter: jitter),
            definition: storedSimple(Unit.upThenRight),
            sampleCount: settings.sampleCount
        )
        #expect(wobblyUp > settings.matchThreshold)
    }
}

// MARK: - Simple strokes

@Suite("识别：简单手势")
struct SimpleStrokeRecognitionTests {
    @Test("向上画线命中「向上」，且远离其它方向")
    func upStrokeMatchesUpGesture() {
        #expect(distanceBetween(Unit.up, storedSimple(Unit.up)) < 0.02)
        for other in [Unit.down, Unit.left, Unit.right] {
            #expect(distanceBetween(Unit.up, storedSimple(other)) > 0.6)
        }
        // 斜线与「上再右」是最近的两种误判候选，实测都明显大于阈值
        #expect(distanceBetween(Unit.up, storedSimple(Unit.upRight)) > 0.3)
        #expect(distanceBetween(Unit.up, storedSimple(Unit.upThenRight)) > 0.15)
    }

    @Test("闭合竖环与闭合横环互相区分")
    func distinguishesLoops() {
        #expect(distanceBetween(Unit.loopVertical, storedSimple(Unit.loopVertical)) < 0.03)
        #expect(distanceBetween(Unit.loopHorizontal, storedSimple(Unit.loopHorizontal)) < 0.03)
        #expect(distanceBetween(Unit.loopVertical, storedSimple(Unit.loopHorizontal)) > 0.3)
    }

    @Test("L 形与其镜像、与直线都能区分")
    func distinguishesCorners() {
        #expect(distanceBetween(Unit.downThenRight, storedSimple(Unit.downThenRight)) < 0.03)
        #expect(distanceBetween(Unit.upThenRight, storedSimple(Unit.downThenRight)) > 0.3)
        #expect(distanceBetween(Unit.leftThenDown, storedSimple(Unit.downThenRight)) > 0.3)
        // 「下」与「下再右」共享前半段，是最接近的一组，仍然大于阈值
        #expect(distanceBetween(Unit.down, storedSimple(Unit.downThenRight)) > 0.15)
    }

    @Test("尺度不影响识别：画得大或小都一样")
    func scaleIndependent() {
        let definition = storedSimple(Unit.up)
        for scale in [0.6, 1, 4, 12] as [CGFloat] {
            let value = StrokeMatcher.distance(
                stroke: live(Unit.up, scale: scale),
                definition: definition,
                sampleCount: 32
            )
            #expect(value < 0.02, "缩放 \(scale) 时距离为 \(value)")
        }
    }
}

// MARK: - Arbitrary shapes

@Suite("识别：手写形状")
struct ArbitraryShapeRecognitionTests {
    /// The reference configuration's `重新载入` gesture, exactly as it appears in `P`.
    private let storedPoints: [CGPoint] = [
        CGPoint(x: 969, y: 546),
        CGPoint(x: 1069, y: 395),
        CGPoint(x: 1203, y: 575),
    ]

    /// The same trajectory in screen orientation — what the user's hand actually did.
    private var drawnPoints: [CGPoint] {
        storedPoints.map { CGPoint(x: $0.x, y: -$0.y) }
    }

    private var definition: WGStrokeStep {
        WGStrokeStep(isSimple: false, points: storedPoints.flatMap { [Int($0.x), Int($0.y)] })
    }

    private func drawn(_ points: [CGPoint], scale: CGFloat = 1, origin: CGPoint = .zero) -> Stroke {
        polyline(points.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) })
    }

    @Test("P 就是绘制顺序，且 y 轴向上为正")
    func definitionIsTheStoredPointList() {
        #expect(definition.points == [969, 546, 1069, 395, 1203, 575])
        #expect(definition.drawingOrderPoints == drawnPoints)
        #expect(definition.directionDescription == "下右→上右")
    }

    @Test("换个位置后仍然匹配")
    func matchesShiftedCurve() {
        let shifted = drawnPoints.map { CGPoint(x: $0.x - 400, y: $0.y + 120) }
        #expect(StrokeMatcher.distance(stroke: drawn(shifted), definition: definition, sampleCount: 32) < 0.02)
    }

    @Test("放大缩小后仍然匹配")
    func matchesScaledCurve() {
        for scale in [0.4, 1.0, 2.5] as [CGFloat] {
            let value = StrokeMatcher.distance(
                stroke: drawn(drawnPoints, scale: scale),
                definition: definition,
                sampleCount: 32
            )
            #expect(value < 0.02, "缩放 \(scale) 时距离为 \(value)")
        }
    }

    @Test("手的抖动不会破坏识别")
    func matchesJitteredCurve() {
        #expect(StrokeMatcher.distance(
            stroke: drawn(jittered(drawnPoints, by: 6)),
            definition: definition,
            sampleCount: 32
        ) < 0.1)
    }

    @Test("上下镜像后的同一形状不会被误判为匹配")
    func mirrorIsNotAMatch() {
        let mirrored = drawnPoints.map { CGPoint(x: $0.x, y: -$0.y) }
        #expect(StrokeMatcher.distance(
            stroke: drawn(mirrored),
            definition: definition,
            sampleCount: 32
        ) > 0.2)
    }
}

// MARK: - Matching against a target

/// Mirrors the shape of the real configuration: `拷贝` and `剪切` share an up-stroke and are
/// told apart only by the extra left-button press.
func simpleIntent(_ name: String, _ drawingOrder: [CGPoint], modifiers: [WGStep] = []) -> WGIntent {
    WGIntent(
        name: name,
        gesture: [
            .keyDown(WGKeyDownStep(key: "MOUSE:1")),
            .stroke(storedSimple(drawingOrder)),
        ] + modifiers,
        command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
    )
}

private func makeTarget() -> WGTarget {

    return WGTarget(
        kind: .general,
        name: "General",
        intents: [
            simpleIntent("Copy", Unit.up),
            simpleIntent("Paste", Unit.down),
            simpleIntent("Cut", Unit.up, modifiers: [.keyDown(WGKeyDownStep(key: "MOUSE:0"))]),
            simpleIntent("Web Search", Unit.loopVertical),
            simpleIntent("Backspace", Unit.loopHorizontal),
            WGIntent(
                name: "Terminal",
                gesture: [
                    .moveToEdgeCorner(WGMoveToEdgeCornerStep(edgeCorner: WGEdgeCorner(value: 8))),
                    .stroke(storedSimple(Unit.downThenRight)),
                ],
                command: .shellScript(WGShellScriptCommand(script: "open -a Terminal"))
            ),
        ]
    )
}

@Suite("识别：目标内的匹配与消歧")
struct TargetMatchingTests {
    @Test("向上画线命中「拷贝」")
    func matchesCopy() throws {
        let match = try #require(GestureRecognizer().recognize(
            stroke: live(Unit.up), button: .right, modifiers: [], in: makeTarget()
        ))
        #expect(match.name == "Copy")
    }

    @Test("画线时按了左键，则同一个向上轨迹命中「剪切」")
    func leftButtonSelectsCut() throws {
        let match = try #require(GestureRecognizer().recognize(
            stroke: live(Unit.up),
            button: .right,
            modifiers: [.down(.left), .up(.left)],
            in: makeTarget()
        ))
        #expect(match.name == "Cut", "更具体的定义（多一个修饰步骤）应当胜出")
    }

    @Test("横向闭环命中「退格」而不是「Web 搜索」")
    func horizontalLoopMatchesBackspace() throws {
        let match = try #require(GestureRecognizer().recognize(
            stroke: live(Unit.loopHorizontal), button: .right, modifiers: [], in: makeTarget()
        ))
        #expect(match.name == "Backspace")
    }

    @Test("完全不认识的形状不会误命中")
    func unknownShapeDoesNotMatch() {
        // 一个又大又歪的 Z 字，与列表里任何形状都不像
        let scribble = polyline([
            CGPoint(x: 300, y: 300), CGPoint(x: 700, y: 500),
            CGPoint(x: 320, y: 620), CGPoint(x: 720, y: 760),
        ])
        #expect(GestureRecognizer().recognize(
            stroke: scribble, button: .right, modifiers: [], in: makeTarget()
        ) == nil)
    }

    @Test("太短的轨迹不做识别，避免手抖误判")
    func veryShortStrokeIsIgnored() {
        let tiny = polyline([CGPoint(x: 500, y: 500), CGPoint(x: 506, y: 498)])
        #expect(GestureRecognizer().recognize(
            stroke: tiny, button: .right, modifiers: [], in: makeTarget()
        ) == nil)
    }

    @Test("左键触发时不会命中任何只认右键的手势")
    func leftButtonDoesNotMatchRightButtonGestures() {
        #expect(GestureRecognizer().recognize(
            stroke: live(Unit.up), button: .left, modifiers: [], in: makeTarget()
        ) == nil)
    }

    @Test("边角触发的手势在边角检测器就位前不参与匹配")
    func edgeTriggeredGesturesAreNotYetEligible() {
        // 「Terminal」的轨迹与「下再右」相同，但它要求先到屏幕边缘，所以现在不应该命中
        #expect(GestureRecognizer().recognize(
            stroke: live(Unit.downThenRight), button: .right, modifiers: [], in: makeTarget()
        ) == nil)
    }

    /// 两条同形、同修饰键的手势抢同一个输入时，**列表靠前的那条生效** —— 这是设置界面里
    /// 「上移 / 下移」之所以有意义的依据。用户明确要求「按照排序前面的优先」。
    @Test("同形冲突时列表靠前的优先")
    func earlierEntryWinsACollision() throws {
        func upStroke(_ name: String) -> WGIntent {
            WGIntent(
                name: name,
                gesture: [
                    .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                    .stroke(storedSimple(Unit.up)),
                ],
                command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"]))
            )
        }

        // 先放「后来的」，再放「更早的」——名字与顺序解耦，避免靠名字猜顺序。
        let laterFirst = WGTarget(kind: .general, name: "General", intents: [upStroke("Winner"), upStroke("Loser")])
        let match = try #require(GestureRecognizer().recognize(
            stroke: live(Unit.up), button: .right, modifiers: [], in: laterFirst
        ))
        #expect(match.name == "Winner")

        // 交换顺序后胜者跟着换。
        let swapped = WGTarget(kind: .general, name: "General", intents: [upStroke("Loser"), upStroke("Winner")])
        let swappedMatch = try #require(GestureRecognizer().recognize(
            stroke: live(Unit.up), button: .right, modifiers: [], in: swapped
        ))
        #expect(swappedMatch.name == "Loser")
    }

    /// 修饰键的优先级高于列表顺序：否则把「剪切」排到「拷贝」后面就会抢走"按住左键"的输入。
    @Test("修饰键更具体的优先，顺序不能推翻它")
    func specificModifiersBeatOrder() throws {
        let target = WGTarget(
            kind: .general,
            name: "General",
            intents: [
                WGIntent(
                    name: "Cut",
                    gesture: [
                        .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                        .stroke(storedSimple(Unit.up)),
                        .keyDown(WGKeyDownStep(key: "MOUSE:0")),
                    ],
                    command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_X"]))
                ),
                makeTarget().intents[0], // Copy：同为向上，不带修饰键，且排在后面
            ]
        )
        // 按住左键：两条都符合条件，但 Cut 更具体 → Cut 赢。
        let withModifier = try #require(GestureRecognizer().recognize(
            stroke: live(Unit.up),
            button: .right,
            modifiers: [.down(.left)],
            in: target
        ))
        #expect(withModifier.name == "Cut")

        // 不按左键：Copy 是唯一符合条件的。
        let plain = try #require(GestureRecognizer().recognize(
            stroke: live(Unit.up), button: .right, modifiers: [], in: target
        ))
        #expect(plain.name == "Copy")
    }

    @Test("禁用的手势永远不参与匹配，即使它是唯一符合条件的一条")
    func disabledGesturesNeverMatch() throws {
        var target = makeTarget()
        // 只留下一条手势，禁用它 —— 这时识别必须返回 nil，而不是「退而求其次」。
        let only = target.intents[0]
        target.intents = [WGIntent(
            name: only.name,
            executeOnRecognize: only.executeOnRecognize,
            gesture: only.gesture,
            command: only.command,
            enabled: false
        )]
        #expect(GestureRecognizer().recognize(
            stroke: live(Unit.up), button: .right, modifiers: [], in: target
        ) == nil)

        // 诊断用的候选列表也应当为空 —— 否则调试面板会报「最近的是某条已禁用的手势」。
        #expect(GestureRecognizer().scoredCandidates(
            stroke: live(Unit.up), button: .right, modifiers: [], in: target
        ).isEmpty)

        // 重新启用后就恢复命中。
        target.intents[0].enabled = true
        let match = try #require(GestureRecognizer().recognize(
            stroke: live(Unit.up), button: .right, modifiers: [], in: target
        ))
        #expect(match.name == "Copy")
    }

    @Test("禁用一条重复形状后，另一条就能正常生效")
    func disablingOneOfTwoDuplicatesLetsTheOtherWin() throws {
        func up(_ name: String, enabled: Bool) -> WGIntent {
            WGIntent(
                name: name,
                gesture: [
                    .keyDown(WGKeyDownStep(key: "MOUSE:1")),
                    .stroke(storedSimple(Unit.up)),
                ],
                command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: ["Command", "ANSI_C"])),
                enabled: enabled
            )
        }
        // 两条同形，靠前的那条被禁用 → 生效的是后面那条（顺序优先的规则只在启用的之间比）。
        let target = WGTarget(kind: .general, name: "General", intents: [
            up("Disabled", enabled: false),
            up("Live", enabled: true),
        ])
        let match = try #require(GestureRecognizer().recognize(
            stroke: live(Unit.up), button: .right, modifiers: [], in: target
        ))
        #expect(match.name == "Live")
    }

    /// 用户实际遇到并提出的问题：给某个应用配了 1 条手势后，那个应用里**其余全局手势都不见了**。
    /// 现在应用手势集是**叠加**在全局之上的：自己的优先，其余继承。
    @Test("应用手势集叠加在全局之上：自己的优先，未定义的手势仍继承全局")
    func applicationGesturesOverlayTheGeneralSet() throws {
        // 全局：向上=Copy，向下=Paste。
        let general = WGTarget(
            kind: .general,
            id: "general",
            name: "General",
            intents: [
                simpleIntent("Copy", Unit.up),
                simpleIntent("Paste", Unit.down),
            ]
        )
        // 应用：只加了一条「向右=Save」，并开着一个重复的「向上=App Copy」用来验证优先级。
        let appTarget = WGTarget(
            kind: .app,
            id: "app",
            name: "Brave",
            bundleId: "com.brave.Browser",
            path: "/Applications/Brave Browser.app",
            intents: [
                simpleIntent("App Copy", Unit.up),
                simpleIntent("Save", Unit.right),
            ]
        )
        let config = WGConfig(general: general, apps: [appTarget])
        let application = WGApplicationIdentity(
            pid: 42,
            bundleIdentifier: "com.brave.Browser",
            executablePath: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
            localizedName: "Brave"
        )
        let resolved = TargetResolver.resolve(config: config, application: application)
        #expect(resolved.kind == .application)
        let recognizer = GestureRecognizer()

        // ① 应用自己定义的手势命中它自己的那条（同形状时靠前的赢）。
        let up = try #require(recognizer.recognize(
            stroke: live(Unit.up), button: .right, modifiers: [], in: resolved.target,
            triggerMatrix: resolved.triggerMatrix
        ))
        #expect(up.name == "App Copy", "应用自己的同形状手势必须优先于全局的")

        // ② 应用没定义的手势仍然继承全局 —— 这就是之前缺失的行为。
        let down = try #require(recognizer.recognize(
            stroke: live(Unit.down), button: .right, modifiers: [], in: resolved.target,
            triggerMatrix: resolved.triggerMatrix
        ))
        #expect(down.name == "Paste")

        // ③ 应用自己的新形状也能命中。
        let right = try #require(recognizer.recognize(
            stroke: live(Unit.right), button: .right, modifiers: [], in: resolved.target,
            triggerMatrix: resolved.triggerMatrix
        ))
        #expect(right.name == "Save")

        // ④ 关掉继承后，只剩应用自己的两条：全局的 Paste 不再可用。
        var replaced = config
        replaced.apps[0].inheritsGlobal = false
        let replacing = TargetResolver.resolve(config: replaced, application: application)
        #expect(recognizer.recognize(
            stroke: live(Unit.down), button: .right, modifiers: [], in: replacing.target,
            triggerMatrix: replacing.triggerMatrix
        ) == nil, "关掉继承后不该再命中全局手势")
        #expect(recognizer.recognize(
            stroke: live(Unit.right), button: .right, modifiers: [], in: replacing.target,
            triggerMatrix: replacing.triggerMatrix
        )?.name == "Save")
    }
}
