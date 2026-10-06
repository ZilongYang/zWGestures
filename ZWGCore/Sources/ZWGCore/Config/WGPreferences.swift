import Foundation

/// How zWGestures decides which target's gesture set applies.
public enum WGTargetMode: String, Codable, Sendable, CaseIterable {
    /// WGestures: 活动的应用程序和窗口
    case focused = "Focused"
    /// WGestures: 鼠标指针下方的应用程序和窗口
    case underCursor = "UnderCursor"

    public var localizedName: String {
        switch self {
        case .focused: L10n.text(.targetModeFocused)
        case .underCursor: L10n.text(.targetModeUnderCursor)
        }
    }
}

/// The preference file, matching `prefs.json` key for key.
public struct WGPreferences: Codable, Equatable, Sendable {
    public var autoStart: Bool
    /// WGestures: 手势起始超时, in milliseconds.
    public var startDragTimeout: Int
    public var showStartDragTimeoutIndicator: Bool
    public var showPath: Bool
    public var showGestureName: Bool
    public var showStatusIcon: Bool
    /// Colours in `#AARRGGBB` form, as written by the original app.
    public var pathColorNormal: String
    public var pathColorRecognized: String
    public var labelColorNormal: String
    /// Key is `LabelColorExecuted` in the original file, not `LabelExecuted` (which is only
    /// the localisation key).
    public var labelColorExecuted: String
    public var targetMode: WGTargetMode
    public var pathLineWidth: Double
    /// Vertical position of the gesture-name label, as a fraction of the screen height.
    public var gesturePos: Double
    public var skipVersion: String?
    /// 是否已经问过用户「要不要把已知的英文手势名改成中文」。**扩展键**，缺键即「没问过」，
    /// 且**只在问过之后才写出**（同 `--language` 的规则，保住逐键一致守卫）。
    public var nameRenameOffered: Bool
    /// 界面语言。**本项目的扩展键**：原版没有这一项，缺键即视为 `system`（跟随系统），
    /// 而且**只在非默认时才写出** —— `ConfigTests` 有一条「真实配置重新编码后与原文件逐键一致」
    /// 的守卫，对默认值也写键会立刻让它失败（与 `WGIntent.enabled` 同一条硬约束）。
    public var language: WGLanguagePreference

    public init(
        autoStart: Bool = true,
        startDragTimeout: Int = 250,
        showStartDragTimeoutIndicator: Bool = true,
        showPath: Bool = true,
        showGestureName: Bool = true,
        showStatusIcon: Bool = true,
        pathColorNormal: String = "#7F7F7FC4",
        pathColorRecognized: String = "#20D697E6",
        labelColorNormal: String = "#60606080",
        labelColorExecuted: String = "#20D697E6",
        targetMode: WGTargetMode = .focused,
        pathLineWidth: Double = 2.25,
        gesturePos: Double = 0.25,
        skipVersion: String? = nil,
        language: WGLanguagePreference = .system,
        nameRenameOffered: Bool = false
    ) {
        self.autoStart = autoStart
        self.startDragTimeout = startDragTimeout
        self.showStartDragTimeoutIndicator = showStartDragTimeoutIndicator
        self.showPath = showPath
        self.showGestureName = showGestureName
        self.showStatusIcon = showStatusIcon
        self.pathColorNormal = pathColorNormal
        self.pathColorRecognized = pathColorRecognized
        self.labelColorNormal = labelColorNormal
        self.labelColorExecuted = labelColorExecuted
        self.targetMode = targetMode
        self.pathLineWidth = pathLineWidth
        self.gesturePos = gesturePos
        self.skipVersion = skipVersion
        self.language = language
        self.nameRenameOffered = nameRenameOffered
    }

    public enum CodingKeys: String, CodingKey {
        case autoStart = "AutoStart"
        case startDragTimeout = "StartDragTimeout"
        case showStartDragTimeoutIndicator = "ShowStartDragTimeoutIndicator"
        case showPath = "ShowPath"
        case showGestureName = "ShowGestureName"
        case showStatusIcon = "ShowStatusIcon"
        case pathColorNormal = "PathColorNormal"
        case pathColorRecognized = "PathColorRecognized"
        case labelColorNormal = "LabelColorNormal"
        case labelColorExecuted = "LabelColorExecuted"
        case targetMode = "TargetMode"
        case pathLineWidth = "PathLineWidth"
        case gesturePos = "GesturePos"
        case skipVersion = "SkipVersion"
        case language = "Language"
        case nameRenameOffered = "NameRenameOffered"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WGPreferences()
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? defaults.autoStart
        startDragTimeout = try container.decodeIfPresent(Int.self, forKey: .startDragTimeout) ?? defaults.startDragTimeout
        showStartDragTimeoutIndicator = try container
            .decodeIfPresent(Bool.self, forKey: .showStartDragTimeoutIndicator) ?? defaults.showStartDragTimeoutIndicator
        showPath = try container.decodeIfPresent(Bool.self, forKey: .showPath) ?? defaults.showPath
        showGestureName = try container.decodeIfPresent(Bool.self, forKey: .showGestureName) ?? defaults.showGestureName
        showStatusIcon = try container.decodeIfPresent(Bool.self, forKey: .showStatusIcon) ?? defaults.showStatusIcon
        pathColorNormal = try container.decodeIfPresent(String.self, forKey: .pathColorNormal) ?? defaults.pathColorNormal
        pathColorRecognized = try container
            .decodeIfPresent(String.self, forKey: .pathColorRecognized) ?? defaults.pathColorRecognized
        labelColorNormal = try container.decodeIfPresent(String.self, forKey: .labelColorNormal) ?? defaults.labelColorNormal
        labelColorExecuted = try container
            .decodeIfPresent(String.self, forKey: .labelColorExecuted) ?? defaults.labelColorExecuted
        targetMode = try container.decodeIfPresent(WGTargetMode.self, forKey: .targetMode) ?? defaults.targetMode
        pathLineWidth = try container.decodeIfPresent(Double.self, forKey: .pathLineWidth) ?? defaults.pathLineWidth
        gesturePos = try container.decodeIfPresent(Double.self, forKey: .gesturePos) ?? defaults.gesturePos
        skipVersion = try container.decodeIfPresent(String.self, forKey: .skipVersion)
        language = try container.decodeIfPresent(WGLanguagePreference.self, forKey: .language) ?? defaults.language
        nameRenameOffered = try container.decodeIfPresent(Bool.self, forKey: .nameRenameOffered)
            ?? defaults.nameRenameOffered
    }

    /// Written explicitly rather than synthesised, because the original always emits every
    /// key — including `SkipVersion: null` — and `encodeIfPresent` would silently drop the
    /// nulls.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(autoStart, forKey: .autoStart)
        try container.encode(startDragTimeout, forKey: .startDragTimeout)
        try container.encode(showStartDragTimeoutIndicator, forKey: .showStartDragTimeoutIndicator)
        try container.encode(showPath, forKey: .showPath)
        try container.encode(showGestureName, forKey: .showGestureName)
        try container.encode(showStatusIcon, forKey: .showStatusIcon)
        try container.encode(pathColorNormal, forKey: .pathColorNormal)
        try container.encode(pathColorRecognized, forKey: .pathColorRecognized)
        try container.encode(labelColorNormal, forKey: .labelColorNormal)
        try container.encode(labelColorExecuted, forKey: .labelColorExecuted)
        try container.encode(targetMode, forKey: .targetMode)
        try container.encode(pathLineWidth, forKey: .pathLineWidth)
        try container.encode(gesturePos, forKey: .gesturePos)
        if let skipVersion {
            try container.encode(skipVersion, forKey: .skipVersion)
        } else {
            try container.encodeNil(forKey: .skipVersion)
        }
        // 扩展键：只在非默认时写出，保证原版文件重新编码后仍然逐键一致（同 `WGIntent.enabled`）。
        if language != .system {
            try container.encode(language, forKey: .language)
        }
        if nameRenameOffered {
            try container.encode(nameRenameOffered, forKey: .nameRenameOffered)
        }
    }
}

extension WGPreferences {
    /// The engine's start-drag timeout in seconds.
    public var startDragTimeoutSeconds: TimeInterval {
        TimeInterval(startDragTimeout) / 1000
    }
}
