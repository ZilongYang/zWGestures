import Darwin
import Foundation

/// Conversions between Mach absolute time and seconds.
///
/// `CGEvent.timestamp` is expressed in Mach absolute time units, whose ratio to nanoseconds
/// is not 1:1 on all hardware (Apple Silicon uses a 125/3 timebase). Comparing event
/// timestamps against `ProcessInfo.systemUptime` would therefore be wrong; both the event
/// timestamps and the engine's notion of "now" go through here instead.
public enum MachTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public static func seconds(_ ticks: UInt64) -> TimeInterval {
        let base = timebase
        guard base.denom != 0 else { return 0 }
        return Double(ticks) * Double(base.numer) / Double(base.denom) / 1_000_000_000
    }

    /// Monotonic "now", on the same scale as `CGEvent.timestamp` converted with `seconds(_:)`.
    public static var now: TimeInterval {
        seconds(mach_absolute_time())
    }
}
