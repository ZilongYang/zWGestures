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
    var timeoutCount: Int = 0
    var tapStatus: String = "stopped"
    /// Name of the last recognised gesture, or nil when the last stroke matched nothing.
    var lastGestureName: String?
    var lastGestureDistance: CGFloat?
    /// Closest configured gesture when the stroke did *not* match — for diagnosing misses.
    var nearestGestureName: String?
    var nearestGestureDistance: CGFloat?
    var strokeLength: CGFloat = 0
    var matchedCount: Int = 0
    /// Short description of the last command that actually ran.
    var lastExecuted: String?
    /// Which gesture set applied to the last stroke: the general one, or an application's.
    var targetName: String?
}

/// Everything the tap thread needs in order to decide which gesture set applies.
///
/// The application directory is a snapshot rather than a live reference so that nothing on the
/// tap thread has to call AppKit.
struct RecognitionContext: Sendable {
    var config = WGConfig()
    var targetMode: WGTargetMode = .focused
    var applications: [Int32: WGApplicationIdentity] = [:]
    var focusedPID: Int32?

    func identity(for pid: Int32) -> WGApplicationIdentity? {
        applications[pid]
    }

    var focusedIdentity: WGApplicationIdentity? {
        focusedPID.flatMap { applications[$0] }
    }
}

/// A recognised gesture together with everything the command needs to run.
struct GestureOutcome: Sendable {
    var match: RecognitionMatch
    var candidate: GestureCandidate
    var target: WGResolvedTarget
    /// Window server id of the window the gesture started over, when one was found.
    var windowID: Int?
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

    /// Written from the main thread, read on the tap thread.
    private let recognitionLock = NSLock()
    private var recognizer = GestureRecognizer()
    private var recognitionContext = RecognitionContext()

    /// Tap-thread state.
    private var pendingTimer: CFRunLoopTimer?
    private var armedPressStartedAt: TimeInterval?
    /// The target resolved when the current press began, so a stroke is matched against the
    /// application it started over even if focus changes mid-gesture.
    private var pressTarget: WGResolvedTarget?
    private var pressWindowID: Int?

    /// Invoked on the tap thread when the emergency-stop shortcut is pressed.
    var onPanic: (@Sendable () -> Void)?

    /// Invoked on the tap thread when a stroke matches a configured gesture. The handler must
    /// return promptly — it must hand off anything slow to another queue.
    var onGestureMatched: (@Sendable (GestureOutcome) -> Void)?

    init(settings: EngineSettings = EngineSettings()) {
        engine = InputEngine(settings: settings)
    }

    var snapshot: InputSnapshot {
        snapshotLock.withLock { snapshotStorage }
    }

    var isRunning: Bool { tap.status.isRunning }

    /// Publishes the gesture sets, the targeting mode and the application directory.
    func updateRecognition(_ context: RecognitionContext, settings: RecognitionSettings = RecognitionSettings()) {
        recognitionLock.withLock {
            recognitionContext = context
            recognizer = GestureRecognizer(settings: settings)
        }
    }

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
            guard let self else { return }
            self.cancelPendingTimer()
            self.engine.reset()
            self.updateSnapshot(with: .suppress, state: self.engine.state)
        }
        tap.onTapThreadTeardown = { [weak self] in
            self?.cancelPendingTimer()
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
            cancelPendingTimer()
            engine.reset()
            onPanic?()
            return nil
        }

        guard let pointerEvent = Self.pointerEvent(from: event) else { return event }

        let decision = engine.handle(pointerEvent)
        perform(decision.effect)
        updateSnapshot(with: decision.effect, state: decision.state)
        captureTargetIfNeeded(for: decision.state)
        rescheduleStartDragTimeout(for: decision.state)

        return decision.effect == .passThrough ? event : nil
    }

    private func perform(_ effect: EngineEffect) {
        switch effect {
        case .passThrough, .suppress:
            break

        case .replay(let events):
            SyntheticEventPoster.post(events)

        case .gestureCompleted(let candidate):
            handleCompletedGesture(candidate)
        }
    }

    /// A finished stroke either matches a configured gesture or is handed back to the app.
    ///
    /// Replaying an unmatched stroke matters: without it a right-button drag would simply
    /// vanish, and the context menu or text selection the user expected would never appear.
    private func handleCompletedGesture(_ candidate: GestureCandidate) {
        let (recognizer, context) = recognitionLock.withLock { (self.recognizer, self.recognitionContext) }
        let resolved = pressTarget ?? resolveTarget(at: candidate.stroke.startPoint, in: context)
        let windowID = pressWindowID
        pressTarget = nil
        pressWindowID = nil

        let match = recognizer.recognize(
            stroke: candidate.stroke,
            button: candidate.button,
            modifiers: candidate.modifiers,
            in: resolved.target
        )

        // Diagnose a miss by reporting the closest configured gesture anyway: "nothing
        // matched" without a number is impossible to act on.
        let nearest = match == nil
            ? recognizer.nearestCandidate(
                stroke: candidate.stroke,
                button: candidate.button,
                modifiers: candidate.modifiers,
                in: resolved.target
            )
            : nil

        record(match, nearest: nearest, candidate: candidate, resolved: resolved)

        if let match {
            Log.recog.notice("""
                命中手势「\(match.intent.name, privacy: .public)」\
                （距离 \(match.distance, privacy: .public)，\
                目标 \(resolved.displayName, privacy: .public)，\
                \(candidate.stroke.points.count, privacy: .public) 个轨迹点）
                """)
            onGestureMatched?(GestureOutcome(
                match: match,
                candidate: candidate,
                target: resolved,
                windowID: windowID
            ))
        } else {
            Log.recog.debug("""
                未识别：\(candidate.stroke.points.count, privacy: .public) 点、\
                长度 \(candidate.stroke.pathLength, privacy: .public)、\
                目标 \(resolved.displayName, privacy: .public)、\
                最近的是「\(nearest?.intent.name ?? "无候选", privacy: .public)」\
                距离 \(nearest?.distance ?? .infinity, privacy: .public)，回放给系统
                """)
            SyntheticEventPoster.replay(candidate)
        }
    }

    private func captureTargetIfNeeded(for state: EngineState) {
        guard case .pending(let press) = state else {
            if case .drawing = state { return }
            pressTarget = nil
            pressWindowID = nil
            return
        }
        guard pressTarget == nil else { return }

        let context = recognitionLock.withLock { recognitionContext }
        // In focused mode the probe is usually unnecessary, so only pay for it when the result
        // can change the answer.
        let probe = needsWindowProbe(for: context) ? WindowProbe.probe(at: press.startPoint) : nil
        pressWindowID = probe?.windowID
        pressTarget = resolveTarget(at: press.startPoint, in: context, probe: probe)
    }

    private func needsWindowProbe(for context: RecognitionContext) -> Bool {
        switch context.targetMode {
        case .underCursor: true
        case .focused: context.focusedIdentity?.bundleIdentifier == "com.apple.finder"
        }
    }

    /// Works out which application (or the desktop) the gesture is aimed at.
    ///
    /// Probing the window server costs a few milliseconds, and this runs on the tap thread, so
    /// `focused` mode skips the probe entirely unless the focused application is Finder — the
    /// only case where the desktop matters.
    private func resolveTarget(
        at point: CGPoint,
        in context: RecognitionContext,
        probe providedProbe: WindowProbe.Result? = nil
    ) -> WGResolvedTarget {
        if case .focused = context.targetMode,
           let focused = context.focusedIdentity,
           focused.bundleIdentifier != "com.apple.finder"
        {
            return TargetResolver.resolve(
                config: context.config,
                application: focused,
                isOverDesktop: false,
                mode: context.targetMode
            )
        }

        let probe = providedProbe ?? WindowProbe.probe(at: point)

        let application: WGApplicationIdentity?
        switch context.targetMode {
        case .underCursor:
            application = probe.flatMap { context.identity(for: $0.pid) }
        case .focused:
            application = context.focusedIdentity
        }

        // The desktop is Finder's window at a lower layer; only treat it as the desktop when the
        // point really landed there.
        let isOverDesktop = probe?.isDesktop == true
            && (application?.bundleIdentifier ?? "com.apple.finder") == "com.apple.finder"

        return TargetResolver.resolve(
            config: context.config,
            application: application,
            isOverDesktop: isOverDesktop,
            mode: context.targetMode
        )
    }

    private func record(
        _ match: RecognitionMatch?,
        nearest: RecognitionMatch?,
        candidate: GestureCandidate,
        resolved: WGResolvedTarget
    ) {
        snapshotLock.withLock {
            var next = snapshotStorage
            next.lastGestureName = match?.intent.name
            next.lastGestureDistance = match?.distance
            next.nearestGestureName = match == nil ? nearest?.intent.name : nil
            next.nearestGestureDistance = match == nil ? nearest?.distance : nil
            next.strokeStart = candidate.stroke.startPoint
            next.strokeEnd = candidate.stroke.endPoint
            next.strokeLength = candidate.stroke.pathLength
            next.targetName = resolved.displayName
            if match != nil { next.matchedCount += 1 }
            snapshotStorage = next
        }
    }

    /// Records that a command ran, for the debug HUD. Safe to call from any thread.
    func noteExecuted(_ summary: String) {
        snapshotLock.withLock { snapshotStorage.lastExecuted = summary }
    }

    // MARK: - Start-drag timeout
    //
    // The timer lives on the tap thread's run loop. Two rules keep it honest:
    //
    // 1. The delay is always *relative* to the moment it is armed. Wall-clock or mach-time
    //    arithmetic against `event.timestamp` is never used, because that timestamp is not on
    //    a known time base.
    // 2. Each timer remembers which press it belongs to, so a late fire cannot cut short a
    //    later press.

    private func rescheduleStartDragTimeout(for state: EngineState) {
        guard case .pending(let press) = state else {
            cancelPendingTimer()
            return
        }
        guard armedPressStartedAt != press.startedAt else { return }

        cancelPendingTimer()
        armedPressStartedAt = press.startedAt

        let fireDate = CFAbsoluteTimeGetCurrent() + engine.settings.startDragTimeout
        let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault,
            fireDate,
            0, // one-shot
            0,
            0
        ) { [weak self] _ in
            self?.startDragTimeoutFired()
        }
        pendingTimer = timer
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
    }

    private func cancelPendingTimer() {
        if let pendingTimer {
            CFRunLoopTimerInvalidate(pendingTimer)
        }
        pendingTimer = nil
        armedPressStartedAt = nil
    }

    private func startDragTimeoutFired() {
        pendingTimer = nil
        let armed = armedPressStartedAt
        armedPressStartedAt = nil

        let decision = engine.startDragTimeoutFired(
            now: MonotonicClock.now,
            expectingPressStartedAt: armed
        )
        perform(decision.effect)
        updateSnapshot(with: decision.effect, state: decision.state, isTimeout: true)
    }

    // MARK: - Snapshot

    private func updateSnapshot(
        with effect: EngineEffect,
        state: EngineState,
        isTimeout: Bool = false
    ) {
        snapshotLock.withLock {
            var next = snapshotStorage
            next.eventCount += 1
            next.stateName = state.name
            next.tapStatus = Self.describe(tap.status)
            if isTimeout { next.timeoutCount += 1 }
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
        // Stamp with our own monotonic clock rather than `event.timestamp`: see
        // `MonotonicClock` for why the Quartz timestamp must not be mixed with other clocks.
        let timestamp = MonotonicClock.now

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
