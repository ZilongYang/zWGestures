import CoreGraphics
import Foundation

/// The emergency-stop shortcut.
///
/// If the engine ever swallows a button press and fails to hand it back, the left mouse
/// button becomes useless. This shortcut stops the engine and releases everything, so the
/// user always has a way out. ⌃⌥⌘⎋ is deliberately close to the system's force-quit
/// shortcut but distinct from it.
enum PanicShortcut {
    static let displayName = "⌃⌥⌘⎋"

    /// `kVK_Escape`
    private static let escapeKeyCode: Int64 = 53

    private static let requiredFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    static func matches(_ event: CGEvent) -> Bool {
        let modifiers = event.flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift])
        return modifiers == requiredFlags
            && event.getIntegerValueField(.keyboardEventKeycode) == escapeKeyCode
    }
}
