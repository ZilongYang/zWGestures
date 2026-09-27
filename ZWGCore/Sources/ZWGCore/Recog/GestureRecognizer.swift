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
        in target: WGTarget
    ) -> RecognitionMatch? {
        guard stroke.pathLength >= settings.minimumStrokeLength else { return nil }

        var candidates: [RecognitionMatch] = []
        for (index, intent) in target.intents.enumerated() {
            guard let definition = intent.strokeStep else { continue }
            guard isTriggerSatisfied(intent.triggerSteps, button: button) else { continue }
            guard areModifiersSatisfied(intent.modifierSteps, recorded: modifiers) else { continue }

            let distance = StrokeMatcher.distance(
                stroke: stroke,
                definition: definition,
                sampleCount: settings.sampleCount
            )
            guard distance <= settings.matchThreshold else { continue }

            candidates.append(RecognitionMatch(
                intent: intent,
                intentIndex: index,
                distance: distance,
                modifierCount: intent.modifierSteps.count
            ))
        }

        return bestCandidate(in: candidates)
    }

    /// Picks between intents that share a trajectory.
    ///
    /// The ordering matters for real configurations: `拷贝` and `剪切` are both an up-stroke,
    /// and only the extra left-button press distinguishes them. The more specific definition
    /// therefore wins; ties go to the closer shape and then to the later entry in the list,
    /// matching WGestures' documented "later match wins" behaviour.
    func bestCandidate(in candidates: [RecognitionMatch]) -> RecognitionMatch? {
        candidates.max { lhs, rhs in
            if lhs.modifierCount != rhs.modifierCount { return lhs.modifierCount < rhs.modifierCount }
            if lhs.distance != rhs.distance { return lhs.distance > rhs.distance }
            return lhs.intentIndex < rhs.intentIndex
        }
    }

    // MARK: - Eligibility

    /// Whether the steps leading up to the stroke describe the trigger we just saw.
    private func isTriggerSatisfied(_ steps: [WGStep], button: MouseButton) -> Bool {
        guard !steps.isEmpty else { return false }
        var sawButton = false

        for step in steps {
            switch step {
            case .keyDown(let key):
                guard case .mouse(let candidate) = WGInputToken(key: key.key), candidate == button else {
                    // Keyboard-as-trigger and scroll-as-trigger are handled in later phases.
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
        return sawButton
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
