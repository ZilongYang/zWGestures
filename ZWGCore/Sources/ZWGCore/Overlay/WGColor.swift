import Foundation

/// A colour written the way the original app writes them in `prefs.json`.
///
/// The format is `#RRGGBBAA`. Two independent details rule out the alternative `#AARRGGBB`:
///
/// * Both "normal" colours start with six digits that form an exact grey — `#7F7F7F…` for the
///   idle trail and `#606060…` for the idle label. Under `AARRGGBB` that would be a coincidence
///   twice over.
/// * The recognised colour is then `#20D697…`, a teal green, which is what a "recognised" or
///   "executed" highlight should look like.
public struct WGColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA` (the `#` is optional). Returns `nil` for anything else,
    /// so a hand-edited preference file cannot crash the overlay.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8,
              let value = UInt32(text, radix: 16)
        else { return nil }

        if text.count == 6 {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        } else {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        }
    }

    /// The `#RRGGBBAA` form the original app writes.
    ///
    /// Deliberately always eight digits and upper case, matching `prefs.json`, so writing a colour
    /// back does not change how the file looks.
    public var hexString: String {
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X%02X",
            channel(red), channel(green), channel(blue), channel(alpha)
        )
    }
}
