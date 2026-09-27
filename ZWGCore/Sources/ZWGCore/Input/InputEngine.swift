import CoreGraphics
import Foundation

/// Tunables for the gesture engine, mirroring the WGestures preferences and a few
/// implementation-specific thresholds.
public struct EngineSettings: Sendable, Equatable {
    /// How long the trigger button may be held without meaningful movement before the
    /// press is treated as an ordinary click. WGestures: 手势起始超时.
    public var startDragTimeout: TimeInterval

    /// Movement (in points) that turns a pending press into a gesture.
    public var dragThreshold: CGFloat

    /// Minimum spacing between recorded stroke samples, to keep the trail cheap.
    public var strokeMinDistance: CGFloat

    /// Minimum time between recorded stroke samples.
    public var strokeSampleInterval: TimeInterval

    /// Buttons that may start a gesture.
    ///
    /// The left button is excluded by default: WGestures 2.5.0 onwards deliberately does
    /// not block left clicks, and the reference configuration has the left-button trigger
    /// disabled.
    public var enabledButtons: Set<MouseButton>

    public init(
        startDragTimeout: TimeInterval = 0.25,
        dragThreshold: CGFloat = 8,
        strokeMinDistance: CGFloat = 1.5,
        strokeSampleInterval: TimeInterval = 0.008,
        enabledButtons: Set<MouseButton> = [.right, .center, .side1, .side2]
    ) {
        self.startDragTimeout = startDragTimeout
        self.dragThreshold = dragThreshold
        self.strokeMinDistance = strokeMinDistance
        self.strokeSampleInterval = strokeSampleInterval
        self.enabledButtons = enabledButtons
    }
}

/// Where the engine is in the press/draw cycle. Exposed for the debug HUD and tests.
public enum EngineState: Sendable, Equatable {
    /// Nothing pressed.
    case idle
    /// A trigger button was pressed and swallowed; waiting to see whether a gesture starts.
    case pending(PendingPress)
    /// The user is drawing a gesture.
    case drawing(DrawingGesture)
    /// The press was judged an ordinary click; the button is logically down and every
    /// event flows straight through.
    case passthrough(MouseButton)

    public var name: String {
        switch self {
        case .idle: "idle"
        case .pending: "pending"
        case .drawing: "drawing"
        case .passthrough: "passthrough"
        }
    }
}

public struct PendingPress: Sendable, Equatable {
    public var button: MouseButton
    /// Where the button went down; replayed events use this point so the click lands
    /// exactly where the user pressed.
    public var startPoint: CGPoint
    public var startedAt: TimeInterval
    public var lastPoint: CGPoint
}

public struct DrawingGesture: Sendable, Equatable {
    public var button: MouseButton
    public var startedAt: TimeInterval
    public var stroke: Stroke
    /// Extra button presses / scrolls performed while drawing. WGestures calls these
    /// 手势修饰键 and uses them to disambiguate strokes that share a trajectory.
    public var modifiers: [PointerEvent.Kind]
}

/// A finished gesture, ready for recognition.
public struct GestureCandidate: Sendable, Equatable {
    public var button: MouseButton
    public var stroke: Stroke
    public var modifiers: [PointerEvent.Kind]
    public var startedAt: TimeInterval
    public var endedAt: TimeInterval
}

/// What the platform layer should do with the event that produced this decision.
public enum EngineEffect: Sendable, Equatable {
    /// Deliver the original event unchanged.
    case passThrough
    /// Drop the original event.
    case suppress
    /// Drop the original event and post these synthetic events instead.
    case replay([PointerEvent])
    /// The stroke finished; recognition decides what happens next.
    case gestureCompleted(GestureCandidate)
}

public struct EngineDecision: Sendable, Equatable {
    public var effect: EngineEffect
    public var state: EngineState
}

/// The press/draw state machine.
///
/// Deliberately free of any CoreGraphics event-tap plumbing so it can be unit tested, and
/// deliberately **not** thread safe: the caller must confine it to a single thread (the
/// event-tap thread). See `EventTapController.performOnTapThread`.
public final class InputEngine {
    public private(set) var state: EngineState = .idle
    public var settings: EngineSettings

    public init(settings: EngineSettings = EngineSettings()) {
        self.settings = settings
    }

    /// Feeds one event in and reports what to do with it.
    public func handle(_ event: PointerEvent) -> EngineDecision {
        switch (state, event.kind) {
        case (.idle, .down(let button)) where settings.enabledButtons.contains(button):
            state = .pending(PendingPress(
                button: button,
                startPoint: event.location,
                startedAt: event.timestamp,
                lastPoint: event.location
            ))
            return decision(.suppress)

        case (.idle, _):
            return decision(.passThrough)

        case (.pending(var press), .drag(let button)) where button == press.button:
            press.lastPoint = event.location
            guard distance(press.startPoint, event.location) >= settings.dragThreshold else {
                state = .pending(press)
                return decision(.suppress)
            }
            var stroke = Stroke(start: press.startPoint, timestamp: press.startedAt)
            stroke.append(
                event.location,
                timestamp: event.timestamp,
                minDistance: 0,
                minInterval: 0
            )
            state = .drawing(DrawingGesture(
                button: press.button,
                startedAt: press.startedAt,
                stroke: stroke,
                modifiers: []
            ))
            return decision(.suppress)

        case (.pending(let press), .up(let button)) where button == press.button:
            // Released without drawing: replay a complete click at the press point.
            state = .idle
            let replay = [
                PointerEvent(kind: .down(press.button), location: press.startPoint, timestamp: event.timestamp),
                PointerEvent(kind: .up(press.button), location: press.startPoint, timestamp: event.timestamp),
            ]
            return decision(.replay(replay))

        case (.pending, _):
            // Unrelated events (another button, scroll) are none of our business yet.
            return decision(.passThrough)

        case (.drawing(var gesture), .drag(let button)) where button == gesture.button:
            gesture.stroke.append(
                event.location,
                timestamp: event.timestamp,
                minDistance: settings.strokeMinDistance,
                minInterval: settings.strokeSampleInterval
            )
            state = .drawing(gesture)
            return decision(.suppress)

        case (.drawing(var gesture), .up(let button)) where button == gesture.button:
            // Capture the release point too: the last drag sample can lag behind it, and the
            // very end of the trajectory is what decides some gestures.
            gesture.stroke.append(
                event.location,
                timestamp: event.timestamp,
                minDistance: 0.5,
                minInterval: 0
            )
            state = .idle
            let candidate = GestureCandidate(
                button: gesture.button,
                stroke: gesture.stroke,
                modifiers: gesture.modifiers,
                startedAt: gesture.startedAt,
                endedAt: event.timestamp
            )
            return decision(.gestureCompleted(candidate))

        case (.drawing(var gesture), .down(let button)):
            gesture.modifiers.append(.down(button))
            state = .drawing(gesture)
            return decision(.suppress)

        case (.drawing(var gesture), .up(let button)):
            gesture.modifiers.append(.up(button))
            state = .drawing(gesture)
            return decision(.suppress)

        case (.drawing(var gesture), .scroll(let deltaX, let deltaY)):
            gesture.modifiers.append(.scroll(deltaX: deltaX, deltaY: deltaY))
            state = .drawing(gesture)
            return decision(.suppress)

        case (.drawing, .move):
            return decision(.suppress)

        case (.drawing, _):
            // Anything else that happens mid-stroke (another button being dragged, …) is
            // swallowed so it cannot leak through to the app underneath.
            return decision(.suppress)

        case (.passthrough, .up):
            state = .idle
            return decision(.passThrough)

        case (.passthrough, _):
            return decision(.passThrough)
        }
    }

    /// Called when the start-drag timeout elapses. Only meaningful while `pending`.
    public func startDragTimeoutFired(now: TimeInterval) -> EngineDecision {
        guard case .pending(let press) = state else {
            return decision(.suppress)
        }

        // No meaningful movement: treat it as an ordinary press, so that a subsequent drag
        // (text selection, window move, …) reaches the app naturally. The synthetic press
        // is posted at the original point so the press lands where the user pressed.
        state = .passthrough(press.button)
        return decision(.replay([
            PointerEvent(kind: .down(press.button), location: press.startPoint, timestamp: now)
        ]))
    }

    /// How long until the start-drag timeout fires, or `nil` when not pending.
    public func startDragTimeoutDeadline() -> TimeInterval? {
        guard case .pending(let press) = state else { return nil }
        return press.startedAt + settings.startDragTimeout
    }

    /// Drops any in-flight state without emitting events.
    ///
    /// Used when the event tap is disabled by the system: we may have missed the button
    /// release, and the underlying app has already been told whatever it was told.
    public func reset() {
        state = .idle
    }

    private func decision(_ effect: EngineEffect) -> EngineDecision {
        EngineDecision(effect: effect, state: state)
    }
}
