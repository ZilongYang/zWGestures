import CoreGraphics
import Foundation

/// One executable step.
public enum WGPlannedAction: Sendable, Equatable {
    /// Hold `modifiers`, press `keyCode`, release everything.
    case keyStroke(modifiers: [CGKeyCode], flags: CGEventFlags, keyCode: CGKeyCode)
    /// A step that only holds modifiers — rare, but it happens.
    case modifierOnly(flags: CGEventFlags)
    /// Run through `/bin/sh -c`.
    case runShellScript(String)
    /// `{0}` is substituted with the search terms, or with the selected URL.
    case webSearch(template: String)
    case systemFunction(WGSystemFunction)
}

public struct WGCommandPlan: Sendable, Equatable {
    /// Whether the target application should be brought forward first.
    ///
    /// WGestures' 这是一个系统快捷键 option means "this is a global shortcut, do not activate
    /// the target first", so a `KeySeqCommand` activates unless `IsSystemHotKey` is set.
    public var activateTargetFirst: Bool
    public var actions: [WGPlannedAction]
    /// Anything that prevented a clean plan, reported rather than silently dropped.
    public var problems: [String]

    public var isExecutable: Bool { !actions.isEmpty }
}

/// Turns a configuration command into executable steps.
///
/// Pure on purpose: the mapping from configuration to key codes is the part most likely to be
/// wrong, and it is much easier to test than a synthetic key press.
public enum WGCommandPlanner {
    public static func plan(_ command: WGCommand) -> WGCommandPlan {
        switch command {
        case .keySequence(let sequence):
            return planKeySequence(sequence)
        case .systemFunctionKey(let function):
            guard let resolved = function.function else {
                return WGCommandPlan(
                    activateTargetFirst: false,
                    actions: [],
                    problems: ["未知的系统功能键索引 \(function.selectedIndex)"]
                )
            }
            return WGCommandPlan(activateTargetFirst: false, actions: [.systemFunction(resolved)], problems: [])
        case .shellScript(let script):
            return WGCommandPlan(activateTargetFirst: false, actions: [.runShellScript(script.script)], problems: [])
        case .webSearch(let search):
            return WGCommandPlan(activateTargetFirst: false, actions: [.webSearch(template: search.searchEngine)], problems: [])
        case .unknown(let type):
            return WGCommandPlan(activateTargetFirst: false, actions: [], problems: ["不支持的命令类型 \(type)"])
        }
    }

    static func planKeySequence(_ command: WGKeySequenceCommand) -> WGCommandPlan {
        var actions: [WGPlannedAction] = []
        var problems: [String] = []

        for (index, step) in command.steps.enumerated() {
            var modifiers: [CGKeyCode] = []
            var flags: CGEventFlags = []
            var mainKey: CGKeyCode?
            var unrecognised: [String] = []

            for name in step {
                switch WGKeyCode.classify(name) {
                case .modifier(let modifierFlag, let code):
                    flags.insert(modifierFlag)
                    modifiers.append(code)
                case .key(let code):
                    if mainKey == nil {
                        mainKey = code
                    } else {
                        unrecognised.append(name)
                    }
                case .unknown:
                    unrecognised.append(name)
                }
            }

            if !unrecognised.isEmpty {
                problems.append("第 \(index + 1) 步里有无法识别的键名：\(unrecognised.joined(separator: "、"))")
            }
            if let mainKey {
                actions.append(.keyStroke(
                    modifiers: canonicalModifierOrder(modifiers),
                    flags: flags,
                    keyCode: mainKey
                ))
            } else if !modifiers.isEmpty {
                actions.append(.modifierOnly(flags: flags))
            }
        }

        return WGCommandPlan(
            // 这是 WGestures 的语义：IsSystemHotKey 为真表示「这是一个系统快捷键」，
            // 执行前**不**激活目标应用。
            activateTargetFirst: !command.isSystemHotKey && !actions.isEmpty,
            actions: actions,
            problems: problems
        )
    }

    /// Configurations write modifiers in whatever order the user recorded them
    /// (`["Command","Shift","ANSI_T"]` and `["Shift","Command","ANSI_T"]` both occur). Sorting
    /// into the conventional ⌃⌥⇧⌘ order makes the plan deterministic, which keeps it testable
    /// and keeps the physical key-press order the same everywhere.
    static func canonicalModifierOrder(_ modifiers: [CGKeyCode]) -> [CGKeyCode] {
        var seen: Set<CGKeyCode> = []
        return modifiers
            .filter { seen.insert($0).inserted }
            .sorted { modifierRank($0) < modifierRank($1) }
    }

    private static func modifierRank(_ code: CGKeyCode) -> Int {
        switch code {
        case 0x3B, 0x3E: 0 // Control
        case 0x3A, 0x3D: 1 // Option
        case 0x38, 0x3C: 2 // Shift
        case 0x37, 0x36: 3 // Command
        case 0x39: 4 // CapsLock
        case 0x3F: 5 // Function
        default: 6
        }
    }

    /// The name shown in the UI for a command, for gesture lists and the debug HUD.
    /// Forwards to `WGCommand.summary` so the settings list and this log line always agree.
    public static func summary(of command: WGCommand) -> String {
        command.summary
    }
}
