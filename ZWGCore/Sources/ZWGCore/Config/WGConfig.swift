import CoreGraphics
import Foundation

// MARK: - Root

/// The on-disk gesture configuration, byte-compatible with
/// `~/Library/Application Support/com.yingdev.wgestures/<version>/gestures.json`.
///
/// Field names and enum values match WGestures exactly, so a file written by zWGestures can
/// be read by the original app and vice versa. Nothing is written back to the original
/// app's directory — import is a one-way copy into zWGestures' own storage.
public struct WGConfig: Codable, Equatable, Sendable {
    /// The fallback target that applies when nothing more specific matches.
    public var general: WGTarget
    /// Groups of applications that share a gesture set.
    public var groups: [WGTarget]
    public var apps: [WGTarget]
    /// Non-application targets, currently just the desktop.
    public var specials: [WGTarget]

    public init(
        general: WGTarget = .makeGeneral(),
        groups: [WGTarget] = [],
        apps: [WGTarget] = [],
        specials: [WGTarget] = []
    ) {
        self.general = general
        self.groups = groups
        self.apps = apps
        self.specials = specials
    }

    public enum CodingKeys: String, CodingKey {
        case general = "General"
        case groups = "Groups"
        case apps = "Apps"
        case specials = "Specials"
    }

    /// Every target, including the general one.
    public var allTargets: [WGTarget] {
        [general] + groups + apps + specials
    }
}

// MARK: - Target

public enum WGTargetKind: Equatable, Sendable {
    /// The `General` key, which carries no `$type`.
    case general
    case app
    case desktop
    /// A `$type` this build does not know about. Preserved so a re-export is not lossy.
    case other(String)
}

extension WGTargetKind: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "MacAppTarget": self = .app
        case "MacDesktopTarget": self = .desktop
        default: self = .other(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .general: try container.encode("") // never encoded; General omits `$type`
        case .app: try container.encode("MacAppTarget")
        case .desktop: try container.encode("MacDesktopTarget")
        case .other(let raw): try container.encode(raw)
        }
    }

    public var isGeneral: Bool { self == .general }
}

/// A gesture target: the general fallback, an application, a group, or the desktop.
public struct WGTarget: Codable, Equatable, Sendable, Identifiable {
    public var kind: WGTargetKind
    public var id: String
    public var name: String
    /// Bundle identifier of the target application. May be `null` in existing configs.
    public var bundleId: String?
    /// Executable path, used when `bundleId` is absent.
    public var path: String?
    public var intents: [WGIntent]
    /// Overrides of the general trigger matrix. An empty list means "inherit everything".
    public var triggers: [WGTrigger]

    public init(
        kind: WGTargetKind,
        id: String = WGIdentifier.make(),
        name: String,
        bundleId: String? = nil,
        path: String? = nil,
        intents: [WGIntent] = [],
        triggers: [WGTrigger] = []
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.path = path
        self.intents = intents
        self.triggers = triggers
    }

    public static func makeGeneral() -> WGTarget {
        WGTarget(kind: .general, name: "General")
    }

    public enum CodingKeys: String, CodingKey {
        case type = "$type"
        case bundleId = "BundleId"
        case id = "Id"
        case name = "Name"
        case path = "Path"
        case intents = "Intents"
        case triggers = "Triggers"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? container.decode(WGTargetKind.self, forKey: .type)) ?? .general
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        intents = try container.decodeIfPresent([WGIntent].self, forKey: .intents) ?? []
        triggers = try container.decodeIfPresent([WGTrigger].self, forKey: .triggers) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !kind.isGeneral {
            try container.encode(kind, forKey: .type)
        }
        // Application targets always carry both keys, matching the original's output.
        if kind == .app {
            try container.encode(bundleId, forKey: .bundleId)
            try container.encode(path, forKey: .path)
        }
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(intents, forKey: .intents)
        try container.encode(triggers, forKey: .triggers)
    }
}

// MARK: - Trigger

/// One row of the trigger matrix: the input sequence plus whether it is enabled.
public struct WGTrigger: Codable, Equatable, Sendable {
    public var def: [WGStep]
    public var enabled: Bool

    public init(def: [WGStep], enabled: Bool) {
        self.def = def
        self.enabled = enabled
    }

    public enum CodingKeys: String, CodingKey {
        case def = "Def"
        case enabled = "Enabled"
    }
}

// MARK: - Intent

public struct WGIntent: Codable, Equatable, Sendable {
    public var name: String
    /// WGestures: 识别手势后立即执行 — run as soon as the stroke is recognised, without
    /// waiting for the trigger to finish.
    public var executeOnRecognize: Bool
    /// Trigger press, then the stroke, then any gesture-modifier steps.
    public var gesture: [WGStep]
    public var command: WGCommand

    public init(name: String, executeOnRecognize: Bool = false, gesture: [WGStep], command: WGCommand) {
        self.name = name
        self.executeOnRecognize = executeOnRecognize
        self.gesture = gesture
        self.command = command
    }

    public enum CodingKeys: String, CodingKey {
        case name = "Name"
        case executeOnRecognize = "ExecuteOnRecognize"
        case gesture = "Gesture"
        case command = "Command"
    }

    /// The steps before the stroke: the trigger itself and any leading conditions.
    public var triggerSteps: [WGStep] { gesture.prefix { !$0.isStroke }.map { $0 } }

    /// The stroke, when this gesture has one.
    public var strokeStep: WGStrokeStep? {
        for step in gesture {
            if case .stroke(let stroke) = step { return stroke }
        }
        return nil
    }

    /// Steps that follow the stroke. WGestures calls these 手势修饰键: extra button presses or
    /// scrolls that pick one command out of several sharing the same trajectory.
    public var modifierSteps: [WGStep] {
        guard let strokeIndex = gesture.firstIndex(where: { $0.isStroke }) else { return [] }
        return Array(gesture[gesture.index(after: strokeIndex)...])
    }
}

// MARK: - Steps

public struct WGKeyDownStep: Codable, Equatable, Sendable {
    /// `MOUSE:n`, `VSCROLL:±n`, or a key name such as `Command`.
    public var key: String

    public init(key: String) { self.key = key }

    public enum CodingKeys: String, CodingKey { case key = "Key" }
}

public struct WGStrokeStep: Codable, Equatable, Sendable {
    /// `true` for a straight/simple stroke stored on the 50-unit grid; `false` for an
    /// arbitrary shape stored as raw screen coordinates.
    public var isSimple: Bool
    /// Flat `x, y, x, y, …` list. **Stored in reverse drawing order**: the final pair is
    /// always the starting point `(0, 0)`.
    ///
    /// Coordinates follow screen orientation — y grows downwards — for both stroke kinds, so
    /// no axis flip is needed when comparing against a live `CGEvent.location`.
    public var points: [Int]

    public init(isSimple: Bool, points: [Int]) {
        self.isSimple = isSimple
        self.points = points
    }

    public enum CodingKeys: String, CodingKey {
        case isSimple = "IsSimple"
        case points = "P"
    }

    /// The trajectory in drawing order, as `(x, y)` pairs.
    public var drawingOrderPoints: [CGPoint] {
        let pairs = stride(from: 0, to: points.count - 1, by: 2).map {
            CGPoint(x: CGFloat(points[$0]), y: CGFloat(points[$0 + 1]))
        }
        return pairs.reversed()
    }
}

public struct WGEdgeCorner: Codable, Equatable, Sendable {
    /// Bit mask of the screen edges: 1 = top, 2 = right, 4 = bottom, 8 = left, and any two
    /// adjacent bits form a corner (3, 6, 12, 9).
    public var value: Int

    public init(value: Int) { self.value = value }

    public enum CodingKeys: String, CodingKey { case value = "Value" }
}

public struct WGMoveToEdgeCornerStep: Codable, Equatable, Sendable {
    public var edgeCorner: WGEdgeCorner

    public init(edgeCorner: WGEdgeCorner) { self.edgeCorner = edgeCorner }

    public enum CodingKeys: String, CodingKey { case edgeCorner = "EdgeCorner" }
}

public struct WGScrollStep: Codable, Equatable, Sendable {
    public var isHorizontal: Bool

    public init(isHorizontal: Bool) { self.isHorizontal = isHorizontal }

    public enum CodingKeys: String, CodingKey { case isHorizontal = "IsHorizontal" }
}

public enum WGStep: Codable, Equatable, Sendable {
    case keyDown(WGKeyDownStep)
    case stroke(WGStrokeStep)
    case moveToEdgeCorner(WGMoveToEdgeCornerStep)
    case scroll(WGScrollStep)
    /// A `$type` this build does not know about; the payload is dropped and reported.
    case unknown(type: String)

    public var typeName: String {
        switch self {
        case .keyDown: "KeyDownStep"
        case .stroke: "StrokeStep"
        case .moveToEdgeCorner: "MoveToEdgeCornerStep"
        case .scroll: "ScrollStep"
        case .unknown(let type): type
        }
    }

    public var isStroke: Bool {
        if case .stroke = self { return true }
        return false
    }

    public var keyDown: WGKeyDownStep? {
        if case .keyDown(let step) = self { return step }
        return nil
    }

    public var edgeCorner: WGMoveToEdgeCornerStep? {
        if case .moveToEdgeCorner(let step) = self { return step }
        return nil
    }

    public var scroll: WGScrollStep? {
        if case .scroll(let step) = self { return step }
        return nil
    }

    private enum TypeKey: String, CodingKey {
        case type = "$type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "KeyDownStep": self = .keyDown(try WGKeyDownStep(from: decoder))
        case "StrokeStep": self = .stroke(try WGStrokeStep(from: decoder))
        case "MoveToEdgeCornerStep": self = .moveToEdgeCorner(try WGMoveToEdgeCornerStep(from: decoder))
        case "ScrollStep": self = .scroll(try WGScrollStep(from: decoder))
        default: self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case .keyDown(let step): try step.encode(to: encoder)
        case .stroke(let step): try step.encode(to: encoder)
        case .moveToEdgeCorner(let step): try step.encode(to: encoder)
        case .scroll(let step): try step.encode(to: encoder)
        case .unknown: break
        }
    }
}

// MARK: - Commands

public struct WGKeySequenceCommand: Codable, Equatable, Sendable {
    /// WGestures: 这是一个系统快捷键 — when true the target application is *not* activated
    /// before the keys are sent.
    public var isSystemHotKey: Bool
    /// Key names, with `null` separating the steps of a multi-step sequence
    /// (e.g. `["Command", "ANSI_V", null, "Return"]` is ⌘V then Return).
    public var keys: [String?]

    public init(isSystemHotKey: Bool, keys: [String?]) {
        self.isSystemHotKey = isSystemHotKey
        self.keys = keys
    }

    public enum CodingKeys: String, CodingKey {
        case isSystemHotKey = "IsSystemHotKey"
        case keys = "Keys"
    }

    /// The sequence split into steps, each step being the keys pressed together.
    public var steps: [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for key in keys {
            if let key {
                current.append(key)
            } else {
                if !current.isEmpty { result.append(current) }
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

public struct WGWebSearchCommand: Codable, Equatable, Sendable {
    /// A URL template where `{0}` is replaced by the search terms.
    public var searchEngine: String

    public init(searchEngine: String) { self.searchEngine = searchEngine }

    public enum CodingKeys: String, CodingKey { case searchEngine = "SearchEngine" }
}

public struct WGShellScriptCommand: Codable, Equatable, Sendable {
    public var script: String

    public init(script: String) { self.script = script }

    public enum CodingKeys: String, CodingKey { case script = "Script" }
}

/// WGestures: 系统功能键. `selectedIndex` runs 0…7 over brightness down/up, previous,
/// play/pause, next, mute, volume down/up — the same order as the localisation table.
public struct WGSystemFunctionKeyCommand: Codable, Equatable, Sendable {
    public var selectedIndex: Int

    public init(selectedIndex: Int) { self.selectedIndex = selectedIndex }

    public enum CodingKeys: String, CodingKey { case selectedIndex = "SelectedIndex" }

    public var function: WGSystemFunction? { WGSystemFunction(rawValue: selectedIndex) }
}

public enum WGSystemFunction: Int, CaseIterable, Sendable {
    case brightnessDown = 0
    case brightnessUp = 1
    case previousTrack = 2
    case playPause = 3
    case nextTrack = 4
    case mute = 5
    case volumeDown = 6
    case volumeUp = 7

    public var localizedName: String {
        switch self {
        case .brightnessDown: "降低亮度"
        case .brightnessUp: "增加亮度"
        case .previousTrack: "上一曲"
        case .playPause: "播放/暂停"
        case .nextTrack: "下一曲"
        case .mute: "静音"
        case .volumeDown: "降低音量"
        case .volumeUp: "增加音量"
        }
    }
}

public enum WGCommand: Codable, Equatable, Sendable {
    case keySequence(WGKeySequenceCommand)
    case webSearch(WGWebSearchCommand)
    case shellScript(WGShellScriptCommand)
    case systemFunctionKey(WGSystemFunctionKeyCommand)
    case unknown(type: String)

    public var typeName: String {
        switch self {
        case .keySequence: "KeySeqCommand"
        case .webSearch: "WebSearchCommand"
        case .shellScript: "ShellScriptCommand"
        case .systemFunctionKey: "SystemFunctionKeyCommand"
        case .unknown(let type): type
        }
    }

    private enum TypeKey: String, CodingKey {
        case type = "$type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "KeySeqCommand": self = .keySequence(try WGKeySequenceCommand(from: decoder))
        case "WebSearchCommand": self = .webSearch(try WGWebSearchCommand(from: decoder))
        case "ShellScriptCommand": self = .shellScript(try WGShellScriptCommand(from: decoder))
        case "SystemFunctionKeyCommand": self = .systemFunctionKey(try WGSystemFunctionKeyCommand(from: decoder))
        default: self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case .keySequence(let command): try command.encode(to: encoder)
        case .webSearch(let command): try command.encode(to: encoder)
        case .shellScript(let command): try command.encode(to: encoder)
        case .systemFunctionKey(let command): try command.encode(to: encoder)
        case .unknown: break
        }
    }
}

// MARK: - Identifiers

/// The original app generates 22-character short GUIDs for target and intent ids.
/// Generated here with the same alphabet so ids look and behave consistently.
public enum WGIdentifier {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    public static func make(length: Int = 22) -> String {
        String((0..<length).map { _ in alphabet.randomElement() ?? "A" })
    }
}
