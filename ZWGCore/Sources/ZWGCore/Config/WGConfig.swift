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
    /// Whether this target's gestures are used **in addition to** the general ones, with its own
    /// taking priority.
    ///
    /// An application gesture set is normally an overlay: an app that defines one gesture still
    /// wants copy, paste and the rest. Replacing the general set outright is occasionally useful
    /// (an app where only that one gesture should work at all), which is why it stays switchable.
    ///
    /// **Extension of this project, like `WGIntent.enabled`.** WGestures 2.3.3 has no such key, so
    /// it is written **only when it differs from the default for that kind** — app targets default
    /// to inheriting, everything else to replacing, which keeps existing files byte-identical when
    /// re-encoded (guarded by `ConfigTests`).
    public var inheritsGlobal: Bool

    /// The default for a kind: application sets overlay the general one; anything else keeps the
    /// original replace semantics.
    public static func defaultInheritsGlobal(for kind: WGTargetKind) -> Bool {
        kind == .app
    }

    public init(
        kind: WGTargetKind,
        id: String = WGIdentifier.make(),
        name: String,
        bundleId: String? = nil,
        path: String? = nil,
        intents: [WGIntent] = [],
        triggers: [WGTrigger] = [],
        inheritsGlobal: Bool? = nil
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.path = path
        self.intents = intents
        self.triggers = triggers
        self.inheritsGlobal = inheritsGlobal ?? Self.defaultInheritsGlobal(for: kind)
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
        case inheritsGlobal = "InheritGlobal"
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
        inheritsGlobal = try container.decodeIfPresent(Bool.self, forKey: .inheritsGlobal)
            ?? Self.defaultInheritsGlobal(for: kind)
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
        // Omitted while it matches the default, so re-encoding an existing file stays key-for-key
        // identical (ConfigTests guards this).
        if inheritsGlobal != Self.defaultInheritsGlobal(for: kind) {
            try container.encode(inheritsGlobal, forKey: .inheritsGlobal)
        }
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
    /// Whether this gesture fires at all. A disabled gesture keeps its stroke, command and position
    /// in the list; the recogniser simply never considers it.
    ///
    /// **This is an extension of this project, not part of the original file format.** WGestures
    /// 2.3.3 has no per-gesture switch (only the trigger matrix), so the key is written **only when
    /// the gesture is disabled** — an enabled gesture emits exactly the original's keys, which is
    /// what keeps `ConfigTests`' "re-encoded file is key-for-key identical" guard passing. The
    /// original app would ignore the extra key and still fire such a gesture; acceptable now that
    /// this project replaces it, and recorded in docs/ROADMAP.md.
    public var enabled: Bool

    public init(
        name: String,
        executeOnRecognize: Bool = false,
        gesture: [WGStep],
        command: WGCommand,
        enabled: Bool = true
    ) {
        self.name = name
        self.executeOnRecognize = executeOnRecognize
        self.gesture = gesture
        self.command = command
        self.enabled = enabled
    }

    public enum CodingKeys: String, CodingKey {
        case name = "Name"
        case executeOnRecognize = "ExecuteOnRecognize"
        case gesture = "Gesture"
        case command = "Command"
        case enabled = "Enabled"
    }

    /// Written by hand so that a missing `Enabled` key means "enabled" — which is the case for every
    /// configuration that exists today.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        executeOnRecognize = try container.decodeIfPresent(Bool.self, forKey: .executeOnRecognize) ?? false
        gesture = try container.decodeIfPresent([WGStep].self, forKey: .gesture) ?? []
        command = try container.decode(WGCommand.self, forKey: .command)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(executeOnRecognize, forKey: .executeOnRecognize)
        try container.encode(gesture, forKey: .gesture)
        try container.encode(command, forKey: .command)
        // Omitted while enabled: the original file has no such key, and the round-trip guard in
        // ConfigTests requires key-for-key equality with it.
        if !enabled {
            try container.encode(false, forKey: .enabled)
        }
    }

    /// The steps before the stroke: the trigger itself and any leading conditions.
    public var triggerSteps: [WGStep] { gesture.prefix { !$0.isStroke }.map { $0 } }

    /// Whether this build can actually fire this gesture.
    ///
    /// Screen-edge/corner and scroll triggers are **not implemented** —
    /// `GestureRecognizer.isTriggerSatisfied` rejects them outright — so such a gesture is stored and
    /// preserved faithfully but can never match. The settings list hides these entries by default
    /// (with a count and a way to reveal them), because a gesture that looks configured and never
    /// fires is worse than one that is clearly parked.
    public var hasSupportedTrigger: Bool {
        let trigger = triggerSteps
        guard !trigger.isEmpty else { return false }
        var sawButton = false
        for step in trigger {
            guard case .keyDown(let key) = step,
                  case .mouse = WGInputToken(key: key.key)
            else { return false }
            sawButton = true
        }
        return sawButton
    }

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
    /// `true` for a straight/simple stroke quantised to the 50-unit grid; `false` for a shape
    /// recorded free-hand, whose points are whatever the user's hand did.
    ///
    /// The flag changes how a stroke is *matched* (grid shapes want a looser tolerance) but not
    /// how it is decoded — see `drawingOrderPoints`.
    public var isSimple: Bool
    /// Flat `x, y, x, y, …` list, **in drawing order** — the first pair is where the stroke
    /// starts, which is exactly the point WGestures draws its trigger symbol on.
    ///
    /// The stored coordinates use the mathematical convention with **y growing upwards**, for
    /// simple and arbitrary strokes alike, while `CGEvent.location` (and therefore `Stroke`) uses
    /// screen coordinates with y growing downwards. `drawingOrderPoints` does the flip.
    public var points: [Int]

    public init(isSimple: Bool, points: [Int]) {
        self.isSimple = isSimple
        self.points = points
    }

    public enum CodingKeys: String, CodingKey {
        case isSimple = "IsSimple"
        case points = "P"
    }

    /// The trajectory as points in screen orientation (y downwards), ready to be compared with
    /// a live `Stroke`.
    ///
    /// **Both** stroke kinds store y with the opposite sign to the screen: simple strokes on the
    /// 50-unit grid and recorded arbitrary shapes alike. Only one coordinate convention for one
    /// `StrokeStep` type makes sense, and the user's own report settles it — treating arbitrary
    /// shapes as raw screen coordinates turned out to swap two of their gestures, because the two
    /// shapes are vertical mirrors of each other and the recogniser cannot confuse them (they are
    /// more than 0.3 apart). A y flip maps one onto the other exactly.
    public var drawingOrderPoints: [CGPoint] {
        stride(from: 0, to: points.count - 1, by: 2).map { index in
            CGPoint(x: CGFloat(points[index]), y: -CGFloat(points[index + 1]))
        }
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

    public var strokeStep: WGStrokeStep? {
        if case .stroke(let step) = self { return step }
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

    /// The `NX_KEYTYPE_*` value these keys are delivered as. Media and brightness keys are not
    /// regular key codes; they travel as `systemDefined` events.
    public var nxKeyType: Int {
        switch self {
        case .volumeUp: 0 // NX_KEYTYPE_SOUND_UP
        case .volumeDown: 1 // NX_KEYTYPE_SOUND_DOWN
        case .brightnessUp: 2 // NX_KEYTYPE_BRIGHTNESS_UP
        case .brightnessDown: 3 // NX_KEYTYPE_BRIGHTNESS_DOWN
        case .mute: 7 // NX_KEYTYPE_MUTE
        case .playPause: 16 // NX_KEYTYPE_PLAY
        case .nextTrack: 17 // NX_KEYTYPE_NEXT
        case .previousTrack: 18 // NX_KEYTYPE_PREVIOUS
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

// MARK: - Direction description

extension WGStrokeStep {
    /// Human-readable direction sequence in drawing order, e.g. `下→右`.
    ///
    /// Directions are named from the user's point of view on screen. Used by tests and later by
    /// the settings UI; it is the cheapest way to check an encoding change against the
    /// gestures a user actually recognises.
    public var directionDescription: String {
        let path = drawingOrderPoints
        guard path.count >= 2 else { return "（单点）" }

        var parts: [String] = []
        for (from, to) in zip(path, path.dropFirst()) {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let horizontal = dx > 0 ? "右" : (dx < 0 ? "左" : "")
            let vertical = dy > 0 ? "下" : (dy < 0 ? "上" : "")
            let piece = vertical + horizontal
            guard !piece.isEmpty else { continue }
            if parts.last != piece { parts.append(piece) }
        }

        let isClosed = path.count > 2 && path.first == path.last
        return parts.joined(separator: "→") + (isClosed ? "（闭环）" : "")
    }
}
