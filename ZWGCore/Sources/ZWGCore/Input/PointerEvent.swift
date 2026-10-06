import CoreGraphics
import Foundation

/// Mouse buttons. Raw values match `CGMouseButton` and the `MOUSE:n` keys used by
/// WGestures configuration files (`0` = left, `1` = right, `2` = centre).
public enum MouseButton: Int, Sendable, CaseIterable, Codable {
    case left = 0
    case right = 1
    case center = 2
    case side1 = 3
    case side2 = 4

    /// The `MOUSE:n` token used in WGestures gesture definitions.
    public var legacyToken: String { "MOUSE:\(rawValue)" }

    public init?(legacyToken: String) {
        guard legacyToken.hasPrefix("MOUSE:"),
              let value = Int(legacyToken.dropFirst("MOUSE:".count)),
              let button = MouseButton(rawValue: value)
        else { return nil }
        self = button
    }

    public var localizedName: String {
        switch self {
        case .left: L10n.text(.displayMouseLeft)
        case .right: L10n.text(.displayMouseRight)
        case .center: L10n.text(.displayMouseCenter)
        case .side1: L10n.text(.displayMouseSide1)
        case .side2: L10n.text(.displayMouseSide2)
        }
    }
}

/// A pointer event reduced to the information the gesture engine needs.
///
/// Locations use the CoreGraphics global coordinate space (origin at the top-left of the
/// primary display, y increasing downwards), which is what `CGEvent.location` provides.
public struct PointerEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case down(MouseButton)
        case up(MouseButton)
        case drag(MouseButton)
        case move
        case scroll(deltaX: Double, deltaY: Double)
    }

    public var kind: Kind
    public var location: CGPoint
    public var timestamp: TimeInterval

    public init(kind: Kind, location: CGPoint, timestamp: TimeInterval) {
        self.kind = kind
        self.location = location
        self.timestamp = timestamp
    }

    /// The button this event belongs to, if any.
    public var button: MouseButton? {
        switch kind {
        case .down(let button), .up(let button), .drag(let button): button
        case .move, .scroll: nil
        }
    }

    /// True when this event is a press, a release or a drag of `button`.
    public func belongsTo(_ button: MouseButton) -> Bool {
        self.button == button
    }
}
