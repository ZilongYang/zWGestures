import AppKit
import Foundation

/// The emergency-stop shortcut.
///
/// If the engine ever swallows a button press and fails to hand it back, the left mouse button
/// becomes useless. This shortcut stops the engine and releases everything, so the user always has
/// a way out. ⌃⌥⌘⎋ is deliberately close to the system's force-quit shortcut but distinct from it.
///
/// **Detected with `NSEvent` monitors, never through the event tap.** Putting the keyboard into the
/// tap's `.defaultTap` mask made this app part of the synchronous path of *every* keystroke on the
/// machine; when the callback missed the system's deadline, typing stopped working system-wide and
/// the only way out was a forced power-off. Monitors are listen-only by construction — they can
/// observe a key press but can never consume one.
///
/// Lives in ZWGCore, next to the rest of the testable logic: an escape hatch is worth testing.
public enum PanicShortcut {
    public static let displayName = "⌃⌥⌘⎋"

    /// `kVK_Escape`
    static let escapeKeyCode: UInt16 = 53

    /// Matches on primitives so the check can run from a non-isolated monitor callback without
    /// sending a non-`Sendable` `NSEvent` across an actor boundary.
    ///
    /// ⇧ is part of the mask on purpose: ⌃⌥⌘⇧⎋ must **not** fire this, so a fat-fingered reach for
    /// the system's force-quit shortcut cannot silently stop the engine instead.
    public static func matches(keyCode: UInt16, modifierFlags: UInt) -> Bool {
        guard keyCode == escapeKeyCode else { return false }
        let interesting = NSEvent.ModifierFlags(rawValue: modifierFlags)
            .intersection([.control, .option, .command, .shift])
        return interesting == [.control, .option, .command]
    }
}
