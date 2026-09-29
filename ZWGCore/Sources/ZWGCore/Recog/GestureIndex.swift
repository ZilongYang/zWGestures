import CoreGraphics
import Foundation

/// What a 手势修饰键 requires of the recorded event stream, parsed once.
///
/// `WGInputToken(key:)` parses a string such as `MOUSE:1` or `VSCROLL:-3`, and it used to run once per
/// modifier step per gesture **per event**. Parsing it here instead is what makes the scoring loop
/// free of string work and allocations.
public enum ModifierRequirement: Sendable, Equatable {
    case button(MouseButton)
    /// Scroll direction: -1, 0 or 1. The axis is deliberately not part of the identity —
    /// `WGInputToken.scrollDirection` reads `deltaY` for horizontal scrolls too, which is the
    /// pre-existing behaviour (docs/ROADMAP.md §7). Preserving it keeps matching bit-for-bit identical.
    case scroll(direction: Int)
    /// A step this build can never satisfy (a keyboard modifier), so the gesture can never match.
    case impossible
}

/// One gesture with everything the matcher needs already computed.
///
/// Before this existed, every candidate re-split its step list on every access
/// (`WGIntent.triggerSteps` and `.modifierSteps` each build a fresh array, and `.modifierSteps` was
/// read twice), re-parsed its trigger and modifier key strings, rebuilt its trigger signature — which
/// allocated a token array *before* `WGTriggerMatrix.allows` could short-circuit on an empty matrix —
/// and re-normalised its stored trajectory (a `[Int]` → `[CGPoint]` conversion plus four more arrays
/// inside `normalize`). At roughly eight allocations per candidate and ~45 candidates, one recognition
/// cost about 1.5 ms **on the event-tap thread**, whose callback the system waits for.
/// See docs/ROADMAP.md §18.
public struct PreparedGesture: Sendable {
    public var intent: WGIntent
    /// Index into the original `WGTarget.intents`, which is what the list-order tie-break uses.
    public var intentIndex: Int
    /// The stored trajectory, already normalised to the index's `sampleCount`.
    public var shape: [CGPoint]
    /// The mouse button the trigger requires. `nil` never appears: a gesture whose trigger this build
    /// cannot fire is left out of the index entirely, because it could never be a candidate.
    public var triggerButton: MouseButton
    /// Pre-built signature for the trigger matrix. Building it per event was pure waste whenever the
    /// matrix was empty, which is the common case.
    public var triggerSignature: WGTriggerSignature?
    public var modifierRequirements: [ModifierRequirement]

    public var modifierCount: Int { modifierRequirements.count }
}

extension PreparedGesture {
    /// Prepares one gesture, or returns `nil` when it could never match.
    ///
    /// A disabled gesture, a gesture with no stroke (or a stroke that cannot be normalised), and one
    /// whose trigger this build cannot fire are all excluded here rather than filtered out on every
    /// event — the answer cannot change while the configuration does not.
    init?(intent: WGIntent, intentIndex: Int, settings: RecognitionSettings) {
        guard intent.enabled, let stroke = intent.strokeStep else { return nil }
        let shape = StrokeNormalizer.normalize(
            stroke.drawingOrderPoints,
            sampleCount: settings.sampleCount
        )
        guard shape.count == settings.sampleCount else { return nil }

        let triggers = intent.triggerSteps
        guard let button = Self.triggerButton(of: triggers) else { return nil }

        self.intent = intent
        self.intentIndex = intentIndex
        self.shape = shape
        triggerButton = button
        triggerSignature = WGTriggerSignature.make(from: triggers)
        modifierRequirements = Self.modifierRequirements(of: intent.modifierSteps)
    }

    /// The mouse button the trigger steps require, or `nil` when this build cannot fire the trigger.
    ///
    /// Mirrors the runtime rule exactly: the trigger must be non-empty, every step must be a mouse
    /// `KeyDownStep`, and they must all name the same button.
    static func triggerButton(of steps: [WGStep]) -> MouseButton? {
        guard !steps.isEmpty else { return nil }
        var required: MouseButton?
        for step in steps {
            guard case .keyDown(let key) = step,
                  case .mouse(let candidate) = WGInputToken(key: key.key)
            else { return nil }
            if let required, required != candidate { return nil }
            required = candidate
        }
        return required
    }

    static func modifierRequirements(of steps: [WGStep]) -> [ModifierRequirement] {
        steps.map { step in
            guard case .keyDown(let key) = step else { return .impossible }
            let token = WGInputToken(key: key.key)
            switch token {
            case .mouse(let button):
                return .button(button)
            case .verticalScroll, .horizontalScroll:
                guard let direction = token.scrollDirection else { return .impossible }
                return .scroll(direction: direction)
            case .key:
                return .impossible
            }
        }
    }
}

/// A target's gestures in the form the event-tap thread can score cheaply.
///
/// Building this is the expensive half — it splits step lists, parses key strings and normalises every
/// stored shape — and that is exactly why it is built **once per configuration change, on the main
/// thread**, and never inside the tap callback.
public struct GestureIndex: Sendable {
    public var settings: RecognitionSettings
    public var gestures: [PreparedGesture]

    public init(target: WGTarget, settings: RecognitionSettings = RecognitionSettings()) {
        self.settings = settings
        gestures = target.intents.enumerated().compactMap { index, intent in
            PreparedGesture(intent: intent, intentIndex: index, settings: settings)
        }
    }
}

/// Prebuilt indexes for every target a configuration can resolve to.
///
/// Keyed by `WGTarget.id`. `TargetResolver.effectiveTarget` guarantees the id a resolution returns is
/// one of the ids built here — an inheriting application target keeps its own id while its intent list
/// is the merged one — so the tap thread only ever does a dictionary lookup.
public struct RecognitionIndex: Sendable {
    public let settings: RecognitionSettings
    private var byTargetID: [String: GestureIndex]

    public init(config: WGConfig, settings: RecognitionSettings = RecognitionSettings()) {
        self.settings = settings
        var built: [String: GestureIndex] = [:]
        for target in config.allTargets {
            let effective = TargetResolver.effectiveTarget(for: target, in: config)
            built[effective.id] = GestureIndex(target: effective, settings: settings)
        }
        byTargetID = built
    }

    public func index(for resolved: WGResolvedTarget) -> GestureIndex? {
        byTargetID[resolved.target.id]
    }

    /// Total prepared gestures across every target, for logging and tests.
    public var gestureCount: Int {
        byTargetID.values.reduce(0) { $0 + $1.gestures.count }
    }
}
