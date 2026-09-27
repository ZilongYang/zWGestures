import AppKit
import CoreGraphics
import Foundation

/// Posts synthetic keyboard events.
enum KeyEventPoster {
    private static let syntheticMarker = SyntheticEventPoster.userDataMagic

    /// Plays one key combination: press the modifiers, press the key, release everything.
    ///
    /// Real modifier key presses are emitted rather than only setting the flag bits on the main
    /// key event, because some applications and system-wide shortcuts track modifier state
    /// rather than reading the flags field. There are no early returns between the press and
    /// the release, so a modifier can never be left stuck down.
    static func postKeyStroke(modifiers: [CGKeyCode], flags: CGEventFlags, keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Log.action.error("无法创建事件源，按键未发送")
            return
        }

        var accumulated: CGEventFlags = []
        for modifier in modifiers {
            accumulated.insert(flag(for: modifier))
            post(keyCode: modifier, down: true, flags: accumulated, source: source)
        }

        post(keyCode: keyCode, down: true, flags: flags, source: source)
        post(keyCode: keyCode, down: false, flags: flags, source: source)

        var remaining = flags
        for modifier in modifiers.reversed() {
            remaining.remove(flag(for: modifier))
            post(keyCode: modifier, down: false, flags: remaining, source: source)
        }
    }

    private static func post(keyCode: CGKeyCode, down: Bool, flags: CGEventFlags, source: CGEventSource) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else {
            Log.action.error("无法构造按键事件 keyCode=\(keyCode, privacy: .public)")
            return
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    private static func flag(for modifierKeyCode: CGKeyCode) -> CGEventFlags {
        switch modifierKeyCode {
        case 0x37, 0x36: .maskCommand
        case 0x38, 0x3C: .maskShift
        case 0x3A, 0x3D: .maskAlternate
        case 0x3B, 0x3E: .maskControl
        case 0x39: .maskAlphaShift
        case 0x3F: .maskSecondaryFn
        default: []
        }
    }
}

/// Posts the media and brightness keys.
///
/// These are not regular key codes: they go through the `systemDefined` event subtype that the
/// `NX_KEYTYPE_*` constants describe.
enum SystemFunctionPoster {
    private static let subtypeAuxControlButtons: Int16 = 8
    /// `NX_KEYDOWN` shifted into the high byte.
    private static let keyDownData: Int = 0x0A00
    private static let keyUpData: Int = 0x0B00

    static func post(_ function: WGSystemFunction) {
        for data in [keyDownData, keyUpData] {
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: subtypeAuxControlButtons,
                data1: (keyType(of: function) << 16) | data,
                data2: -1
            ) else {
                Log.action.error("无法构造系统功能键事件")
                continue
            }
            if let cgEvent = event.cgEvent {
                cgEvent.setIntegerValueField(.eventSourceUserData, value: SyntheticEventPoster.userDataMagic)
                cgEvent.post(tap: .cghidEventTap)
            }
        }
    }

    /// `NX_KEYTYPE_*` values live with the command model so they can be unit tested.
    static func keyType(of function: WGSystemFunction) -> Int {
        function.nxKeyType
    }
}
