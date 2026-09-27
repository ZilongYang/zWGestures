import Foundation

/// A typed view of the `Key` strings used by `KeyDownStep`.
///
/// Examples seen in real configurations: `MOUSE:1`, `MOUSE:0`, `VSCROLL:-13`, `VSCROLL:12`.
/// Anything else is preserved as a keyboard key name such as `Command` or `ANSI_C`.
public enum WGInputToken: Equatable, Sendable {
    case mouse(MouseButton)
    /// Vertical scroll, as the raw value the original app recorded (e.g. `-13`).
    case verticalScroll(Int)
    case horizontalScroll(Int)
    case key(String)

    private static let mousePrefix = "MOUSE:"
    private static let verticalScrollPrefix = "VSCROLL:"
    private static let horizontalScrollPrefix = "HSCROLL:"

    public init(key: String) {
        if key.hasPrefix(Self.mousePrefix), let button = MouseButton(legacyToken: key) {
            self = .mouse(button)
            return
        }
        if key.hasPrefix(Self.verticalScrollPrefix),
           let value = Int(key.dropFirst(Self.verticalScrollPrefix.count))
        {
            self = .verticalScroll(value)
            return
        }
        if key.hasPrefix(Self.horizontalScrollPrefix),
           let value = Int(key.dropFirst(Self.horizontalScrollPrefix.count))
        {
            self = .horizontalScroll(value)
            return
        }
        self = .key(key)
    }

    public var isMouse: Bool {
        if case .mouse = self { return true }
        return false
    }

    /// `-1`, `0` or `1`.
    public var scrollDirection: Int? {
        switch self {
        case .verticalScroll(let value), .horizontalScroll(let value):
            value == 0 ? 0 : (value > 0 ? 1 : -1)
        default:
            nil
        }
    }
}
