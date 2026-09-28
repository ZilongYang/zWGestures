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
    /// A newly drawn shape, shown in the right column. `nil` means "keep the current shape".
    @Published public private(set) var pendingStroke: WGStrokeStep?

    /// The steps before and after the stroke, kept from the gesture being edited.
    private let leadingSteps: [WGStep]
    private let trailingSteps: [WGStep]

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
    public convenience init(newGestureNamed name: String = "新手势", siblings: [WGIntent] = []) {
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
            format: "这个形状与「%@」相同（距离 %.3f），两条手势抢同一个输入。列表里**靠前的一条优先**："
                + "要让这一条生效，保存后用右键把它「上移」到「%@」前面；否则画这个形状只会触发「%@」。",
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
        currentStroke?.directionDescription ?? "（这条手势原本没有形状）"
    }

    /// What the editor's right column shows.
    public var pendingStrokeDescription: String {
        pendingStroke?.directionDescription ?? "（还没画）"
    }

    /// The shape that will actually be stored.
    public var strokeDescription: String {
        effectiveStroke?.directionDescription ?? "（还没画）"
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
        guard !trimmedName.isEmpty else { return "名字不能为空。" }
        guard effectiveStroke != nil else { return "还没有画出手势形状 —— 点右边的框，在全屏幕上画一个。" }
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
