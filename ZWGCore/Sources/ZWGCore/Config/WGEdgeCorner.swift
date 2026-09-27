import Foundation

/// Decodes the `EdgeCorner.Value` bit mask used by `MoveToEdgeCornerStep`.
///
/// The mapping is confirmed against the original app's own quick-start artwork, which draws each
/// edge and corner gesture with a position marker:
///
/// | 配置值 | 手势      | 快捷入门图上的标记                  |
/// |--------|-----------|-------------------------------------|
/// | 1      | 音量+/−   | 监视器图标**顶部**的黑条 = 上边缘   |
/// | 4      | 亮度+/−   | 监视器图标**底部**的黑条 = 下边缘   |
/// | 9      | 切换任务  | 屏幕**左上角**的角括号 = 上\|左     |
/// | 8      | 终端      | 左边缘（竖环起点的方块标记）        |
/// | 2      | 活动监视器 | 右边缘（与终端构成镜像对）          |
///
/// The four single-bit values are the edges; every corner value is the OR of two *adjacent*
/// edges (3, 6, 12, 9), which is what fixes the cyclic order top → right → bottom → left.
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
