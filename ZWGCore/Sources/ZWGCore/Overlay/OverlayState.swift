import CoreGraphics
import Foundation

/// What the on-screen trail should be showing right now.
///
/// Published by the input coordinator for the overlay to draw; deliberately a plain value so it
/// can be passed across threads safely.
public struct OverlayState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Nothing to draw.
        case idle
        /// A stroke is being drawn.
        case drawing
        /// The stroke finished and matched a gesture.
        case matched
        /// The stroke finished and matched nothing.
        case unmatched
    }

    public var phase: Phase = .idle
    /// The trajectory in global screen coordinates.
    public var points: [CGPoint] = []
    /// Name to show, when the gesture matched.
    public var gestureName: String?
    /// Increments once per finished stroke, so the overlay can tell a new one from a redraw.
    public var completionSequence: Int = 0

    public init(
        phase: Phase = .idle,
        points: [CGPoint] = [],
        gestureName: String? = nil,
        completionSequence: Int = 0
    ) {
        self.phase = phase
        self.points = points
        self.gestureName = gestureName
        self.completionSequence = completionSequence
    }

    public var isEmpty: Bool { points.isEmpty }
}

/// The visually configurable parts, taken straight from `prefs.json`.
public struct OverlayStyle: Sendable, Equatable {
    public var showPath: Bool
    public var showGestureName: Bool
    public var pathColorNormal: WGColor
    public var pathColorRecognized: WGColor
    public var labelColorNormal: WGColor
    public var labelColorExecuted: WGColor
    public var lineWidth: Double
    /// Vertical position of the gesture-name label, as a fraction of the screen height.
    public var gesturePosition: Double

    public init(
        showPath: Bool = true,
        showGestureName: Bool = true,
        pathColorNormal: WGColor = WGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.77),
        pathColorRecognized: WGColor = WGColor(red: 0.125, green: 0.84, blue: 0.59, alpha: 0.9),
        labelColorNormal: WGColor = WGColor(red: 0.38, green: 0.38, blue: 0.38, alpha: 0.5),
        labelColorExecuted: WGColor = WGColor(red: 0.125, green: 0.84, blue: 0.59, alpha: 0.9),
        lineWidth: Double = 2.25,
        gesturePosition: Double = 0.25
    ) {
        self.showPath = showPath
        self.showGestureName = showGestureName
        self.pathColorNormal = pathColorNormal
        self.pathColorRecognized = pathColorRecognized
        self.labelColorNormal = labelColorNormal
        self.labelColorExecuted = labelColorExecuted
        self.lineWidth = lineWidth
        self.gesturePosition = gesturePosition
    }

    /// Builds a style from the imported preferences, falling back to the defaults for any
    /// colour that cannot be parsed.
    public init(preferences: WGPreferences) {
        let defaults = OverlayStyle()
        self.init(
            showPath: preferences.showPath,
            showGestureName: preferences.showGestureName,
            pathColorNormal: WGColor(hex: preferences.pathColorNormal) ?? defaults.pathColorNormal,
            pathColorRecognized: WGColor(hex: preferences.pathColorRecognized) ?? defaults.pathColorRecognized,
            labelColorNormal: WGColor(hex: preferences.labelColorNormal) ?? defaults.labelColorNormal,
            labelColorExecuted: WGColor(hex: preferences.labelColorExecuted) ?? defaults.labelColorExecuted,
            lineWidth: preferences.pathLineWidth,
            gesturePosition: preferences.gesturePos
        )
    }

    /// Where the label sits vertically on a screen of `screenHeight` points, measured from the
    /// top. `gesturePosition` 0 is the very top, 1 is the very bottom.
    public func labelCenterY(screenHeight: CGFloat) -> CGFloat {
        let clamped = min(max(gesturePosition, 0), 1)
        return screenHeight * clamped
    }
}
