import Foundation

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

    /// Tap-thread confined; call `reset()` when a new tap is installed.
    private var timeouts: [TimeInterval] = []

    public init(maxTimeouts: Int = 3, window: TimeInterval = 60) {
        self.maxTimeouts = maxTimeouts
        self.window = window
    }

    /// How many timeouts are currently inside the window.
    public var recentTimeoutCount: Int { timeouts.count }

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
