import CoreGraphics
import Foundation

/// A cheap, lock-guarded view of the engine, for the debug HUD and the menu bar.
struct InputSnapshot: Sendable, Equatable {
    var stateName: String = "idle"
    var lastEffect: String = "-"
    var strokePointCount: Int = 0
    var strokeStart: CGPoint = .zero
    var strokeEnd: CGPoint = .zero
    var eventCount: Int = 0
    var gestureCount: Int = 0
    var replayCount: Int = 0
    var tapStatus: String = "stopped"
}

/// Wires the event tap to the gesture engine and carries out the engine's decisions.
///
/// `handle(_:)` and everything it calls run on the tap thread; `snapshot` may be read from
/// any thread.
final class InputCoordinator: @unchecked Sendable {
    let engine: InputEngine
    private let tap = EventTapController()

    private let snapshotLock = NSLock()
    private var snapshotStorage = InputSnapshot()

    private var scheduledPressStartedAt: TimeInterval?

    /// Invoked on the tap thread when the emergency-stop shortcut is pressed.
    var onPanic: (@Sendable () -> Void)?

    init(settings: EngineSettings = EngineSettings()) {
        engine = InputEngine(settings: settings)
    }

    var snapshot: InputSnapshot {
        snapshotLock.withLock { snapshotStorage }
    }

    var isRunning: Bool { tap.status.isRunning }

    // MARK: - Lifecycle

    @discardableResult
    func start() -> Bool {
        // Set before starting: the tap thread reads them, and they never change afterwards.
        tap.handler = { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        tap.onSystemDisable = { [weak self] in
            // The tap was off for a while, so a button release may have been missed. Drop the
            // in-flight state rather than replaying a gesture that never finished.
            self?.engine.reset()
            self?.updateSnapshot(with: .suppress, state: self?.engine.state ?? .idle)
        }

        let installed = tap.start()
        if !installed {
            Log.input.error("event tap 安装失败：\(String(describing: self.tap.status), privacy: .public)")
        }
        updateSnapshot(with: .suppress, state: engine.state)
        return installed
    }

    func stop() {
        tap.stop()
    }

    // MARK: - Tap thread

    private func handle(_ event: CGEvent) -> CGEvent? {
        // Never react to our own synthetic events.
        guard !SyntheticEventPoster.isSynthetic(event) else { return event }

        // Emergency stop. Handled here rather than through a separate global monitor so that
        // it works even while a gesture is in flight.
        if event.type == .keyDown, PanicShortcut.matches(event) {
            Log.app.error("panic shortcut pressed; stopping the input engine")
            engine.reset()
            onPanic?()
            return nil
        }

        guard let pointerEvent = Self.pointerEvent(from: event) else { return event }

        let decision = engine.handle(pointerEvent)
        perform(decision.effect)
        updateSnapshot(with: decision.effect, state: decision.state)
        scheduleStartDragTimeoutIfNeeded(for: decision.state)

        return decision.effect == .passThrough ? event : nil
    }

    private func perform(_ effect: EngineEffect) {
        switch effect {
        case .passThrough, .suppress:
            break

        case .replay(let events):
            SyntheticEventPoster.post(events)

        case .gestureCompleted(let candidate):
            // P1 has no recogniser yet, so every finished stroke is replayed. Without this,
            // right-button drags would be swallowed and the app underneath would misbehave.
            Log.recog.debug("""
                stroke finished: \(candidate.stroke.points.count, privacy: .public) points, \
                length \(candidate.stroke.pathLength, privacy: .public) pt, \
                modifiers \(candidate.modifiers.count, privacy: .public)
                """)
            SyntheticEventPoster.replay(candidate)
        }
    }

    private func scheduleStartDragTimeoutIfNeeded(for state: EngineState) {
        guard case .pending(let press) = state else {
            scheduledPressStartedAt = nil
            return
        }
        guard scheduledPressStartedAt != press.startedAt else { return }
        scheduledPressStartedAt = press.startedAt

        let deadline = press.startedAt + engine.settings.startDragTimeout
        let delay = max(0, deadline - MachTime.now)

        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.tap.performOnTapThread { [weak self] in
                guard let self else { return }
                let decision = self.engine.startDragTimeoutFired(now: MachTime.now)
                self.perform(decision.effect)
                self.updateSnapshot(with: decision.effect, state: decision.state)
            }
        }
    }

    private func updateSnapshot(with effect: EngineEffect, state: EngineState) {
        snapshotLock.withLock {
            var next = snapshotStorage
            next.eventCount += 1
            next.stateName = state.name
            next.tapStatus = Self.describe(tap.status)
            switch effect {
            case .passThrough:
                next.lastEffect = "passThrough"
            case .suppress:
                next.lastEffect = "suppress"
            case .replay(let events):
                next.lastEffect = "replay(\(events.count))"
                next.replayCount += 1
            case .gestureCompleted(let candidate):
                next.lastEffect = "gestureCompleted"
                next.gestureCount += 1
                next.strokeStart = candidate.stroke.startPoint
                next.strokeEnd = candidate.stroke.endPoint
            }
            switch state {
            case .drawing(let gesture):
                next.strokePointCount = gesture.stroke.points.count
            default:
                next.strokePointCount = 0
            }
            snapshotStorage = next
        }
    }

    private static func describe(_ status: EventTapController.Status) -> String {
        switch status {
        case .stopped: "stopped"
        case .running: "running"
        case .systemDisabled: "systemDisabled"
        case .failed(let reason): "failed: \(reason)"
        }
    }

    // MARK: - CGEvent translation

    static func pointerEvent(from event: CGEvent) -> PointerEvent? {
        let location = event.location
        let timestamp = MachTime.seconds(event.timestamp)

        switch event.type {
        case .leftMouseDown:
            return PointerEvent(kind: .down(.left), location: location, timestamp: timestamp)
        case .leftMouseUp:
            return PointerEvent(kind: .up(.left), location: location, timestamp: timestamp)
        case .leftMouseDragged:
            return PointerEvent(kind: .drag(.left), location: location, timestamp: timestamp)

        case .rightMouseDown:
            return PointerEvent(kind: .down(.right), location: location, timestamp: timestamp)
        case .rightMouseUp:
            return PointerEvent(kind: .up(.right), location: location, timestamp: timestamp)
        case .rightMouseDragged:
            return PointerEvent(kind: .drag(.right), location: location, timestamp: timestamp)

        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            guard let button = buttonNumber(of: event) else { return nil }
            let kind: PointerEvent.Kind = switch event.type {
            case .otherMouseDown: .down(button)
            case .otherMouseUp: .up(button)
            default: .drag(button)
            }
            return PointerEvent(kind: kind, location: location, timestamp: timestamp)

        case .mouseMoved:
            return PointerEvent(kind: .move, location: location, timestamp: timestamp)

        case .scrollWheel:
            return PointerEvent(
                kind: .scroll(
                    deltaX: event.getDoubleValueField(.scrollWheelEventDeltaAxis2),
                    deltaY: event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                ),
                location: location,
                timestamp: timestamp
            )

        default:
            return nil
        }
    }

    private static func buttonNumber(of event: CGEvent) -> MouseButton? {
        let raw = event.getIntegerValueField(.mouseEventButtonNumber)
        return MouseButton(rawValue: Int(raw))
    }
}
