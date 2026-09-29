import Foundation

/// Remembers whether this app has ever run with the Accessibility grant in place.
///
/// The only way to tell "never granted" apart from "granted, then taken away by an update": macOS
/// exposes no API for reading the TCC database, and an ad-hoc signature derives its designated
/// requirement from the CDHash, so as far as TCC is concerned every rebuild is a different app.
///
/// Kept in this app's own `UserDefaults` rather than in the user's `prefs.json`: it describes this
/// machine's installation, not the user's gesture configuration. It also has to survive the case
/// that matters — an update replacing the app bundle — and `prefs.json` lives outside the bundle.
public struct PermissionHistory {
    private static let key = "hasRunWithAccessibilityGranted"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasEverRunGranted: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func recordGranted() {
        guard !hasEverRunGranted else { return }
        defaults.set(true, forKey: Self.key)
    }
}
