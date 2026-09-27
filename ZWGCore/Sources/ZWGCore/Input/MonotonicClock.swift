import Foundation

/// One monotonic clock for everything the gesture engine measures.
///
/// `CGEvent.timestamp` is **not** on the same time base as `mach_absolute_time()`: subtracting
/// one from the other silently produces a duration that is off by the CPU timebase ratio
/// (41.67× on Apple Silicon), which is how the start-drag timeout once ended up scheduled
/// roughly two weeks into the future. Pointer events are therefore stamped with this clock as
/// they are delivered, and every duration the engine computes compares like with like.
public enum MonotonicClock {
    /// Seconds since boot. Monotonic, unaffected by wall-clock adjustments.
    public static var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
