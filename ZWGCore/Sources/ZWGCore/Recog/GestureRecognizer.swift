import CoreGraphics
import Foundation

/// Tunables for gesture recognition.
public struct RecognitionSettings: Sendable, Equatable {
    /// Number of equidistant points both strokes are resampled to before comparison.
    public var sampleCount: Int
    /// Strokes shorter than this (in screen points) are never recognised — otherwise a
    /// twitchy click would be matched against whatever it vaguely resembles.
    public var minimumStrokeLength: CGFloat
    /// Largest mean normalised distance still accepted as a match, as a fraction of the
    /// stroke length. Calibrated in `GestureRecognizerTests`.
    public var matchThreshold: CGFloat

    public init(
        sampleCount: Int = 32,
        minimumStrokeLength: CGFloat = 30,
        matchThreshold: CGFloat = 0.10
    ) {
        self.sampleCount = sampleCount
        self.minimumStrokeLength = minimumStrokeLength
        self.matchThreshold = matchThreshold
    }
}

public struct RecognitionMatch: Sendable, Equatable {
    public var intent: WGIntent
    public var intentIndex: Int
    /// Mean normalised distance to the stored trajectory; 0 is exact.
    public var distance: CGFloat
    /// How many gesture-modifier steps the intent required.
    public var modifierCount: Int

    public var name: String { intent.name }
}

/// Matches a drawn stroke against the gestures configured for a target.
public struct GestureRecognizer: Sendable {
    public var settings: RecognitionSettings

    public init(settings: RecognitionSettings = RecognitionSettings()) {
        self.settings = settings
    }

    /// - Parameters:
    ///   - stroke: the trajectory that was just drawn.
    ///   - button: the button that triggered it.
    ///   - modifiers: extra button presses and scrolls performed while drawing.
    ///   - target: the target whose gesture list applies.
    /// - Returns: the best match, or `nil` when nothing is close enough.
    public func recognize(
        stroke: Stroke,
        button: MouseButton,
        modifiers: [PointerEvent.Kind],
        in target: WGTarget,
        triggerMatrix: WGTriggerMatrix = .empty
    ) -> RecognitionMatch? {
        guard stroke.pathLength >= settings.minimumStrokeLength else { return nil }
        let passing = scoredCandidates(
            stroke: stroke,
            button: button,
            modifiers: modifiers,
            in: target,
            triggerMatrix: triggerMatrix
        )
        .filter { $0.distance <= settings.matchThreshold }
        return bestCandidate(in: passing)
    }

    /// Every eligible intent and how far its trajectory is from the drawn stroke, nearest
    /// first. Includes candidates that are too far to match, which is what makes a failed
    /// recognition diagnosable instead of a mystery.
    public func scoredCandidates(
        stroke: Stroke,
        button: MouseButton,
        modifiers: [PointerEvent.Kind],
        in target: WGTarget,
        triggerMatrix: WGTriggerMatrix = .empty
    ) -> [RecognitionMatch] {
        guard stroke.pathLength >= settings.minimumStrokeLength else { return [] }

        var candidates: [RecognitionMatch] = []
        for (index, intent) in target.intents.enumerated() {
            // 被禁用的手势保留在列表里，但不参与任何匹配 —— 这就是「禁用」的全部语义。
            guard intent.enabled else { continue }
            guard let definition = intent.strokeStep else { continue }
            guard isTriggerSatisfied(intent.triggerSteps, button: button, matrix: triggerMatrix) else { continue }
            guard areModifiersSatisfied(intent.modifierSteps, recorded: modifiers) else { continue }

            let distance = StrokeMatcher.distance(
                stroke: stroke,
                definition: definition,
                sampleCount: settings.sampleCount
            )
            candidates.append(RecognitionMatch(
                intent: intent,
                intentIndex: index,
                distance: distance,
                modifierCount: intent.modifierSteps.count
            ))
        }
        return candidates.sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.intentIndex < rhs.intentIndex
        }
    }

    /// The closest eligible intent regardless of the threshold — used only for diagnostics.
    public func nearestCandidate(
        stroke: Stroke,
        button: MouseButton,
        modifiers: [PointerEvent.Kind],
        in target: WGTarget,
        triggerMatrix: WGTriggerMatrix = .empty
    ) -> RecognitionMatch? {
        scoredCandidates(
            stroke: stroke,
            button: button,
            modifiers: modifiers,
            in: target,
            triggerMatrix: triggerMatrix
        ).first
    }

    /// Picks between intents that share a trajectory.
    ///
    /// Order of preference:
    /// 1. **More 手势修饰键 wins.** `拷贝` and `剪切` are both an up-stroke and only the extra
    ///    left-button press distinguishes them, so the more specific definition must take over when
    ///    that button is also pressed.
    /// 2. **Earlier in the list wins.** The list order is the user's priority control: two gestures
    ///    with the same trajectory are otherwise indistinguishable, and the settings window lets
    ///    them reorder entries to decide which one fires.
    /// 3. Closer shape, purely as a last resort.
    ///
    /// This deliberately differs from WGestures' documented "later match wins": an explicit,
    /// visible priority is far easier to reason about than "the last one in the file wins", and it
    /// is what makes the settings list's ordering meaningful.
    ///
    /// Putting the list order ahead of the shape distance is safe because two *different* shapes
    /// cannot both pass `matchThreshold`: in the user's real configuration the closest
    /// non-duplicate pair is ~0.28 apart, nearly three times the 0.10 threshold. Order therefore
    /// only ever decides between entries that are genuine duplicates.
    func bestCandidate(in candidates: [RecognitionMatch]) -> RecognitionMatch? {
        candidates.max { lhs, rhs in
            if lhs.modifierCount != rhs.modifierCount { return lhs.modifierCount < rhs.modifierCount }
            if lhs.intentIndex != rhs.intentIndex { return lhs.intentIndex > rhs.intentIndex }
            return lhs.distance > rhs.distance
        }
    }

    // MARK: - Eligibility

    /// Whether the steps leading up to the stroke describe the trigger we just saw, and whether
    /// the trigger matrix allows that trigger for this target.
    private func isTriggerSatisfied(
        _ steps: [WGStep],
        button: MouseButton,
        matrix: WGTriggerMatrix
    ) -> Bool {
        guard !steps.isEmpty else { return false }
        var sawButton = false

        for step in steps {
            switch step {
            case .keyDown(let key):
                guard case .mouse(let candidate) = WGInputToken(key: key.key), candidate == button else {
                    // Keyboard-as-trigger and scroll-as-trigger are handled by the edge and
                    // scroll detector in a later phase.
                    return false
                }
                sawButton = true
            case .moveToEdgeCorner:
                // Screen-edge gestures need the edge detector; not eligible until then.
                return false
            default:
                return false
            }
        }
        guard sawButton else { return false }

        // A gesture whose trigger the user switched off in the 触发方式 matrix must not fire.
        if let signature = WGTriggerSignature.make(from: steps) {
            return matrix.allows(signature)
        }
        return true
    }

    /// Whether every gesture-modifier step actually happened while the stroke was drawn.
    private func areModifiersSatisfied(_ steps: [WGStep], recorded: [PointerEvent.Kind]) -> Bool {
        for step in steps {
            guard case .keyDown(let key) = step else { return false }
            let token = WGInputToken(key: key.key)

            switch token {
            case .mouse(let button):
                guard recorded.contains(.down(button)) else { return false }
            case .verticalScroll, .horizontalScroll:
                guard let direction = token.scrollDirection else { return false }
                guard recorded.contains(where: { kind in
                    guard case .scroll(_, let deltaY) = kind else { return false }
                    let recordedDirection = deltaY == 0 ? 0 : (deltaY > 0 ? 1 : -1)
                    return recordedDirection == direction
                }) else { return false }
            case .key:
                return false
            }
        }
        return true
    }
}
