import CoreGraphics
import Foundation

/// Everything a command may need to know about the gesture that triggered it.
///
/// These become the `WG_*` environment variables that shell-script commands can read, matching
/// the set the original app exposes.
public struct WGActionContext: Sendable, Equatable {
    public var targetPID: Int32?
    public var targetBundleIdentifier: String?
    public var targetExecutablePath: String?
    public var targetWindowID: Int?
    public var targetAppName: String?
    public var targetWindowName: String?
    /// Where the gesture started, in global screen coordinates.
    public var gestureStart: CGPoint
    /// Height of the gesture's screen, used for the flipped y variable.
    public var screenHeight: CGFloat

    public init(
        targetPID: Int32? = nil,
        targetBundleIdentifier: String? = nil,
        targetExecutablePath: String? = nil,
        targetWindowID: Int? = nil,
        targetAppName: String? = nil,
        targetWindowName: String? = nil,
        gestureStart: CGPoint = .zero,
        screenHeight: CGFloat = 0
    ) {
        self.targetPID = targetPID
        self.targetBundleIdentifier = targetBundleIdentifier
        self.targetExecutablePath = targetExecutablePath
        self.targetWindowID = targetWindowID
        self.targetAppName = targetAppName
        self.targetWindowName = targetWindowName
        self.gestureStart = gestureStart
        self.screenHeight = screenHeight
    }

    /// The variable names come from the original app's localisation table.
    public func environment() -> [String: String] {
        var environment: [String: String] = [:]
        if let targetPID { environment["WG_TARGET_PID"] = String(targetPID) }
        if let targetBundleIdentifier { environment["WG_TARGET_BUNDLE"] = targetBundleIdentifier }
        if let targetExecutablePath { environment["WG_TARGET_EXE"] = targetExecutablePath }
        if let targetWindowID { environment["WG_TARGET_WID"] = String(targetWindowID) }
        if let targetAppName { environment["WG_TARGET_APP_NAME"] = targetAppName }
        if let targetWindowName { environment["WG_TARGET_WIN_NAME"] = targetWindowName }
        environment["WG_MOUSE_X"] = String(Int(gestureStart.x))
        environment["WG_MOUSE_Y"] = String(Int(gestureStart.y))
        if screenHeight > 0 {
            environment["WG_MOUSE_Y_FLIP"] = String(Int(screenHeight - gestureStart.y))
        }
        return environment
    }
}
