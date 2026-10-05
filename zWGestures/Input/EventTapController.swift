import CoreGraphics
import Foundation

/// Installs and maintains a `CGEventTap` on its own thread.
///
/// Design notes:
///
/// - The tap runs on a dedicated thread with its own run loop, so it is never blocked by
///   main-thread UI work. Blocking an event tap is what makes the whole system feel like
///   the mouse has frozen.
/// - macOS disables event taps when the callback takes too long (`tapDisabledByTimeout`)
///   or when the user input state changes (`tapDisabledByUserInput`). Noticing and
///   recovering from that is the single most important robustness property here — it is the
///   known root cause of WGestures' "mouse freezes" reports.
/// - **The tap deliberately does not capture keyboard events.** A `.defaultTap` sits in the
///   synchronous path of every event it is interested in, and keyboard events cannot be
///   coalesced the way pointer motion can, so a callback that misses the system's deadline makes
///   typing impossible machine-wide while the mouse still partly works. Owning the keyboard is
///   not worth that risk: the emergency-stop shortcut uses listen-only `NSEvent` monitors
///   instead (see `PanicShortcut`).
/// - **A chronically slow callback is a failure, not something to retry forever.** Re-enabling
///   the tap the instant the system disables it drags the system straight back into the slow tap.
///   A `tapDisabledByTimeout` therefore backs off before retrying and, after `maxTimeouts` inside
///   `timeoutWindow`, takes the tap down and reports it. `tapDisabledByUserInput` is **not** a
///   slowness signal — `EventTapHealthPolicy.action(for:at:)` re-enables it immediately, as the app
///   did before the freeze fix, so a gesture never pauses for half a second for no reason.
/// - Every piece of gesture logic runs on the tap thread. `performOnTapThread` is the only
///   supported way to touch that state from elsewhere, which is what lets `InputEngine`
///   stay lock-free.
final class EventTapController: @unchecked Sendable {
    enum Status: Equatable {
        case stopped
        case running
        case systemDisabled
        /// The callback kept missing the system's deadline, so the tap was taken down on purpose.
        ///
        /// Distinct from `.failed` because it must **not** be retried automatically: retrying is
        /// exactly what makes the whole system's input unusable.
        case gaveUp(timeoutCount: Int)
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .running, .systemDisabled: true
            case .stopped, .gaveUp, .failed: false
            }
        }

        /// Whether the tap stopped for a reason worth reporting to the user.
        var isFailed: Bool {
            switch self {
            case .gaveUp, .failed: true
            case .stopped, .running, .systemDisabled: false
            }
        }
    }

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var statusStorage: Status = .stopped

    /// Tap-thread only: how often the system has disabled the tap for being too slow.
    private var health = EventTapHealthPolicy()
    /// Tap-thread only: a re-enable that is waiting out the backoff.
    private var reenableTimer: CFRunLoopTimer?

    /// Signalled once the previous tap thread has fully torn down. `start()` waits on it so
    /// that a quick pause/resume pair cannot race with the old thread's cleanup.
    private var threadFinished: DispatchSemaphore?

    /// Handles one event on the tap thread. Returning `nil` swallows the event.
    /// Set this before calling `start()`, then leave it alone.
    var handler: (@Sendable (CGEvent) -> CGEvent?)?

    /// Called on the tap thread right after the system disabled the tap.
    var onSystemDisable: (@Sendable () -> Void)?

    /// Called on the tap thread when the tap has been torn down because the callback kept missing
    /// the system's deadline. The argument is how many timeouts were seen.
    ///
    /// Separate from `onSystemDisable` on purpose: that one means "we are recovering", this one
    /// means "we have stopped, and the user has to be told".
    var onGiveUp: (@Sendable (Int) -> Void)?

    /// Called on the tap thread just before it exits, so that owners can release
    /// run-loop-bound resources (timers, sources) from the thread that owns them.
    var onTapThreadTeardown: (@Sendable () -> Void)?

    var status: Status { lock.withLock { statusStorage } }

    /// Pointer and scroll events only — see `EventTapMask` for why the keyboard is excluded, and
    /// for the test that keeps it that way.
    static let eventMask: CGEventMask = EventTapMask.mask

    // MARK: - Lifecycle

    /// Starts the tap thread.
    /// - Returns: whether the tap was installed. `false` almost always means the process
    ///   lacks the Accessibility permission.
    ///
    /// A previous failure is retryable: the usual cause is a missing Accessibility grant, which
    /// the user may have just given.
    @discardableResult
    func start() -> Bool {
        if lock.withLock({ statusStorage.isRunning }) {
            return true
        }

        // Make sure the previous tap thread has released the run loop and the mach port.
        if let finished = lock.withLock({ threadFinished }) {
            _ = finished.wait(timeout: .now() + 2)
            lock.withLock { threadFinished = nil }
        }

        lock.withLock { statusStorage = .stopped }

        let ready = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                finished.signal()
                return
            }
            self.health.reset()
            let installed = self.installTapOnCurrentThread()
            ready.signal()
            if installed {
                CFRunLoopRun()
            }
            self.removeTapOnCurrentThread()
            finished.signal()
        }
        thread.name = "io.github.zilongyang.zwgestures.eventtap"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 512 * 1024
        lock.withLock { threadFinished = finished }
        thread.start()

        ready.wait()
        return status.isRunning
    }

    /// Stops the tap thread and tears the tap down. Safe to call from any thread.
    func stop() {
        let runLoop = lock.withLock { self.runLoop }
        guard let runLoop else { return }
        CFRunLoopStop(runLoop)
    }

    /// Runs `block` on the tap thread, where the gesture engine lives.
    func performOnTapThread(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop = lock.withLock({ self.runLoop }) else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: - Tap thread only

    private func installTapOnCurrentThread() -> Bool {
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            lock.withLock { statusStorage = .failed("CGEvent.tapCreate 返回 nil（通常是没有辅助功能权限）") }
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            lock.withLock { statusStorage = .failed("CFMachPortCreateRunLoopSource 失败") }
            return false
        }

        lock.withLock {
            self.tap = tap
            self.source = source
            self.runLoop = CFRunLoopGetCurrent()
            self.statusStorage = .running
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.input.notice("event tap installed")
        return true
    }

    private func removeTapOnCurrentThread() {
        onTapThreadTeardown?()

        if let reenableTimer = lock.withLock({ self.reenableTimer }) {
            CFRunLoopTimerInvalidate(reenableTimer)
            lock.withLock { self.reenableTimer = nil }
        }

        let (tap, source) = lock.withLock { (self.tap, self.source) }

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }

        lock.withLock {
            self.tap = nil
            self.source = nil
            self.runLoop = nil
            // Keep a failure reason so the menu can explain why the engine is off. Only a clean
            // teardown resets to `.stopped`.
            if !self.statusStorage.isFailed {
                self.statusStorage = .stopped
            }
        }
        Log.input.notice("event tap removed")
    }

    // MARK: - Event handling

    fileprivate func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            let reason: EventTapDisableReason = type == .tapDisabledByTimeout ? .timeout : .userInput
            Log.input.error("""
                event tap disabled by system \
                (type \(type.rawValue, privacy: .public), \
                \(reason == .timeout ? "timeout" : "user input", privacy: .public))
                """)
            lock.withLock { statusStorage = .systemDisabled }
            switch health.action(for: reason, at: CFAbsoluteTimeGetCurrent()) {
            case .reEnableNow:
                // The system did not disable us for being slow (user input does this on its own),
                // so put the tap back at once. Waiting out the backoff here is what made gestures
                // feel sticky after the 2026-09-29 freeze fix.
                reenableNow()
            case .reEnableAfterBackoff(let delay):
                scheduleReenable(after: delay)
            case .giveUp(let count):
                giveUp(timeoutCount: count)
                return nil
            }
            onSystemDisable?()
            return nil
        default:
            break
        }

        if let handler, let output = handler(event) {
            return Unmanaged.passUnretained(output)
        }
        return nil
    }

    /// Records that the callback has missed the system's deadline too often and stops the tap.
    ///
    /// Runs on the tap thread inside the callback, so it must not block — and it deliberately does
    /// not re-enable anything. Leaving the run loop tears the tap down via
    /// `removeTapOnCurrentThread`, which preserves the `.gaveUp` status.
    private func giveUp(timeoutCount count: Int) {
        Log.input.error("""
            事件拦截器在 \(Int(self.health.window), privacy: .public) 秒内超时 \
            \(count, privacy: .public) 次，主动停用以免拖慢系统输入
            """)
        lock.withLock { statusStorage = .gaveUp(timeoutCount: count) }
        onGiveUp?(count)
        if let runLoop = lock.withLock({ self.runLoop }) {
            CFRunLoopStop(runLoop)
        }
    }

    /// Re-enables the tap immediately, cancelling any pending backoff.
    private func reenableNow() {
        cancelReenable()
        let tap = lock.withLock { self.tap }
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.withLock { statusStorage = .running }
    }

    private func cancelReenable() {
        if let pending = lock.withLock({ reenableTimer }) {
            CFRunLoopTimerInvalidate(pending)
            lock.withLock { reenableTimer = nil }
        }
    }

    /// Re-enables the tap after the backoff rather than immediately.
    private func scheduleReenable(after delay: TimeInterval) {
        cancelReenable()

        let fireDate = CFAbsoluteTimeGetCurrent() + delay
        let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault,
            fireDate,
            0, // one-shot
            0,
            0
        ) { [weak self] _ in
            self?.reenableAfterSystemDisable()
        }
        lock.withLock { reenableTimer = timer }
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
    }

    private func reenableAfterSystemDisable() {
        lock.withLock { reenableTimer = nil }

        let (tap, status) = lock.withLock { (self.tap, self.statusStorage) }
        // Nothing to re-enable if we were torn down or gave up while the backoff was pending.
        guard let tap, !status.isFailed else { return }

        CGEvent.tapEnable(tap: tap, enable: true)
        lock.withLock { statusStorage = .running }
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.process(type: type, event: event)
}
