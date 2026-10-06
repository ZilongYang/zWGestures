import Foundation

/// The input combination that starts a gesture, reduced to something comparable.
///
/// WGestures' 触发方式 panel is a matrix of these: 右键, 屏幕上边缘 + 滚轮, 左上角 + 中键, and so
/// on. A gesture may only fire if the matrix says its trigger is enabled, which is how a user
/// turns off, say, every top-edge gesture without deleting them.
public struct WGTriggerSignature: Hashable, Sendable {
    public enum Token: Hashable, Sendable {
        case mouse(MouseButton)
        /// `direction` is -1, 0 or 1; magnitude is not part of the identity.
        case scroll(isHorizontal: Bool, direction: Int)
        case edge(WGEdgeCornerMask)
    }

    public var tokens: [Token]

    public init(tokens: [Token]) {
        self.tokens = tokens
    }

    public var isEmpty: Bool { tokens.isEmpty }

    public var description: String {
        tokens.map(Self.describe).joined(separator: " + ")
    }

    static func describe(_ token: Token) -> String {
        switch token {
        case .mouse(let button):
            return button.legacyToken
        case .edge(let mask):
            return mask.localizedName
        case .scroll(let isHorizontal, let direction):
            let arrow = direction > 0 ? "↓" : (direction < 0 ? "↑" : "")
            return (isHorizontal ? L10n.text(.triggerHorizontalScroll) : L10n.text(.triggerScroll)) + arrow
        }
    }

    /// Whether `self` is a leading part of `other` — the matrix row `[右键]` covers the
    /// signature `[右键, 滚轮↑]`.
    ///
    /// A matrix row's scroll token carries **no direction**: the original writes
    /// `{"$type":"ScrollStep","IsHorizontal":false}`, so `上边缘 + 滚轮` is one row covering both
    /// directions, while the gesture definitions are the ones that distinguish 音量+ from 音量−.
    /// A row token with direction 0 therefore matches any direction.
    public func isPrefix(of other: WGTriggerSignature) -> Bool {
        guard tokens.count <= other.tokens.count else { return false }
        return zip(tokens, other.tokens).allSatisfy(Self.rowTokenMatches)
    }

    private static func rowTokenMatches(_ rowToken: Token, _ gestureToken: Token) -> Bool {
        switch (rowToken, gestureToken) {
        case (.scroll(let rowAxis, let rowDirection), .scroll(let axis, let direction)):
            return rowAxis == axis && (rowDirection == 0 || rowDirection == direction)
        default:
            return rowToken == gestureToken
        }
    }
}

public struct WGTriggerRow: Sendable, Equatable {
    public var signature: WGTriggerSignature
    public var enabled: Bool

    public init(signature: WGTriggerSignature, enabled: Bool) {
        self.signature = signature
        self.enabled = enabled
    }
}

extension WGTriggerSignature {
    /// Builds a signature from the steps that lead up to the stroke.
    ///
    /// Returns `nil` when a step cannot be interpreted, in which case the caller should not gate
    /// on the matrix rather than guess.
    public static func make(from steps: [WGStep]) -> WGTriggerSignature? {
        var tokens: [Token] = []
        for step in steps {
            switch step {
            case .keyDown(let key):
                let token = WGInputToken(key: key.key)
                switch token {
                case .mouse(let button):
                    tokens.append(.mouse(button))
                case .verticalScroll(let value):
                    tokens.append(.scroll(isHorizontal: false, direction: sign(of: value)))
                case .horizontalScroll(let value):
                    tokens.append(.scroll(isHorizontal: true, direction: sign(of: value)))
                case .key:
                    // Keyboard triggers are not modelled yet.
                    return nil
                }
            case .moveToEdgeCorner(let edge):
                guard edge.edgeCorner.mask.isValid else { return nil }
                tokens.append(.edge(edge.edgeCorner.mask))
            case .scroll(let scroll):
                tokens.append(.scroll(isHorizontal: scroll.isHorizontal, direction: 0))
            case .stroke, .unknown:
                return nil
            }
        }
        return WGTriggerSignature(tokens: tokens)
    }

    private static func sign(of value: Int) -> Int {
        value == 0 ? 0 : (value > 0 ? 1 : -1)
    }
}

/// The effective trigger matrix for a target.
public struct WGTriggerMatrix: Sendable, Equatable {
    public var rows: [WGTriggerRow]
    /// True when this came from the target itself rather than being inherited.
    public var isOverridden: Bool

    public init(rows: [WGTriggerRow], isOverridden: Bool) {
        self.rows = rows
        self.isOverridden = isOverridden
    }

    public static let empty = WGTriggerMatrix(rows: [], isOverridden: false)

    /// A target with its own rows overrides the general matrix; an empty list inherits it.
    /// (WGestures calls this 继承; the on-disk format only ever records true/false per row.)
    public static func effective(for target: WGTarget, inheriting general: WGTarget) -> WGTriggerMatrix {
        if target.triggers.isEmpty {
            return WGTriggerMatrix(rows: general.triggers.map(row(from:)), isOverridden: false)
        }
        return WGTriggerMatrix(rows: target.triggers.map(row(from:)), isOverridden: true)
    }

    /// Whether the matrix permits a gesture that starts with `signature`.
    ///
    /// The **longest** matching row wins, so a specific `上边缘 + 滚轮` row can be turned off
    /// while plain `上边缘` stays on. When nothing matches, the gesture is allowed: the shipped
    /// matrices are written to describe the gestures the app ships with, and silently disabling
    /// a gesture because its trigger is not listed would be worse than allowing it.
    public func allows(_ signature: WGTriggerSignature) -> Bool {
        guard !rows.isEmpty else { return true }

        var best: WGTriggerRow?
        for row in rows where row.signature.isPrefix(of: signature) {
            if best == nil || row.signature.tokens.count > best!.signature.tokens.count {
                best = row
            }
        }
        return best?.enabled ?? true
    }

    private static func row(from trigger: WGTrigger) -> WGTriggerRow {
        WGTriggerRow(
            signature: WGTriggerSignature.make(from: trigger.def) ?? WGTriggerSignature(tokens: []),
            enabled: trigger.enabled
        )
    }
}
