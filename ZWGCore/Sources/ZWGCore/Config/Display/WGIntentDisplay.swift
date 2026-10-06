import Foundation

/// Display helpers shared by the settings UI and the executed-command log line.
extension WGStrokeStep {
    /// Integer units per grid cell in the stored encoding. Both simple and arbitrary strokes use
    /// it, so it doubles as the scale for thumbnail drawing.
    public static var gridUnit: CGFloat { 50 }
}

extension WGTarget {
    /// What the settings sidebar shows for this target.
    public var displayName: String {
        switch kind {
        case .general: L10n.text(.displayGeneralTarget)
        default: name.isEmpty ? L10n.text(.displayUnnamed) : name
        }
    }
}

extension WGIntent {
    /// Human-readable shape of the stroke, e.g. `下→右`.
    public var strokeDescription: String {
        strokeStep?.directionDescription ?? L10n.text(.displayNoStroke)
    }

    /// The 手势修饰键 that follow the stroke — the extra presses that pick one command out of
    /// several sharing the same trajectory.
    public var modifierDescriptions: [String] {
        modifierSteps.compactMap { step in
            switch step {
            case .keyDown(let keyDown):
                WGCommand.describe(inputKey: keyDown.key)
            case .scroll(let scroll):
                scroll.isHorizontal ? L10n.text(.displayScrollHorizontal) : L10n.text(.displayScrollVertical)
            case .moveToEdgeCorner(let corner):
                corner.edgeCorner.mask.localizedName
            case .stroke:
                nil // a second stroke is not a modifier
            case .unknown(let type):
                L10n.format(.displayUnknownStepFormat, type)
            }
        }
    }
}

extension WGCommand {
    /// A compact, human-readable summary for a settings list row.
    ///
    /// This is the single source of truth for command text: `WGCommandPlanner.summary(of:)`
    /// forwards here, so the gesture list and the engine's "executed" log line can never disagree.
    ///
    /// Key names render with the standard macOS symbols where one exists and are printed verbatim
    /// otherwise — the config stores names such as `ANSI_V`, and inventing nicer names would only
    /// make the UI disagree with the file.
    public var summary: String {
        switch self {
        case .keySequence(let command):
            guard !command.steps.isEmpty else { return L10n.text(.displayEmptyKeySequence) }
            return command.steps
                .map { $0.map(Self.keySymbol).joined(separator: "+") }
                .joined(separator: " ")

        case .webSearch(let command):
            let template = command.searchEngine
            guard let host = URL(string: template)?.host else { return L10n.text(.displayWebSearch) }
            return L10n.format(.displayWebSearchHostFormat, host)

        case .shellScript(let command):
            let firstLine = command.script
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? ""
            return firstLine.isEmpty
                ? L10n.text(.displayShellScript)
                : L10n.format(.displayShellScriptFormat, firstLine)

        case .systemFunctionKey(let command):
            return command.function?.localizedName
                ?? L10n.format(.displaySystemFunctionKeyFormat, command.selectedIndex)

        case .unknown(let type):
            return L10n.format(.displayUnsupportedCommandFormat, type)
        }
    }

    /// Describes a `KeyDownStep` key such as `MOUSE:1`, `VSCROLL:-13`, `Command` or `ANSI_C`.
    ///
    /// Scroll signs are read as WGestures stores them: a positive `VSCROLL:n` is an upward
    /// scroll. (`docs/ROADMAP.md` §7 still lists the exact magnitude bucketing as unverified —
    /// that affects matching, not this display.)
    public static func describe(inputKey: String) -> String {
        switch WGInputToken(key: inputKey) {
        case .mouse(let button):
            button.localizedName
        case .verticalScroll(let value):
            value == 0
                ? L10n.text(.displayScrollVertical)
                : L10n.format(value > 0 ? .displayScrollUpFormat : .displayScrollDownFormat, value > 0 ? "↑" : "↓")
        case .horizontalScroll(let value):
            value == 0
                ? L10n.text(.displayScrollHorizontal)
                : L10n.format(value > 0 ? .displayScrollLeftFormat : .displayScrollRightFormat, value > 0 ? "←" : "→")
        case .key(let name):
            keySymbol(name)
        }
    }

    /// The modifier glyphs macOS shows in menus, plus a few common special keys.
    public static func keySymbol(_ key: String) -> String {
        if key.hasPrefix("ANSI_") { return String(key.dropFirst("ANSI_".count)) }
        return switch key {
        case "Command", "Meta": "⌘"
        case "Shift": "⇧"
        case "Option", "Alt": "⌥"
        case "Control", "Ctrl": "⌃"
        case "Return", "Enter": "↩"
        case "Tab": "⇥"
        case "Space": "␣"
        case "Delete", "Backspace": "⌫"
        case "Escape", "Esc": "⎋"
        case "Up", "UpArrow": "↑"
        case "Down", "DownArrow": "↓"
        case "Left", "LeftArrow": "←"
        case "Right", "RightArrow": "→"
        default: key
        }
    }
}
