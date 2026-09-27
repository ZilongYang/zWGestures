import CoreGraphics
import Foundation
import Testing

@testable import ZWGCore

private let t0: TimeInterval = 1000

private func down(_ button: MouseButton, _ x: CGFloat, _ y: CGFloat, at t: TimeInterval = t0) -> PointerEvent {
    PointerEvent(kind: .down(button), location: CGPoint(x: x, y: y), timestamp: t)
}

private func up(_ button: MouseButton, _ x: CGFloat, _ y: CGFloat, at t: TimeInterval = t0) -> PointerEvent {
    PointerEvent(kind: .up(button), location: CGPoint(x: x, y: y), timestamp: t)
}

private func drag(_ button: MouseButton, _ x: CGFloat, _ y: CGFloat, at t: TimeInterval = t0) -> PointerEvent {
    PointerEvent(kind: .drag(button), location: CGPoint(x: x, y: y), timestamp: t)
}

@Suite("输入引擎：普通点击与拖拽不被打断")
struct InputEnginePassthroughTests {
    @Test("左键是默认禁用的触发键，事件原样透传")
    func leftButtonPassesThrough() {
        let engine = InputEngine()
        #expect(engine.handle(down(.left, 10, 10)).effect == .passThrough)
        #expect(engine.handle(drag(.left, 40, 40)).effect == .passThrough)
        #expect(engine.handle(up(.left, 40, 40)).effect == .passThrough)
        #expect(engine.state == .idle)
    }

    @Test("滚轮与移动始终透传")
    func scrollAndMovePassThrough() {
        let engine = InputEngine()
        #expect(engine.handle(PointerEvent(kind: .move, location: .zero, timestamp: t0)).effect == .passThrough)
        #expect(engine
            .handle(PointerEvent(kind: .scroll(deltaX: 0, deltaY: 3), location: .zero, timestamp: t0))
            .effect == .passThrough)
    }

    @Test("触发键按下后先吞掉事件并进入 pending")
    func triggerPressIsSwallowed() {
        let engine = InputEngine()
        let decision = engine.handle(down(.right, 100, 100))
        #expect(decision.effect == .suppress)
        #expect(decision.state == .pending(PendingPress(
            button: .right,
            startPoint: CGPoint(x: 100, y: 100),
            startedAt: t0,
            lastPoint: CGPoint(x: 100, y: 100)
        )))
    }
}

@Suite("输入引擎：起始超时判定为普通点击")
struct InputEngineStartDragTimeoutTests {
    @Test("未移动即超时：在原按下点补发 down，之后全部透传")
    func timeoutReplaysPress() {
        let engine = InputEngine(settings: EngineSettings(startDragTimeout: 0.25))
        _ = engine.handle(down(.right, 100, 100))

        let decision = engine.startDragTimeoutFired(now: t0 + 0.3)
        #expect(decision.effect == .replay([
            PointerEvent(kind: .down(.right), location: CGPoint(x: 100, y: 100), timestamp: t0 + 0.3)
        ]))
        #expect(decision.state == .passthrough(.right))

        // 之后的拖拽与抬起都直接交给系统，窗口拖动/文字选择因此照常工作
        #expect(engine.handle(drag(.right, 140, 160)).effect == .passThrough)
        #expect(engine.handle(up(.right, 140, 160)).effect == .passThrough)
        #expect(engine.state == .idle)
    }

    @Test("小幅抖动不足以画手势，仍然判定为点击")
    func smallMovementStaysPending() {
        let engine = InputEngine(settings: EngineSettings(dragThreshold: 8))
        _ = engine.handle(down(.right, 100, 100))
        let decision = engine.handle(drag(.right, 105, 104))
        #expect(decision.effect == .suppress)
        #expect(decision.state.name == "pending")
    }

    @Test("超时后没有新事件时再调用不会重复补发")
    func timeoutIsIdempotent() {
        let engine = InputEngine()
        _ = engine.handle(down(.right, 100, 100))
        _ = engine.startDragTimeoutFired(now: t0 + 0.3)
        #expect(engine.startDragTimeoutFired(now: t0 + 0.4).effect == .suppress)
    }

    @Test("过期的定时器不能打断后来的一次按下")
    func staleTimeoutDoesNotCutShortANewPress() {
        let engine = InputEngine()
        _ = engine.handle(down(.right, 100, 100, at: t0))
        // 第一次按下已经被判定为普通点击
        _ = engine.startDragTimeoutFired(now: t0 + 0.3, expectingPressStartedAt: t0)
        #expect(engine.state == .passthrough(.right))
        _ = engine.handle(up(.right, 100, 100, at: t0 + 0.4))

        // 第二次按下
        _ = engine.handle(down(.right, 200, 200, at: t0 + 1.0))
        // 属于第一次按下的旧定时器此刻才触发，必须被忽略
        let decision = engine.startDragTimeoutFired(now: t0 + 1.05, expectingPressStartedAt: t0)
        #expect(decision.effect == .suppress)
        #expect(decision.state.name == "pending")

        // 属于第二次按下的定时器正常工作
        let real = engine.startDragTimeoutFired(now: t0 + 1.3, expectingPressStartedAt: t0 + 1.0)
        #expect(real.state == .passthrough(.right))
    }

    @Test("未移动即抬起：在原按下点补发完整的 down + up")
    func quickClickReplaysPressAndRelease() {
        let engine = InputEngine()
        _ = engine.handle(down(.right, 30, 40, at: t0))
        let decision = engine.handle(up(.right, 31, 41, at: t0 + 0.05))
        #expect(decision.effect == .replay([
            PointerEvent(kind: .down(.right), location: CGPoint(x: 30, y: 40), timestamp: t0 + 0.05),
            PointerEvent(kind: .up(.right), location: CGPoint(x: 30, y: 40), timestamp: t0 + 0.05),
        ]))
        #expect(engine.state == .idle)
    }
}

@Suite("输入引擎：手势绘制")
struct InputEngineDrawingTests {
    @Test("位移超过阈值后进入 drawing，并吞掉拖拽事件")
    func dragBeyondThresholdStartsDrawing() {
        let engine = InputEngine(settings: EngineSettings(dragThreshold: 8))
        _ = engine.handle(down(.right, 100, 100, at: t0))
        let decision = engine.handle(drag(.right, 100, 60, at: t0 + 0.05))

        #expect(decision.effect == .suppress)
        guard case .drawing(let gesture) = decision.state else {
            Issue.record("状态应为 drawing，实际为 \(decision.state)")
            return
        }
        #expect(gesture.button == .right)
        #expect(gesture.stroke.points == [CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 60)])
    }

    @Test("抬起触发键时交出完整的手势候选")
    func releaseEmitsCandidate() {
        var settings = EngineSettings()
        settings.strokeMinDistance = 0
        settings.strokeSampleInterval = 0
        let engine = InputEngine(settings: settings)

        _ = engine.handle(down(.right, 100, 100, at: t0))
        _ = engine.handle(drag(.right, 100, 60, at: t0 + 0.05))
        _ = engine.handle(drag(.right, 140, 60, at: t0 + 0.10))
        let decision = engine.handle(up(.right, 140, 60, at: t0 + 0.20))

        guard case .gestureCompleted(let candidate) = decision.effect else {
            Issue.record("应产出 gestureCompleted，实际为 \(decision.effect)")
            return
        }
        #expect(candidate.button == .right)
        #expect(candidate.stroke.points == [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 60),
            CGPoint(x: 140, y: 60),
        ])
        // 手势总时长以按下到抬起为准；stroke.duration 只覆盖采样到的轨迹点。
        #expect(abs((candidate.endedAt - candidate.startedAt) - 0.20) < 0.0001)
        #expect(abs(candidate.stroke.duration - 0.10) < 0.0001)
        #expect(engine.state == .idle)
    }

    @Test("绘制期间按下的其它按键与滚轮被记录为手势修饰键并吞掉")
    func modifierStepsAreRecorded() {
        let engine = InputEngine(settings: EngineSettings(dragThreshold: 8))
        _ = engine.handle(down(.right, 100, 100, at: t0))
        _ = engine.handle(drag(.right, 100, 60, at: t0 + 0.05))

        #expect(engine.handle(down(.left, 100, 60, at: t0 + 0.06)).effect == .suppress)
        #expect(engine.handle(up(.left, 100, 60, at: t0 + 0.07)).effect == .suppress)
        #expect(engine
            .handle(PointerEvent(kind: .scroll(deltaX: 0, deltaY: -1), location: CGPoint(x: 100, y: 60), timestamp: t0 + 0.08))
            .effect == .suppress)

        let decision = engine.handle(up(.right, 100, 60, at: t0 + 0.09))
        guard case .gestureCompleted(let candidate) = decision.effect else {
            Issue.record("应产出 gestureCompleted")
            return
        }
        #expect(candidate.modifiers == [
            .down(.left),
            .up(.left),
            .scroll(deltaX: 0, deltaY: -1),
        ])
    }

    @Test("重置会丢弃进行中的状态")
    func resetDropsInFlightState() {
        let engine = InputEngine()
        _ = engine.handle(down(.right, 100, 100))
        #expect(engine.state.name == "pending")
        engine.reset()
        #expect(engine.state == .idle)
        #expect(engine.startDragTimeoutDeadline() == nil)
    }
}

@Suite("轨迹几何")
struct StrokeTests {
    @Test("等距重采样得到稳定的点数与端点")
    func resamplingKeepsEndpoints() {
        var stroke = Stroke(start: CGPoint(x: 0, y: 0), timestamp: 0)
        stroke.append(CGPoint(x: 100, y: 0), timestamp: 1, minDistance: 0, minInterval: 0)

        let points = stroke.resampled(count: 5)
        #expect(points.count == 5)
        #expect(points.first == CGPoint(x: 0, y: 0))
        #expect(points.last == CGPoint(x: 100, y: 0))
        #expect(abs(points[2].x - 50) < 0.001)
    }

    @Test("直线与折线的转向量不同")
    func totalTurnDistinguishesShapes() {
        var straight = Stroke(start: CGPoint(x: 0, y: 0), timestamp: 0)
        for x in stride(from: 10, through: 100, by: 10) {
            straight.append(CGPoint(x: x, y: 0), timestamp: 0, minDistance: 0, minInterval: 0)
        }
        #expect(straight.totalTurn < 0.001)

        var corner = Stroke(start: CGPoint(x: 0, y: 0), timestamp: 0)
        corner.append(CGPoint(x: 50, y: 0), timestamp: 0, minDistance: 0, minInterval: 0)
        corner.append(CGPoint(x: 50, y: 50), timestamp: 0, minDistance: 0, minInterval: 0)
        #expect(abs(corner.totalTurn - .pi / 2) < 0.001)
    }
}
