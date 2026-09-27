import CoreGraphics
import Foundation

/// Finds the window under a point using the window server.
///
/// `CGWindowListCopyWindowInfo` is safe to call from the event-tap thread, which matters: the
/// target has to be resolved synchronously while the gesture is being recognised, and hopping
/// to the main thread there would stall input handling.
enum WindowProbe {
    struct Result: Sendable, Equatable {
        var pid: Int32
        var windowID: Int?
        /// True when the point is over the desktop rather than a normal window.
        var isDesktop: Bool
    }

    static func probe(at point: CGPoint) -> Result? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]]
        else { return nil }

        // The window server returns windows front to back, so the first normal-layer window
        // containing the point is the one the user sees there.
        var desktopFallback: Result?

        for info in list {
            guard let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.contains(point)
            else { continue }

            guard let pidValue = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pidValue.int32Value
            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.intValue
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0

            if layer == 0 {
                return Result(pid: pid, windowID: windowID, isDesktop: false)
            }

            // The desktop sits below the normal layer; Finder owns it.
            if desktopFallback == nil, layer < 0 {
                desktopFallback = Result(pid: pid, windowID: windowID, isDesktop: true)
            }
        }

        return desktopFallback
    }
}
