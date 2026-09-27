import CoreGraphics
import Foundation

/// Maps the key names used in WGestures configurations to virtual key codes and event flags.
///
/// The names mirror Apple's `kVK_*` constants: letters and digits are `ANSI_A` … `ANSI_Z` and
/// `ANSI_0` … `ANSI_9` (those are the *names*, the codes themselves are the hardware layout
/// values), named symbols are `ANSI_LeftBracket` and friends, and modifiers are spelled out
/// (`Command`, `Shift`, `Control`, `Option`).
public enum WGKeyCode {
    public enum Kind: Sendable, Equatable {
        case key(CGKeyCode)
        case modifier(CGEventFlags, CGKeyCode)
        case unknown
    }

    public static func classify(_ name: String) -> Kind {
        if let flags = modifierFlags[name], let code = modifierKeyCodes[name] {
            return .modifier(flags, code)
        }
        if let code = keyCodes[name] {
            return .key(code)
        }
        return .unknown
    }

    /// Whether the name is a modifier such as `Command`.
    public static func isModifier(_ name: String) -> Bool {
        modifierFlags[name] != nil
    }

    /// Virtual key codes for modifiers, used to emit realistic modifier key presses.
    public static let modifierKeyCodes: [String: CGKeyCode] = [
        "Command": 0x37, // kVK_Command
        "Shift": 0x38, // kVK_Shift
        "CapsLock": 0x39, // kVK_CapsLock
        "Option": 0x3A, // kVK_Option
        "Control": 0x3B, // kVK_Control
        "RightCommand": 0x36,
        "RightShift": 0x3C,
        "RightOption": 0x3D,
        "RightControl": 0x3E,
        "Function": 0x3F, // kVK_Function
    ]

    public static let modifierFlags: [String: CGEventFlags] = [
        "Command": .maskCommand,
        "Shift": .maskShift,
        "CapsLock": .maskAlphaShift,
        "Option": .maskAlternate,
        "Control": .maskControl,
        "RightCommand": .maskCommand,
        "RightShift": .maskShift,
        "RightOption": .maskAlternate,
        "RightControl": .maskControl,
        "Function": .maskSecondaryFn,
    ]

    /// `ANSI_…` names and the special keys seen in real configurations.
    public static let keyCodes: [String: CGKeyCode] = {
        var table: [String: CGKeyCode] = [:]

        let letters: [String: CGKeyCode] = [
            "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05,
            "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C,
            "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11, "O": 0x1F,
            "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "K": 0x28,
            "N": 0x2D, "M": 0x2E,
        ]
        for (letter, code) in letters {
            table["ANSI_\(letter)"] = code
        }

        let digits: [String: CGKeyCode] = [
            "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
            "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        ]
        for (digit, code) in digits {
            table["ANSI_\(digit)"] = code
        }

        let symbols: [String: CGKeyCode] = [
            "ANSI_Equal": 0x18,
            "ANSI_Minus": 0x1B,
            "ANSI_RightBracket": 0x1E,
            "ANSI_LeftBracket": 0x21,
            "ANSI_Quote": 0x27,
            "ANSI_Semicolon": 0x29,
            "ANSI_Backslash": 0x2A,
            "ANSI_Comma": 0x2B,
            "ANSI_Slash": 0x2C,
            "ANSI_Period": 0x2F,
            "ANSI_Grave": 0x32,
            "Return": 0x24,
            "Tab": 0x30,
            "Space": 0x31,
            "Delete": 0x33,
            "Escape": 0x35,
            "ForwardDelete": 0x75,
            "Home": 0x73,
            "End": 0x77,
            "PageUp": 0x74,
            "PageDown": 0x79,
            "Help": 0x72,
            "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76, "F5": 0x60,
            "F6": 0x61, "F7": 0x62, "F8": 0x64, "F9": 0x65, "F10": 0x6D,
            "F11": 0x67, "F12": 0x6F, "F13": 0x69, "F14": 0x6B, "F15": 0x71,
            "F16": 0x6A, "F17": 0x40, "F18": 0x4F, "F19": 0x50, "F20": 0x5A,
            // 小键盘
            "ANSI_Keypad0": 0x52, "ANSI_Keypad1": 0x53, "ANSI_Keypad2": 0x54,
            "ANSI_Keypad3": 0x55, "ANSI_Keypad4": 0x56, "ANSI_Keypad5": 0x57,
            "ANSI_Keypad6": 0x58, "ANSI_Keypad7": 0x59, "ANSI_Keypad8": 0x5B,
            "ANSI_Keypad9": 0x5C, "ANSI_KeypadDecimal": 0x41,
            "ANSI_KeypadMultiply": 0x43, "ANSI_KeypadPlus": 0x45,
            "ANSI_KeypadClear": 0x47, "ANSI_KeypadDivide": 0x4B,
            "ANSI_KeypadEnter": 0x4C, "ANSI_KeypadMinus": 0x4E,
            "ANSI_KeypadEquals": 0x51,
        ]
        table.merge(symbols) { current, _ in current }
        return table
    }()
}
