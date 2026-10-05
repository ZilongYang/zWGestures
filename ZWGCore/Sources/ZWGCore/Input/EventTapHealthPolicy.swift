import Foundation

/// Why the system took the tap down. The two cases look alike in `CGEventType` terms but mean very
/// different things, and treating them the same cost the user a 0.5 s dead window every time.
public enum EventTapDisableReason: Sendable, Equatable {
    /// `tapDisabledByTimeout`: our callback missed the system's deadline. Our fault.
    case timeout
    /// `tapDisabledByUserInput`: the system disabled the tap because of user input. Says nothing
    /// about how fast the callback was.
    case userInput
}

/// What to do about a disable notification.
public enum EventTapDisableAction: Sendable, Equatable {
    /// Put the tap back immediately — what the app did before the freeze fix, and correct whenever
    /// the system did not disable us for being slow.
    case reEnableNow
    /// Wait out the backoff before re-enabling. Re-enabling a tap that just missed its deadline
    /// drags the system straight back into it.
    case reEnableAfterBackoff(TimeInterval)
    /// The callback has missed the deadline too often: stop, and tell the user.
    case giveUp(timeoutCount: Int)
}

/// Decides when a chronically slow event tap has to be abandoned.
///
/// This lives in ZWGCore because it is the safety-critical part of the tap. A `.defaultTap` sits in
/// the synchronous path of every event it is interested in, and re-enabling it the instant the
/// system disables it drags the system straight back into a tap that cannot keep up — which is how
/// a gesture tool ends up holding the whole machine's input hostage. The give-up rule is therefore
/// explicit and unit tested rather than tuned by feel.
public struct EventTapHealthPolicy: Sendable {
    /// Timeouts tolerated inside `window` before the tap is abandoned.
    public let maxTimeouts: Int
    /// How far back timeouts are counted. An occasional timeout on its own is harmless.
    public let window: TimeInterval
    /// How long a tap that missed its deadline stays down before it is tried again.
    public let backoff: TimeInterval

    /// Tap-thread confined; call `reset()` when a new tap is installed.
    private var timeouts: [TimeInterval] = []

    public init(maxTimeouts: Int = 3, window: TimeInterval = 60, backoff: TimeInterval = 0.5) {
        self.maxTimeouts = maxTimeouts
        self.window = window
        self.backoff = backoff
    }

    /// How many timeouts are currently inside the window.
    public var recentTimeoutCount: Int { timeouts.count }

    /// Works out what to do about a disable notification.
    ///
    /// Only `.timeout` counts against the health budget: it is the one signal that the callback is
    /// too slow. `.userInput` is a different code path inside the system and is re-enabled
    /// immediately, as it was before the freeze fix — making it wait out the backoff showed up as
    /// gestures feeling slightly sticky (docs/ROADMAP.md §21).
    public mutating func action(
        for reason: EventTapDisableReason,
        at now: TimeInterval
    ) -> EventTapDisableAction {
        switch reason {
        case .userInput:
            return .reEnableNow

        case .timeout:
            guard recordTimeout(at: now) else { return .reEnableAfterBackoff(backoff) }
            return .giveUp(timeoutCount: recentTimeoutCount)
        }
    }

    /// Records one `tapDisabledByTimeout` notification.
    /// - Returns: `true` when the tap has missed the system's deadline too often and must be
    ///   torn down rather than re-enabled again.
    public mutating func recordTimeout(at now: TimeInterval) -> Bool {
        timeouts.append(now)
        timeouts.removeAll { now - $0 > window }
        return timeouts.count > maxTimeouts
    }

    public mutating func reset() {
        timeouts.removeAll()
    }

    /// Why the engine switched itself off, phrased for the menu bar and the alert.
    public static func failureReason(count: Int) -> String {
        "事件拦截器连续超时 \(count) 次，已主动停用"
    }
}
