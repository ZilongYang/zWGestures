import CoreGraphics

/// The event types the gesture tap is interested in.
///
/// Kept in ZWGCore, and asserted by tests, because the most dangerous single mistake in this app is
/// to add a keyboard type here.
///
/// A `.defaultTap` sits in the synchronous path of **every event it is interested in**: the system
/// waits for the callback to return before delivering that event. Pointer motion is coalesced, so a
/// slow callback merely degrades it. Keyboard events cannot be coalesced, so the moment a callback
/// misses the system's deadline, a tap that asked for `.keyDown` makes typing stop working
/// machine-wide — the mouse still partly works, the video keeps playing, and the only way out is a
/// forced power-off. That is exactly what happened on 2026-09-29 (see docs/ROADMAP.md); the
/// emergency-stop shortcut is watched with listen-only `NSEvent` monitors instead (see
/// `PanicShortcut`).
///
/// Pointer events are captured with `.defaultTap` rather than listen-only on purpose: suppressing
/// the press that starts a gesture, and replaying a plain click, is the whole point.
public enum EventTapMask {
    public static let types: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .mouseMoved,
        .scrollWheel,
    ]

    /// Keyboard event types that must never appear in `types`.
    ///
    /// The two `tapDisabled*` pseudo-events are absent for a different reason: a tap cannot ask for
    /// them, the system delivers them on its own.
    public static let forbiddenKeyboardTypes: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged,
    ]

    public static let mask: CGEventMask = types.reduce(CGEventMask(0)) {
        $0 | (CGEventMask(1) << CGEventMask($1.rawValue))
    }

    public static func contains(_ type: CGEventType) -> Bool {
        mask & (CGEventMask(1) << CGEventMask(type.rawValue)) != 0
    }
}
