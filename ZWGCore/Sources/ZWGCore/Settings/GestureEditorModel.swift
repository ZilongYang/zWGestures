import CoreGraphics
import Foundation

/// Editing state for one whole gesture: its stroke, its name and the command it runs.
///
/// A gesture in WGestures is *a trigger plus a trajectory plus an action*: the user draws the shape
/// first and only then decides what it does. This model keeps that order, and it is the reason the
/// stroke is the primary editable thing here rather than a read-only thumbnail next to a command
/// editor.
///
/// Steps that surround the stroke — the trigger button (`MOUSE:1`) and any 手势修饰键 that follow —
/// are preserved verbatim, so re-recording a shape never silently changes how the gesture is
/// triggered. Like the rest of the settings layer this is a plain model in `ZWGCore`, fully covered
/// by `swift test`; the sheet only renders it.
@MainActor
public final class GestureEditorModel: ObservableObject {
    public enum Mode: Equatable, Sendable {
        /// Re-editing the gesture at this index of the selected target.
        case existing(index: Int)
        /// Adding a new gesture to the selected target.
        case new
    }

    /// The trigger used for a brand-new gesture: WGestures' right mouse button.
    ///
    /// Right-button gestures are the only trigger this build implements, so offering anything else
    /// here would create a gesture that can never fire.
    public static let defaultTriggerSteps: [WGStep] = [.keyDown(WGKeyDownStep(key: MouseButton.right.legacyToken))]

    public let mode: Mode
    public let commandEditor: CommandEditorModel

    @Published public var name: String
    @Published public var executeOnRecognize: Bool
    /// Whether the gesture fires at all; a disabled gesture is kept but never matched.
    @Published public var enabled: Bool
    /// The shape the gesture has **right now**, shown in the editor's left column.
    @Published public private(set) var currentStroke: WGStrokeStep?
    /// True when the gesture's trigger is one this build cannot fire (screen edge/corner or scroll).
    /// The editor says so plainly rather than letting the user polish a shape that will never run.
    public let hasUnsupportedTrigger: Bool
    /// A newly drawn shape, shown in the right column. `nil` means "keep the current shape".
    @Published public private(set) var pendingStroke: WGStrokeStep?

    /// The steps before the stroke, kept from the gesture being edited (the trigger).
    private let leadingSteps: [WGStep]
    /// The 手势修饰键 after the stroke. Editable: this is what lets a new gesture say "same shape,
    /// but while also holding the left button".
    @Published private var trailingSteps: [WGStep]

    /// The other gestures of the same set, used to refuse a shape that is already taken.
    private let siblings: [WGIntent]

    /// The index being edited inside `siblings`, so the shape is not compared with itself.
    private let editingIndex: Int?

    public init(
        mode: Mode,
        intent: WGIntent?,
        name: String,
        command: WGCommand,
        siblings: [WGIntent] = []
    ) {
        self.mode = mode
        self.name = name
        self.executeOnRecognize = intent?.executeOnRecognize ?? false
        self.enabled = intent?.enabled ?? true
        self.currentStroke = intent?.strokeStep
        self.pendingStroke = nil
        self.hasUnsupportedTrigger = intent.map { !$0.hasSupportedTrigger } ?? false
        self.commandEditor = CommandEditorModel(command: command)
        self.siblings = siblings
        if case .existing(let index) = mode {
            editingIndex = index
        } else {
            editingIndex = nil
        }

        if let intent {
            leadingSteps = intent.triggerSteps
            trailingSteps = intent.modifierSteps
        } else {
            leadingSteps = Self.defaultTriggerSteps
            trailingSteps = []
        }
    }

    // MARK: - 手势修饰键

    /// The gesture modifiers that are currently part of this gesture.
    ///
    /// A step this build cannot offer (a horizontal scroll, say) is dropped from the list rather
    /// than shown as something uneditable — but it is **kept in `gestureSteps`**, so opening and
    /// saving a gesture never silently deletes a step somebody else wrote.
    public var modifiers: [WGModifierKind] {
        trailingSteps.compactMap { step in
            guard let key = step.keyDown?.key else { return nil }
            return WGModifierKind(key: key)
        }
    }

    /// Whether adding `kind` would change anything.
    public func canAddModifier(_ kind: WGModifierKind) -> Bool {
        !modifiers.contains(kind)
    }

    /// Adds a 手势修饰键.
    ///
    /// - Returns: `false` when it is already present, so a menu can simply disable that entry.
    ///
    /// The step is appended after the existing ones. WGestures describes these as presses made
    /// *while* drawing, and this build accepts them any time before the button is released — the
    /// exact timing has never been checked against the original (ROADMAP §7), so nothing here
    /// depends on it.
    @discardableResult
    public func addModifier(_ kind: WGModifierKind) -> Bool {
        guard canAddModifier(kind) else { return false }
        trailingSteps.append(kind.step)
        return true
    }

    public func removeModifier(_ kind: WGModifierKind) {
        trailingSteps.removeAll { step in
            guard let key = step.keyDown?.key else { return false }
            return key == kind.key
        }
    }

    /// Convenience for re-editing an existing gesture.
    public convenience init(mode: Mode, intent: WGIntent, siblings: [WGIntent] = []) {
        self.init(
            mode: mode,
            intent: intent,
            name: intent.name,
            command: intent.command,
            siblings: siblings
        )
    }

    /// Convenience for a brand-new gesture: right-button trigger, no stroke, empty key sequence.
    public convenience init(newGestureNamed name: String = L10n.text(.gestureNewName), siblings: [WGIntent] = []) {
        self.init(
            mode: .new,
            intent: nil,
            name: name,
            command: .keySequence(WGKeySequenceCommand(isSystemHotKey: false, keys: [])),
            siblings: siblings
        )
    }

    // MARK: - Shape conflicts

    /// The gesture that would beat this one when the shape is drawn, if any.
    ///
    /// Two gestures cannot share a trajectory: the matcher picks one and the other silently never
    /// fires. Refusing the edit here is the only way to keep "stored" and "can actually trigger"
    /// the same thing — a collision created by a re-recorded 「Copy」 against an existing
    /// 「Forward」 is exactly the bug this prevents.
    public var shapeConflict: WGStrokeConflict.Twin? {
        guard effectiveStroke != nil else { return nil }
        return WGStrokeConflict.nearestTwin(
            toCandidate: intent,
            in: siblings,
            excluding: editingIndex
        )
    }

    /// A sentence naming the gesture that owns this shape, for the editor to show.
    public var shapeConflictDescription: String? {
        guard let conflict = shapeConflict else { return nil }
        return String(
            format: L10n.text(.gestureConflictFormat),
            conflict.name, Double(conflict.distance), conflict.name, conflict.name
        )
    }

    // MARK: - Stroke

    /// The shape the gesture will end up with: the newly drawn one when there is one, otherwise the
    /// one it already had.
    public var effectiveStroke: WGStrokeStep? { pendingStroke ?? currentStroke }

    /// Whether the user has drawn a shape that would replace the current one.
    public var hasPendingStroke: Bool { pendingStroke != nil }

    /// The trajectory as the configuration will store it, with the leading and trailing steps back
    /// in place: `[触发, 笔画, 手势修饰键…]`.
    public var gestureSteps: [WGStep] {
        guard let effectiveStroke else { return leadingSteps }
        return leadingSteps + [.stroke(effectiveStroke)] + trailingSteps
    }

    /// What the editor's left column shows.
    public var currentStrokeDescription: String {
        currentStroke?.directionDescription ?? L10n.text(.gestureNoOriginalShape)
    }

    /// What the editor's right column shows.
    public var pendingStrokeDescription: String {
        pendingStroke?.directionDescription ?? L10n.text(.gestureNothingDrawn)
    }

    /// The shape that will actually be stored.
    public var strokeDescription: String {
        effectiveStroke?.directionDescription ?? L10n.text(.gestureNothingDrawn)
    }

    /// Records a drawing from the canvas.
    ///
    /// - Parameter screenPoints: trajectory in screen orientation (y downwards), drawing order.
    /// - Returns: a message to show when the drawing was rejected, `nil` on success.
    @discardableResult
    public func recordStroke(screenPoints: [CGPoint]) -> String? {
        do {
            pendingStroke = try WGStrokeRecorder.encode(screenPoints: screenPoints)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Throws away the newly drawn shape. The gesture keeps the shape it already had — this is the
    /// 「不想修改手势」exit.
    public func discardPendingStroke() {
        pendingStroke = nil
    }

    /// Kept for the new-gesture flow, where there is no shape to fall back to.
    public func clearStroke() {
        pendingStroke = nil
        currentStroke = nil
    }

    /// The live direction text while the user is still drawing, e.g. `下→右`.
    public func liveDescription(screenPoints: [CGPoint]) -> String {
        WGStrokeRecorder.directionPreview(screenPoints: screenPoints)
    }

    // MARK: - Result

    /// Whether everything needed to store this gesture is present.
    public var validationError: String? {
        guard !trimmedName.isEmpty else { return L10n.text(.gestureNameEmpty) }
        guard effectiveStroke != nil else { return L10n.text(.gestureShapeMissing) }
        // A collision is no longer a refusal: the list order decides which entry wins, so the user
        // can keep both and reorder. The warning is shown next to the shape instead.
        return commandEditor.validationError
    }

    public var canCommit: Bool { validationError == nil }

    /// The gesture to store.
    public var intent: WGIntent {
        WGIntent(
            name: trimmedName,
            executeOnRecognize: executeOnRecognize,
            gesture: gestureSteps,
            command: commandEditor.command,
            enabled: enabled
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
