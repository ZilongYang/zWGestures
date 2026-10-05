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
    ///
    /// Used by the arc-length metric (retracing gestures) and kept for diagnostics; the structure
    /// metric does not need it.
    public var shape: [CGPoint]
    /// The corner structure, precomputed for the structure metric.
    public var structure: StrokeStructure?
    /// Which metric this gesture is scored with, derived from its own stored shape.
    public var metric: StrokeMetric
    /// The mouse button the trigger requires. `nil` never appears: a gesture whose trigger this build
    /// cannot fire is left out of the index entirely, because it could never be a candidate.
    public var triggerButton: MouseButton
    /// Pre-built signature for the trigger matrix. Building it per event was pure waste whenever the
    /// matrix was empty, which is the common case.
    public var triggerSignature: WGTriggerSignature?
    public var modifierRequirements: [ModifierRequirement]

    public var modifierCount: Int { modifierRequirements.count }

    /// Distance from a live stroke (already normalised / already reduced) to this gesture.
    ///
    /// The live side is passed in precomputed because it is identical for every candidate: only
    /// the stored side differs here.
    func distance(
        liveArc: [CGPoint],
        liveStructure: StrokeStructure?,
        settings: RecognitionSettings
    ) -> CGFloat {
        switch metric {
        case .arcLength:
            return StrokeMatcher.distance(liveArc, shape)

        case .structure:
            guard let liveStructure, let structure else { return .infinity }
            return StrokeStructure.distance(liveStructure, structure, settings: settings.structure)
        }
    }
}

extension PreparedGesture {
    /// Prepares one gesture, or returns `nil` when it could never match.
    ///
    /// A disabled gesture, a gesture with no stroke (or a stroke that cannot be normalised), and one
    /// whose trigger this build cannot fire are all excluded here rather than filtered out on every
    /// event — the answer cannot change while the configuration does not.
    init?(intent: WGIntent, intentIndex: Int, settings: RecognitionSettings) {
        guard intent.enabled, let stroke = intent.strokeStep else { return nil }
        let drawingOrderPoints = stroke.drawingOrderPoints
        let shape = StrokeNormalizer.normalize(
            drawingOrderPoints,
            sampleCount: settings.sampleCount
        )
        guard shape.count == settings.sampleCount else { return nil }

        let triggers = intent.triggerSteps
        guard let button = Self.triggerButton(of: triggers) else { return nil }

        let metric = StrokeMatching.metric(forStoredPoints: drawingOrderPoints)
        let structure = metric == .structure
            ? StrokeStructure.make(from: drawingOrderPoints, settings: settings.structure)
            : nil
        // A structure gesture whose stored shape cannot be reduced to a structure could never
        // match anything, so leaving it in the index would only cost time per event.
        if metric == .structure, structure == nil { return nil }

        self.intent = intent
        self.intentIndex = intentIndex
        self.shape = shape
        self.structure = structure
        self.metric = metric
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

    /// Whether any gesture here is scored by structure — lets the hot path skip computing the
    /// live stroke's structure when it would be wasted.
    public var usesStructure: Bool

    public init(target: WGTarget, settings: RecognitionSettings = RecognitionSettings()) {
        self.settings = settings
        gestures = target.intents.enumerated().compactMap { index, intent in
            PreparedGesture(intent: intent, intentIndex: index, settings: settings)
        }
        usesStructure = gestures.contains { $0.metric == .structure }
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

/// Keeps a built `RecognitionIndex` and hands it back until the configuration actually changes.
///
/// The distinction this type exists to enforce: the *application directory* is refreshed every few
/// seconds (and on every app switch), but the *index* only depends on the configuration. Rebuilding
/// it on the directory path put roughly a millisecond of work on the main actor every three
/// seconds — on the very path a finished gesture travels to reach its command — which showed up as
/// the action occasionally firing a beat late (docs/ROADMAP.md §21).
///
/// `buildCount` makes that observable: a test (and the debug HUD) can assert that a directory
/// refresh does not move it.
public struct RecognitionIndexCache: Sendable {
    public private(set) var buildCount = 0
    private var configuration: WGConfig?
    private var settings: RecognitionSettings?
    private var index: RecognitionIndex?

    public init() {}

    /// - Returns: the index for this configuration, and whether it had to be built.
    public mutating func index(
        for configuration: WGConfig,
        settings: RecognitionSettings = RecognitionSettings()
    ) -> (index: RecognitionIndex, rebuilt: Bool) {
        if let index, self.configuration == configuration, self.settings == settings {
            return (index, false)
        }
        let built = RecognitionIndex(config: configuration, settings: settings)
        self.configuration = configuration
        self.settings = settings
        self.index = built
        buildCount += 1
        return (built, true)
    }
}
