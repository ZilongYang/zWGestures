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
///   recovering from that immediately is the single most important robustness property
///   here — it is the known root cause of WGestures' "mouse freezes" reports.
/// - Every piece of gesture logic runs on the tap thread. `performOnTapThread` is the only
///   supported way to touch that state from elsewhere, which is what lets `InputEngine`
///   stay lock-free.
final class EventTapController: @unchecked Sendable {
    enum Status: Equatable {
        case stopped
        case running
        case systemDisabled
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .running, .systemDisabled: true
            case .stopped, .failed: false
            }
        }
    }

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var statusStorage: Status = .stopped

    /// Signalled once the previous tap thread has fully torn down. `start()` waits on it so
    /// that a quick pause/resume pair cannot race with the old thread's cleanup.
    private var threadFinished: DispatchSemaphore?

    /// Handles one event on the tap thread. Returning `nil` swallows the event.
    /// Set this before calling `start()`, then leave it alone.
    var handler: (@Sendable (CGEvent) -> CGEvent?)?

    /// Called on the tap thread right after the system disabled the tap.
    var onSystemDisable: (@Sendable () -> Void)?

    /// Called on the tap thread just before it exits, so that owners can release
    /// run-loop-bound resources (timers, sources) from the thread that owns them.
    var onTapThreadTeardown: (@Sendable () -> Void)?

    var status: Status { lock.withLock { statusStorage } }

    /// Mouse, scroll and keyboard events.
    ///
    /// Keyboard events are tapped so the emergency-stop shortcut keeps working while a
    /// gesture is in flight, and because keyboard gesture modifiers are on the roadmap.
    static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved,
            .scrollWheel,
            .keyDown,
        ]
        return types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }()

    // MARK: - Lifecycle

    /// Starts the tap thread.
    /// - Returns: whether the tap was installed. `false` almost always means the process
    ///   lacks the Accessibility permission.
    @discardableResult
    func start() -> Bool {
        guard lock.withLock({ statusStorage }) == .stopped else {
            return status.isRunning
        }

        // Make sure the previous tap thread has released the run loop and the mach port.
        if let finished = lock.withLock({ threadFinished }) {
            _ = finished.wait(timeout: .now() + 2)
            lock.withLock { threadFinished = nil }
        }

        let ready = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                finished.signal()
                return
            }
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
            self.statusStorage = .stopped
        }
        Log.input.notice("event tap removed")
    }

    // MARK: - Event handling

    fileprivate func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Log.input.error("event tap disabled by system (type \(type.rawValue, privacy: .public)); re-enabling")
            lock.withLock { statusStorage = .systemDisabled }
            if let tap = lock.withLock({ self.tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
                lock.withLock { statusStorage = .running }
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
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.process(type: type, event: event)
}
