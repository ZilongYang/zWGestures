import Combine
import Foundation

/// One row of the settings gesture list.
public struct WGGestureRow: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    /// e.g. `下→右`.
    public let direction: String
    /// e.g. `⌘C`.
    public let commandSummary: String
    /// 手势修饰键 such as `鼠标左键`, empty for most gestures.
    public let modifiers: [String]
    public let executeOnRecognize: Bool
    /// Whether this gesture fires. Disabled rows stay in the list, dimmed.
    public let isEnabled: Bool
    /// True for a gesture that belongs to the general set and is only *shown* here because this
    /// target inherits it. Inherited rows are read-only.
    public let isInherited: Bool
    /// False for a gesture this build cannot trigger (edge/corner or scroll triggers are not
    /// implemented). Such rows are hidden unless the user asks to see them.
    public let hasSupportedTrigger: Bool
    /// The trajectory in screen orientation, for the thumbnail.
    public let points: [CGPoint]
    public let isClosed: Bool
    /// Name of the gesture that owns the same trajectory, when there is one.
    ///
    /// A colliding gesture looks perfectly configured and can never fire, so the list marks it
    /// instead of leaving the user to discover it by drawing.
    public let collidingGestureName: String?
}

/// An application that a gesture set can be attached to.
///
/// Comes either from the list of running applications or from a chosen `.app` bundle; both provide
/// the same three facts, which is all `TargetResolver` needs to recognise the app later.
public struct WGAppCandidate: Hashable, Sendable {
    public var name: String
    public var bundleId: String?
    public var path: String?

    public init(name: String, bundleId: String? = nil, path: String? = nil) {
        self.name = name
        self.bundleId = bundleId
        self.path = path
    }

    /// Whether an existing target already covers this application.
    ///
    /// Stricter than `TargetResolver.matchApplication` on purpose. The resolver compares paths only
    /// for targets without a bundle identifier, so a *new* path-only target for an app that already
    /// has an identifier-carrying target would be added but could never win: the identifier pass
    /// runs first and returns the existing one. Since the whole point of this check is to refuse
    /// targets that can never fire, paths are compared here regardless of identifiers — both sides
    /// reduced to their `.app` bundle so `…/Finder.app` and
    /// `…/Finder.app/Contents/MacOS/Finder` count as the same application.
    public func isCovered(by target: WGTarget) -> Bool {
        guard target.kind == .app else { return false }

        let identifier = bundleId?.trimmingCharacters(in: .whitespaces) ?? ""
        if !identifier.isEmpty, target.bundleId == identifier {
            return true
        }

        guard let candidatePath = Self.normalizedBundlePath(path),
              let targetPath = Self.normalizedBundlePath(target.path)
        else { return false }
        return candidatePath == targetPath
    }

    /// The `.app` bundle a path belongs to, or `nil` when there is nothing usable.
    static func normalizedBundlePath(_ path: String?) -> String? {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return TargetResolver.bundlePath(of: trimmed)
    }
}

/// Why an application target could not be added.
public enum WGAddTargetProblem: Error, Equatable {
    /// Another target already covers this application.
    case duplicate(existingName: String)
    /// Neither a bundle identifier nor a path: the app could never be recognised.
    case noIdentity
    /// Nothing usable as a name.
    case missingName

    public var errorDescription: String? {
        switch self {
        case .duplicate(let existingName):
            return "「\(existingName)」已经有自己的手势集了 —— 同一个应用只能有一个目标，否则第二个永远不会被用到。"
        case .noIdentity:
            return "这个应用既没有 Bundle ID 也没有路径，无法识别。"
        case .missingName:
            return "这个应用没有可用的名称。"
        }
    }
}

/// Owns the settings window's editing state.
///
/// Deliberately a plain value-semantics model in `ZWGCore` rather than "logic inside SwiftUI
/// views": every mutation below is covered by `swift test` without launching the app, and the
/// UI stays a thin renderer. It follows the same split the rest of the project uses — testable
/// logic in the package, AppKit/SwiftUI in the app target.
///
/// `ObservableObject` rather than the `@Observable` macro on purpose: the macro needs
/// `swift-plugin-server`, which fails inside this Xcode build ("malformed response"). Plain
/// `ObservableObject` is macro-free and publishes the same changes to SwiftUI.
///
/// The model holds a *working copy* of the configuration and never writes to disk itself;
/// `isDirty` tells the app when there is something to save.
@MainActor
public final class SettingsModel: ObservableObject {
    /// Which target's gestures the editor is showing.
    public enum Selection: Hashable, Sendable {
        case general
        case app(id: String)
        case special(id: String)

        /// Targets whose gesture sets are not shown yet (the groups feature is unimplemented).
        case group(id: String)
    }

    @Published public private(set) var config: WGConfig
    @Published public var selection: Selection
    @Published public private(set) var query: String = ""
    /// Whether gestures this build cannot trigger are listed. Off by default: they would look like
    /// working gestures that mysteriously never fire.
    @Published public var showsUnsupportedGestures: Bool = false

    /// The configuration as it was last loaded or saved, used to detect pending edits.
    private var savedConfig: WGConfig

    public init(config: WGConfig, selection: Selection = .general) {
        self.config = config
        self.savedConfig = config
        self.selection = selection
    }

    // MARK: - Targets

    /// Every target, in the order the sidebar lists them.
    public var targets: [WGTarget] {
        [config.general] + config.groups + config.apps + config.specials
    }

    public var selectedTarget: WGTarget? {
        switch selection {
        case .general: config.general
        case .app(let id): config.apps.first { $0.id == id }
        case .special(let id): config.specials.first { $0.id == id }
        case .group(let id): config.groups.first { $0.id == id }
        }
    }

    public func selection(forIndex index: Int) -> Selection? {
        let all = targets
        guard all.indices.contains(index) else { return nil }
        let target = all[index]
        switch target.kind {
        case .general: return .general
        case .app: return .app(id: target.id)
        case .desktop: return .special(id: target.id)
        case .other: return .group(id: target.id)
        }
    }

    public func selectedIndex(in all: [WGTarget]) -> Int? {
        all.firstIndex { target in
            switch selection {
            case .general: target.kind == .general
            case .app(let id): target.id == id
            case .special(let id): target.id == id
            case .group(let id): target.id == id
            }
        }
    }

    public var selectedTargetName: String? { selectedTarget?.displayName }

    /// How many gestures each target has, matching the sidebar's summary text.
    public var countsByTargetId: [String: Int] {
        Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.intents.count) })
    }

    // MARK: - Rows

    /// The selected target's gestures after applying the search filter.
    ///
    /// When the selected target inherits the general set, the general gestures are listed after its
    /// own (flagged `isInherited`) so the window shows what will actually fire — without that the
    /// user cannot tell an app set apart from a broken one.
    public var rows: [WGGestureRow] {
        guard let target = selectedTarget else { return [] }
        // 继承来的手势同样要按「能否触发」过滤（全局里也有边角/滚轮手势）。
        let inheritedRows = {
            guard target.kind != .general, target.inheritsGlobal else { return [WGGestureRow]() }
            var rows = Self.rows(
                for: config.general,
                matching: query,
                inherited: true,
                idOffset: target.intents.count
            )
            if !showsUnsupportedGestures { rows.removeAll { !$0.hasSupportedTrigger } }
            return rows
        }()
        var listed = Self.rows(for: target, matching: query)
        if !showsUnsupportedGestures {
            listed.removeAll { !$0.hasSupportedTrigger }
        }
        listed += inheritedRows
        return listed
    }

    /// The general gestures shown as inherited rows, for the count in the status line.
    public var inheritedRowCount: Int {
        guard let target = selectedTarget, target.kind != .general, target.inheritsGlobal else { return 0 }
        var rows = Self.rows(for: config.general, matching: query, inherited: true)
        if !showsUnsupportedGestures { rows.removeAll { !$0.hasSupportedTrigger } }
        return rows.count
    }

    /// How many gestures of the selected target (own + inherited) this build cannot trigger, so the
    /// status line can say what is being hidden instead of silently dropping entries.
    public var hiddenUnsupportedCount: Int {
        guard let target = selectedTarget else { return 0 }
        var intents = target.intents
        if target.kind != .general, target.inheritsGlobal {
            intents += config.general.intents
        }
        return intents.filter { !$0.hasSupportedTrigger }.count
    }

    /// Whether the selected target's inheritance can be switched (the general set has no parent).
    public var canToggleInheritance: Bool {
        guard let target = selectedTarget else { return false }
        return target.kind != .general
    }

    /// Whether the selected target currently overlays the general set.
    public var selectedTargetInheritsGlobal: Bool {
        selectedTarget?.inheritsGlobal ?? false
    }

    /// Turns inheritance of the general set on or off for the selected target.
    @discardableResult
    public func setInheritsGlobal(_ inherits: Bool) -> Bool {
        guard let targetIndex = targetIndex(),
              let target = config.target(at: targetIndex),
              target.kind != .general
        else { return false }
        config.mutateTarget(at: targetIndex) { $0.inheritsGlobal = inherits }
        return true
    }

    /// Total number of gestures across every target, for the window's status line.
    public var totalIntentCount: Int {
        config.allTargets.reduce(0) { $0 + $1.intents.count }
    }

    /// Gestures the filter hides from the selected target.
    public var hiddenByFilterCount: Int {
        guard let target = selectedTarget, !query.isEmpty else { return 0 }
        return target.intents.count - rows.count
    }

    public func setQuery(_ newValue: String) {
        query = newValue
    }

    /// How many gestures of the selected target are switched off.
    public var disabledCount: Int {
        selectedTarget?.intents.filter { !$0.enabled }.count ?? 0
    }

    /// Gestures of the selected target that share a trajectory with another gesture, mapped to the
    /// name of the twin they lose against.
    ///
    /// Surfaced as a warning in the list: a collision means one of the two can never fire, and it is
    /// invisible otherwise — the gesture still looks perfectly configured.
    public var shapeCollisions: [Int: String] {
        guard let target = selectedTarget else { return [:] }
        return WGStrokeConflict.collisions(in: target.intents)
    }

    // MARK: - Application targets

    /// Adds a gesture set for an application and returns where it was put, so the caller can select
    /// it.
    public func addApplicationTarget(
        _ candidate: WGAppCandidate
    ) -> Result<Selection, WGAddTargetProblem> {
        let identifier = candidate.bundleId?.trimmingCharacters(in: .whitespaces)
        let path = candidate.path?.trimmingCharacters(in: .whitespaces)
        guard !(identifier ?? "").isEmpty || !(path ?? "").isEmpty else {
            return .failure(.noIdentity)
        }
        if let existing = config.apps.first(where: { candidate.isCovered(by: $0) }) {
            return .failure(.duplicate(existingName: existing.displayName))
        }
        let name = Self.targetName(for: candidate)
        guard !name.isEmpty else { return .failure(.missingName) }

        let target = WGTarget(
            kind: .app,
            id: WGIdentifier.make(),
            name: name,
            bundleId: (identifier ?? "").isEmpty ? nil : identifier,
            path: (path ?? "").isEmpty ? nil : path,
            intents: [],
            triggers: []
        )
        config.apps.append(target)
        return .success(.app(id: target.id))
    }

    /// A readable name: what the app calls itself, else derived from the identifier or file name.
    static func targetName(for candidate: WGAppCandidate) -> String {
        let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if let identifier = candidate.bundleId?.trimmingCharacters(in: .whitespaces), !identifier.isEmpty {
            // "com.apple.Safari" → "Safari"
            return identifier.split(separator: ".").last.map(String.init) ?? identifier
        }
        if let path = candidate.path {
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        return ""
    }

    /// Whether a target can be removed. The general set is the fallback for everything, so it stays.
    public func canRemoveTarget(_ target: Selection) -> Bool {
        switch target {
        case .general: false
        case .app(let id): config.apps.contains { $0.id == id }
        case .special(let id): config.specials.contains { $0.id == id }
        case .group(let id): config.groups.contains { $0.id == id }
        }
    }

    /// Removes a target and everything in it.
    ///
    /// Deliberately does **not** touch the general set: `general` is what applies when nothing more
    /// specific matches, so removing it would leave the user with no gestures at all.
    @discardableResult
    public func removeTarget(_ target: Selection) -> Bool {
        guard canRemoveTarget(target) else { return false }
        switch target {
        case .general:
            return false
        case .app(let id):
            config.apps.removeAll { $0.id == id }
        case .special(let id):
            config.specials.removeAll { $0.id == id }
        case .group(let id):
            config.groups.removeAll { $0.id == id }
        }
        // 删掉的正好是当前选中项时，回到全局。
        clampSelection()
        return true
    }

    /// Every gesture of the selected target, so the editor can check a new shape against them.
    public var selectedTargetIntents: [WGIntent] {
        selectedTarget?.intents ?? []
    }

    /// Builds the list rows for a target, in configuration order.
    public static func rows(
        for target: WGTarget,
        matching query: String = "",
        inherited: Bool = false,
        idOffset: Int = 0
    ) -> [WGGestureRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let collisions = WGStrokeConflict.collisions(in: target.intents)
        return target.intents.enumerated().compactMap { index, intent in
            let row = WGGestureRow(
                id: idOffset + index,
                name: intent.name,
                direction: intent.strokeDescription,
                commandSummary: intent.command.summary,
                modifiers: intent.modifierDescriptions,
                executeOnRecognize: intent.executeOnRecognize,
                isEnabled: intent.enabled,
                isInherited: inherited,
                hasSupportedTrigger: intent.hasSupportedTrigger,
                points: intent.strokeStep?.drawingOrderPoints ?? [],
                isClosed: {
                    let path = intent.strokeStep?.drawingOrderPoints ?? []
                    return path.count > 2 && path.first == path.last
                }(),
                collidingGestureName: collisions[index]
            )
            guard needle.isEmpty || Self.matches(row, needle: needle) else { return nil }
            return row
        }
    }

    /// Case- and diacritic-insensitive match over everything the row displays.
    private static func matches(_ row: WGGestureRow, needle: String) -> Bool {
        let haystack = [row.name, row.direction, row.commandSummary].joined(separator: "\u{1}")
            + "\u{1}" + row.modifiers.joined(separator: "\u{1}")
        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: - Editing

    public var isDirty: Bool { config != savedConfig }

    /// Renames the gesture at `index` of the selected target.
    ///
    /// - Returns: `false` when the name is blank or the index is stale, so a caller can keep the
    ///   text field's old value instead of silently accepting a no-op.
    @discardableResult
    public func renameIntent(at index: Int, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return updateIntent(at: index) { $0.name = trimmed }
    }

    /// Deletes the gesture at `index` of the selected target.
    @discardableResult
    public func deleteIntent(at index: Int) -> Bool {
        guard let targetIndex = targetIndex(),
              let target = config.target(at: targetIndex),
              target.intents.indices.contains(index)
        else { return false }
        config.mutateTarget(at: targetIndex) { target in
            target.intents.remove(at: index)
        }
        clampSelection()
        return true
    }

    /// The configuration with pending edits applied, ready to be written to disk.
    public var editedConfig: WGConfig { config }

    /// Replaces the command of the gesture at `index` of the selected target.
    @discardableResult
    public func setCommand(at index: Int, to command: WGCommand) -> Bool {
        updateIntent(at: index) { $0.command = command }
    }

    /// Stores an edited gesture: replaces the one at `index`, or appends a new one when `index` is
    /// `nil`.
    @discardableResult
    public func apply(intent: WGIntent, at index: Int?) -> Bool {
        if let index {
            return updateIntent(at: index) { $0 = intent }
        }
        guard let targetIndex = targetIndex() else { return false }
        config.mutateTarget(at: targetIndex) { $0.intents.append(intent) }
        return true
    }

    /// The gesture at `index` of the selected target, for seeding an editor.
    public func intent(at index: Int) -> WGIntent? {
        guard let target = selectedTarget, target.intents.indices.contains(index) else { return nil }
        return target.intents[index]
    }

    // MARK: - Priority by order

    /// Whether the gesture at `index` can move by `offset` places (-1 = earlier, +1 = later).
    ///
    /// Order is the user's conflict control: `GestureRecognizer.bestCandidate` prefers the earlier
    /// entry when two gestures share a trajectory, so moving a row changes which one fires.
    public func canMoveIntent(at index: Int, by offset: Int) -> Bool {
        guard let target = selectedTarget else { return false }
        let destination = index + offset
        return target.intents.indices.contains(index) && target.intents.indices.contains(destination)
    }

    /// Moves the gesture at `from` to position `to` within the selected target.
    ///
    /// This is what drag-and-drop reordering needs: a drop reports a destination index, not a
    /// relative offset. `to` is interpreted in the list as it looked before the move, which is what
    /// the user sees while dragging.
    @discardableResult
    public func moveIntent(from: Int, to: Int) -> Bool {
        guard from != to,
              let targetIndex = targetIndex(),
              let target = config.target(at: targetIndex),
              target.intents.indices.contains(from),
              target.intents.indices.contains(to)
        else { return false }
        config.mutateTarget(at: targetIndex) { target in
            let moved = target.intents.remove(at: from)
            target.intents.insert(moved, at: to)
        }
        return true
    }

    /// Moves the gesture at `index` by `offset` places within the selected target.
    ///
    /// - Returns: `false` when the move is out of range, so the UI can keep the buttons disabled
    ///   instead of appearing to do nothing.
    @discardableResult
    public func moveIntent(at index: Int, by offset: Int) -> Bool {
        moveIntent(from: index, to: index + offset)
    }

    /// Enables or disables the gesture at `index` of the selected target.
    ///
    /// A disabled gesture keeps everything — stroke, command, position in the list — and is simply
    /// never considered by the recogniser, so it can be switched back on later.
    @discardableResult
    public func setEnabled(at index: Int, to enabled: Bool) -> Bool {
        updateIntent(at: index) { $0.enabled = enabled }
    }

    /// Toggles WGestures' 识别手势后立即执行 for the gesture at `index`.
    @discardableResult
    public func setExecuteOnRecognize(at index: Int, to value: Bool) -> Bool {
        updateIntent(at: index) { $0.executeOnRecognize = value }
    }

    /// The command of the gesture at `index`, for seeding an editor.
    public func command(at index: Int) -> WGCommand? {
        selectedTarget?.intents.indices.contains(index) == true
            ? selectedTarget?.intents[index].command
            : nil
    }

    /// Copies the gesture at `index` and puts the copy **right after the original**.
    ///
    /// Adjacent placement is deliberate: the list order is the priority order, so a copy sits next
    /// to the gesture it came from and the user can immediately change its shape or move it.
    ///
    /// - Returns: the new gesture's index, or `nil` when `index` is not valid.
    @discardableResult
    public func duplicateIntent(at index: Int) -> Int? {
        guard let targetIndex = targetIndex(),
              let target = config.target(at: targetIndex),
              target.intents.indices.contains(index)
        else { return nil }

        var copy = target.intents[index]
        copy.name = Self.uniqueName(basedOn: copy.name, taken: target.intents.map(\.name))
        config.mutateTarget(at: targetIndex) { target in
            target.intents.insert(copy, at: index + 1)
        }
        return index + 1
    }

    /// `"Copy"` → `"Copy 副本"`, then `"Copy 副本 2"`, … so a name is never duplicated.
    static func uniqueName(basedOn name: String, taken: [String]) -> String {
        let existing = Set(taken)
        let base = "\(name) 副本"
        guard existing.contains(base) else { return base }
        for number in 2...999 where !existing.contains("\(base) \(number)") {
            return "\(base) \(number)"
        }
        return "\(base) \(UUID().uuidString.prefix(4))"
    }

    /// Discards every pending edit and goes back to the last loaded/saved configuration.
    public func revert() {
        config = savedConfig
        clampSelection()
    }

    /// Records that the working copy was written to disk.
    public func markSaved() {
        savedConfig = config
    }

    /// Replaces the working copy with a configuration loaded from elsewhere (a re-import, or a
    /// reload before the window is shown).
    ///
    /// This mutates in place instead of handing back a fresh model because the SwiftUI layer binds
    /// to this object for its lifetime — swapping the instance would leave the window rendering a
    /// stale copy.
    public func load(config newConfig: WGConfig) {
        config = newConfig
        savedConfig = newConfig
        clampSelection()
    }

    /// Whether `selection` currently resolves to a real, unambiguous target.
    public var hasValidSelection: Bool { selectedTarget != nil }

    // MARK: - Private

    private func updateIntent(at index: Int, _ body: (inout WGIntent) -> Void) -> Bool {
        guard let targetIndex = targetIndex() else { return false }
        var didEdit = false
        config.mutateTarget(at: targetIndex) { target in
            guard target.intents.indices.contains(index) else { return }
            body(&target.intents[index])
            didEdit = true
        }
        return didEdit
    }

    /// The row index of the selected target inside `WGConfig.allTargets`, or `nil` when the
    /// selection does not resolve to a target.
    ///
    /// Returning `nil` rather than a fallback index matters: an earlier version computed the
    /// index arithmetically and a stale selection (a target that had since been removed) silently
    /// resolved to a *different* target, so an edit landed on the wrong gesture. Each branch now
    /// proves the target exists in the array it belongs to before returning a position.
    private func targetIndex() -> Int? {
        switch selection {
        case .general:
            return 0

        case .app(let id):
            guard config.apps.contains(where: { $0.id == id }),
                  let offset = config.apps.firstIndex(where: { $0.id == id })
            else { return nil }
            return 1 + config.groups.count + offset

        case .special(let id):
            guard config.specials.contains(where: { $0.id == id }),
                  let offset = config.specials.firstIndex(where: { $0.id == id })
            else { return nil }
            return 1 + config.groups.count + config.apps.count + offset

        case .group(let id):
            guard config.groups.contains(where: { $0.id == id }),
                  let offset = config.groups.firstIndex(where: { $0.id == id })
            else { return nil }
            return 1 + offset
        }
    }

    /// Keeps `selection` pointing at a target that still exists after an edit.
    private func clampSelection() {
        guard selectedTarget == nil else { return }
        selection = .general
    }
}

// MARK: - Index-addressed target access

extension WGConfig {
    /// The targets in the same order as `allTargets`, so an index from the settings list maps
    /// straight onto a mutable target.
    func target(at index: Int) -> WGTarget? {
        let all = allTargets
        guard all.indices.contains(index) else { return nil }
        return all[index]
    }

    /// Applies `body` to the target at `index`, writing it back into the right array (or the
    /// `General` key).
    mutating func mutateTarget(at index: Int, _ body: (inout WGTarget) -> Void) {
        let groupCount = groups.count
        let appCount = apps.count
        switch index {
        case 0:
            body(&general)
        case 1..<(1 + groupCount):
            body(&groups[index - 1])
        case (1 + groupCount)..<(1 + groupCount + appCount):
            body(&apps[index - 1 - groupCount])
        default:
            let specialIndex = index - 1 - groupCount - appCount
            guard specials.indices.contains(specialIndex) else { return }
            body(&specials[specialIndex])
        }
    }
}
