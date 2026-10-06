import Foundation

/// Editing state for `prefs.json`.
///
/// Only exposes preferences the app actually honours. `ShowStartDragTimeoutIndicator` and
/// `ShowStatusIcon` exist in the original format but are **not implemented** in this build (nothing
/// reads them), so they are deliberately absent: a control that does nothing is worse than no
/// control. Hiding the status icon would be actively dangerous here — the menu-bar item is this
/// app's only way in.
///
/// Colours are kept as their original `#RRGGBBAA` strings and only rewritten when the user picks a
/// new one, so opening the pane and saving cannot silently reformat a hand-edited file.
@MainActor
public final class PreferencesModel: ObservableObject {
    public static let timeoutRange = 50...1000
    public static let lineWidthRange = 0.5...8.0
    public static let gesturePositionRange = 0.0...1.0

    @Published public var startDragTimeout: Int
    @Published public var targetMode: WGTargetMode
    @Published public var showPath: Bool
    @Published public var showGestureName: Bool
    @Published public var pathColorNormalHex: String
    @Published public var pathColorRecognizedHex: String
    @Published public var labelColorNormalHex: String
    @Published public var labelColorExecutedHex: String
    @Published public var pathLineWidth: Double
    @Published public var gesturePos: Double
    @Published public var language: WGLanguagePreference

    /// The preferences as last loaded or saved. Everything the panel does not edit — `AutoStart`
    /// (owned by the login item) and `SkipVersion` — is carried over from here, so saving cannot
    /// clobber it, and comparing against it is what makes `isDirty` trustworthy.
    private var loaded: WGPreferences

    public init(preferences: WGPreferences) {
        startDragTimeout = preferences.startDragTimeout
        targetMode = preferences.targetMode
        showPath = preferences.showPath
        showGestureName = preferences.showGestureName
        pathColorNormalHex = preferences.pathColorNormal
        pathColorRecognizedHex = preferences.pathColorRecognized
        labelColorNormalHex = preferences.labelColorNormal
        labelColorExecutedHex = preferences.labelColorExecuted
        pathLineWidth = preferences.pathLineWidth
        gesturePos = preferences.gesturePos
        language = preferences.language
        loaded = preferences
    }

    /// Reloads from disk, e.g. before the settings window comes up.
    public func load(preferences: WGPreferences) {
        let reloaded = PreferencesModel(preferences: preferences)
        startDragTimeout = reloaded.startDragTimeout
        targetMode = reloaded.targetMode
        showPath = reloaded.showPath
        showGestureName = reloaded.showGestureName
        pathColorNormalHex = reloaded.pathColorNormalHex
        pathColorRecognizedHex = reloaded.pathColorRecognizedHex
        labelColorNormalHex = reloaded.labelColorNormalHex
        labelColorExecutedHex = reloaded.labelColorExecutedHex
        pathLineWidth = reloaded.pathLineWidth
        gesturePos = reloaded.gesturePos
        language = reloaded.language
        loaded = preferences
    }

    // MARK: - Colours

    public var pathColorNormal: WGColor {
        get { WGColor(hex: pathColorNormalHex) ?? Self.fallbackPath }
        set { pathColorNormalHex = newValue.hexString }
    }

    public var pathColorRecognized: WGColor {
        get { WGColor(hex: pathColorRecognizedHex) ?? Self.fallbackRecognized }
        set { pathColorRecognizedHex = newValue.hexString }
    }

    public var labelColorNormal: WGColor {
        get { WGColor(hex: labelColorNormalHex) ?? Self.fallbackLabel }
        set { labelColorNormalHex = newValue.hexString }
    }

    public var labelColorExecuted: WGColor {
        get { WGColor(hex: labelColorExecutedHex) ?? Self.fallbackRecognized }
        set { labelColorExecutedHex = newValue.hexString }
    }

    private static let fallbackPath = WGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.77)
    private static let fallbackLabel = WGColor(red: 0.38, green: 0.38, blue: 0.38, alpha: 0.5)
    private static let fallbackRecognized = WGColor(red: 0.125, green: 0.84, blue: 0.59, alpha: 0.9)

    // MARK: - Result

    /// The preferences as they would be written to disk.
    public var editedPreferences: WGPreferences {
        var result = loaded
        result.startDragTimeout = startDragTimeout
        result.targetMode = targetMode
        result.showPath = showPath
        result.showGestureName = showGestureName
        result.pathColorNormal = pathColorNormalHex
        result.pathColorRecognized = pathColorRecognizedHex
        result.labelColorNormal = labelColorNormalHex
        result.labelColorExecuted = labelColorExecutedHex
        result.pathLineWidth = pathLineWidth
        result.gesturePos = gesturePos
        result.language = language
        return result
    }

    public var isDirty: Bool { editedPreferences != loaded }

    public func markSaved() {
        loaded = editedPreferences
    }

    public func revert() {
        load(preferences: loaded)
    }

    /// Rounds a slider value to something a human would type, so `prefs.json` stays readable.
    public static func roundedLineWidth(_ value: Double) -> Double {
        (value * 4).rounded() / 4
    }

    /// The current values, checked. Sliders cannot leave their range, so this is a safety net for
    /// values loaded from a hand-edited file.
    public var validationError: String? {
        guard Self.timeoutRange.contains(startDragTimeout) else {
            return "起始超时需要在 \(Self.timeoutRange.lowerBound)–\(Self.timeoutRange.upperBound) 毫秒之间。"
        }
        guard Self.lineWidthRange.contains(pathLineWidth) else {
            return "线宽需要在 \(Self.lineWidthRange.lowerBound)–\(Self.lineWidthRange.upperBound) 之间。"
        }
        guard Self.gesturePositionRange.contains(gesturePos) else {
            return "手势名位置需要在 0–1 之间。"
        }
        return nil
    }

    public var canSave: Bool { validationError == nil }
}
