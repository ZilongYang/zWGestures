import Foundation

/// A 手势修饰键 the editor can add to a gesture: an extra button press or a wheel movement
/// performed while the stroke is drawn.
///
/// WGestures stores these as `KeyDownStep`s **after** the stroke, and the recogniser requires every
/// declared one to have actually happened (`GestureRecognizer.areModifiersSatisfied`). That is what
/// lets one trajectory carry several commands: `拷贝` and `剪切` are both an up-stroke, and only the
/// extra left-button press picks `剪切`.
///
/// **Horizontal wheel movement is deliberately absent.** The recogniser compares a
/// `HSCROLL:±n` modifier against the *vertical* delta (`areModifiersSatisfied` matches every scroll
/// token against `deltaY`), so a left/right modifier would be satisfied by scrolling up or down —
/// offering it would create gestures that fire for the wrong input. See `docs/ROADMAP.md` §7.
public enum WGModifierKind: Hashable, CaseIterable, Sendable {
    case mouseButton(MouseButton)
    /// Wheel up / down, stored as `VSCROLL:±1`.
    case scrollUp
    case scrollDown

    /// Every kind the editor offers, in menu order.
    public static var allCases: [WGModifierKind] {
        MouseButton.allCases.map(WGModifierKind.mouseButton) + [.scrollUp, .scrollDown]
    }

    /// The `Key` string written into the configuration.
    ///
    /// The scroll magnitude is `1`, which is what the reference configuration contains
    /// (`VSCROLL:1` / `VSCROLL:-1`). Only the sign is compared when matching — the real bucketing of
    /// larger values is still unverified (ROADMAP §7) — so the smallest value is the honest choice.
    public var key: String {
        switch self {
        case .mouseButton(let button):
            button.legacyToken
        case .scrollUp:
            "VSCROLL:1"
        case .scrollDown:
            "VSCROLL:-1"
        }
    }

    public var localizedName: String {
        switch self {
        case .mouseButton(let button):
            button.localizedName
        case .scrollUp:
            "向上滚动"
        case .scrollDown:
            "向下滚动"
        }
    }

    /// Parses a stored `KeyDownStep` key back into a kind, or `nil` when it is something the editor
    /// does not offer (a horizontal scroll, or a keyboard modifier no gesture uses).
    public init?(key: String) {
        switch WGInputToken(key: key) {
        case .mouse(let button):
            self = .mouseButton(button)
        case .verticalScroll(let value):
            self = value > 0 ? .scrollUp : .scrollDown
        case .horizontalScroll, .key:
            return nil
        }
    }

    /// The step as stored in the gesture.
    public var step: WGStep {
        .keyDown(WGKeyDownStep(key: key))
    }
}
