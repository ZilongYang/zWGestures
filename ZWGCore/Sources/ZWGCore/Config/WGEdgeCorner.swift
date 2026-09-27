import Foundation

/// Decodes the `EdgeCorner.Value` bit mask used by `MoveToEdgeCornerStep`.
///
/// ⚠️ **The exact mapping is not yet confirmed against the original app.** What *is* derived
/// from data is the structure: the four single-bit values 1, 2, 4 and 8 are the screen edges,
/// and every observed corner value (3, 6, 12, 9) is the bitwise OR of two *adjacent* edges
/// (1|2, 2|4, 4|8, 8|1). That fixes the cyclic order top → right → bottom → left, but leaves
/// two mirror-image interpretations; this file picks one. `docs/ROADMAP.md` tracks the
/// experiment that will settle it, and `make`ing the change here is all that is needed.
public struct WGEdgeCornerMask: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let top = WGEdgeCornerMask(rawValue: 1)
    public static let right = WGEdgeCornerMask(rawValue: 2)
    public static let bottom = WGEdgeCornerMask(rawValue: 4)
    public static let left = WGEdgeCornerMask(rawValue: 8)

    public static let allEdges: WGEdgeCornerMask = [.top, .right, .bottom, .left]

    /// The four single-bit edges, as a list.
    public static let edges: [WGEdgeCornerMask] = [.top, .right, .bottom, .left]

    /// The four corners: each is two *adjacent* edges, in the cyclic order
    /// top → right → bottom → left.
    public static let corners: [WGEdgeCornerMask] = [
        [.top, .right],
        [.right, .bottom],
        [.bottom, .left],
        [.top, .left],
    ]

    /// A single edge.
    public var isEdge: Bool { WGEdgeCornerMask.edges.contains(self) }

    /// Two adjacent edges meeting at a corner.
    public var isCorner: Bool { WGEdgeCornerMask.corners.contains(self) }

    /// True for a real edge or corner. Combinations such as top + bottom are rejected.
    public var isValid: Bool { isEdge || isCorner }

    public var localizedName: String {
        switch self {
        case .top: "屏幕上边缘"
        case .bottom: "屏幕下边缘"
        case .left: "屏幕左边缘"
        case .right: "屏幕右边缘"
        case [.top, .left]: "屏幕左上角"
        case [.top, .right]: "屏幕右上角"
        case [.bottom, .left]: "屏幕左下角"
        case [.bottom, .right]: "屏幕右下角"
        default: "未知边角(\(rawValue))"
        }
    }

    /// Whether the mask contains `other` entirely.
    public func contains(_ other: WGEdgeCornerMask) -> Bool {
        intersection(other) == other
    }
}

extension WGEdgeCorner {
    public var mask: WGEdgeCornerMask { WGEdgeCornerMask(rawValue: value) }
}
