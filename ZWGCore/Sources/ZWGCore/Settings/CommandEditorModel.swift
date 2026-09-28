import CoreGraphics
import Foundation

/// Editing state for one gesture's command.
///
/// Like `SettingsModel`, this lives in `ZWGCore` so that every rule about what a valid command
/// looks like is covered by `swift test`, while the sheet in the app target stays a renderer. The
/// model never writes to disk: it produces a `WGCommand` that the caller hands to `SettingsModel`.
///
/// An `unknown` command type is surfaced as an error state rather than silently reinterpreted as
/// one of the four known kinds — the original configuration may contain commands this build does
/// not understand, and quietly replacing one would be data loss. The user has to pick a kind
/// deliberately (`beginReplacingUnknownCommand`) before the editor will produce a replacement.
@MainActor
public final class CommandEditorModel: ObservableObject {
    /// The command kinds this build can edit, in the order the picker shows them.
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case keySequence
        case webSearch
        case shellScript
        case systemFunctionKey

        public var id: String { rawValue }

        public var localizedName: String {
            switch self {
            case .keySequence: "按键序列"
            case .webSearch: "Web 搜索"
            case .shellScript: "Shell 脚本"
            case .systemFunctionKey: "系统功能键"
            }
        }

        public static func of(_ command: WGCommand) -> Kind? {
            switch command {
            case .keySequence: .keySequence
            case .webSearch: .webSearch
            case .shellScript: .shellScript
            case .systemFunctionKey: .systemFunctionKey
            case .unknown: nil
            }
        }
    }

    /// The command as it was when the editor opened, for change detection and revert.
    private let original: WGCommand

    @Published public private(set) var kind: Kind
    /// The stored flat key list, `nil` marking a step boundary.
    @Published public private(set) var keys: [String?]
    @Published public var isSystemHotKey: Bool
    @Published public var searchEngine: String
    @Published public var script: String
    @Published public var functionIndex: Int

    /// Non-nil when the command on disk is a type this build cannot edit.
    public private(set) var unknownTypeName: String?

    public init(command: WGCommand) {
        original = command
        switch command {
        case .keySequence(let sequence):
            kind = .keySequence
            keys = sequence.keys
            isSystemHotKey = sequence.isSystemHotKey
            searchEngine = ""
            script = ""
            functionIndex = WGSystemFunction.volumeUp.rawValue

        case .webSearch(let search):
            kind = .webSearch
            keys = []
            isSystemHotKey = false
            searchEngine = search.searchEngine
            script = ""
            functionIndex = WGSystemFunction.volumeUp.rawValue

        case .shellScript(let shell):
            kind = .shellScript
            keys = []
            isSystemHotKey = false
            searchEngine = ""
            script = shell.script
            functionIndex = WGSystemFunction.volumeUp.rawValue

        case .systemFunctionKey(let function):
            kind = .systemFunctionKey
            keys = []
            isSystemHotKey = false
            searchEngine = ""
            script = ""
            functionIndex = function.selectedIndex

        case .unknown(let type):
            // Start on a usable kind, but stay in the "unknown" error state until acknowledged.
            kind = .keySequence
            keys = []
            isSystemHotKey = false
            searchEngine = ""
            script = ""
            functionIndex = WGSystemFunction.volumeUp.rawValue
            unknownTypeName = type
        }
    }

    // MARK: - Unknown command handling

    /// Whether the command currently on disk is an unsupported type that would be replaced.
    public var isReplacingUnknownCommand: Bool { unknownTypeName != nil }

    /// Acknowledges replacing a command type this build does not understand.
    public func beginReplacingUnknownCommand() {
        unknownTypeName = nil
    }

    // MARK: - Key sequence editing

    /// The key list split into steps, each step being the keys pressed together.
    public var keySteps: [[String]] {
        let sequence = WGKeySequenceCommand(isSystemHotKey: isSystemHotKey, keys: keys)
        return sequence.steps
    }

    /// One-line rendering of the sequence, e.g. `⌘+V ↩`.
    public var keySequenceSummary: String {
        WGCommand.keySequence(WGKeySequenceCommand(isSystemHotKey: isSystemHotKey, keys: keys)).summary
    }

    /// Replaces the whole sequence with a single recorded combination.
    ///
    /// This is what「录制按键」does: a user who clicked "record" expects one hotkey, not one extra
    /// step per press. Adding further steps is a separate, explicit action (`appendStep`).
    ///
    /// - Returns: `false` when `step` is empty, so the caller can keep recording.
    @discardableResult
    public func setSingleStep(_ step: [String]) -> Bool {
        let cleaned = Self.normalized(step)
        guard !cleaned.isEmpty else { return false }
        keys = cleaned
        return true
    }

    /// Appends a recorded step (a set of keys held together) as its own step.
    ///
    /// - Returns: `false` when `step` is empty or already ends the sequence, so the caller can keep
    ///   the recorder open instead of appearing to have accepted something.
    @discardableResult
    public func appendStep(_ step: [String]) -> Bool {
        let cleaned = Self.normalized(step)
        guard !cleaned.isEmpty else { return false }
        var newKeys = keys
        if !newKeys.isEmpty { newKeys.append(nil) } // step separator
        newKeys.append(contentsOf: cleaned)
        keys = newKeys
        return true
    }

    public func removeStep(at index: Int) {
        var steps = keySteps
        guard steps.indices.contains(index) else { return }
        steps.remove(at: index)

        // Rebuild with explicit separators so an emptied list cannot leave a stray `nil`.
        var rebuilt: [String?] = []
        for step in steps where !step.isEmpty {
            if !rebuilt.isEmpty { rebuilt.append(nil) }
            rebuilt.append(contentsOf: step)
        }
        keys = rebuilt
    }

    public func clearKeys() {
        keys = []
    }

    /// Modifiers first, de-duplicated, then the non-modifier key — the order the original app
    /// writes (`Command`, `ANSI_V`).
    static func normalized(_ step: [String]) -> [String] {
        var modifiers: [String] = []
        var others: [String] = []
        for name in step {
            if WGKeyCode.isModifier(name) {
                if !modifiers.contains(name) { modifiers.append(name) }
            } else if !others.contains(name) {
                others.append(name)
            }
        }
        return modifiers + others
    }

    // MARK: - Validation

    /// Whether the current state can be turned into a command.
    public var validationError: String? {
        guard !isReplacingUnknownCommand else {
            return "这条命令的类型（\(unknownTypeName ?? "?")）本版本不认识，直接保存会覆盖它。"
        }
        switch kind {
        case .keySequence:
            return keySteps.isEmpty ? "按键序列至少需要一步（例如 ⌘+C）。" : nil
        case .webSearch:
            let template = searchEngine.trimmingCharacters(in: .whitespacesAndNewlines)
            if template.isEmpty { return "搜索地址不能为空。" }
            if !template.contains("{0}") { return "搜索地址里需要 {0} 占位符，它会被替换成搜索词。" }
            return nil
        case .shellScript:
            return script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "脚本不能为空。" : nil
        case .systemFunctionKey:
            return WGSystemFunction(rawValue: functionIndex) == nil
                ? "请选择一个系统功能键。" : nil
        }
    }

    public var canCommit: Bool { validationError == nil }

    // MARK: - Result

    /// The command the editor currently describes.
    public var command: WGCommand {
        switch kind {
        case .keySequence:
            .keySequence(WGKeySequenceCommand(isSystemHotKey: isSystemHotKey, keys: keys))
        case .webSearch:
            .webSearch(WGWebSearchCommand(
                searchEngine: searchEngine.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        case .shellScript:
            .shellScript(WGShellScriptCommand(script: script))
        case .systemFunctionKey:
            .systemFunctionKey(WGSystemFunctionKeyCommand(selectedIndex: functionIndex))
        }
    }

    public var isDirty: Bool { command != original }

    /// Switches the edited kind, discarding the fields of the previous kind.
    ///
    /// Switching back and forth is lossy for any kind's fields the user already filled in, which
    /// is why the sheet only offers kinds before the first edit of the session; the alternative
    /// (keeping per-kind drafts) would let a user assemble a command they never saw.
    public func setKind(_ newKind: Kind) {
        guard newKind != kind else { return }
        kind = newKind
        switch newKind {
        case .keySequence:
            keys = []
            isSystemHotKey = false
        case .webSearch:
            if searchEngine.isEmpty { searchEngine = "https://www.google.com/search?q={0}" }
        case .shellScript:
            break
        case .systemFunctionKey:
            if WGSystemFunction(rawValue: functionIndex) == nil {
                functionIndex = WGSystemFunction.volumeUp.rawValue
            }
        }
    }
}
