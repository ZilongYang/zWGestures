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

    // MARK: - Matching against a prepared index（拦截器线程走这条）

    /// Scores every gesture in `index`, nearest first.
    ///
    /// This is the form the event-tap thread uses. The live stroke is normalised **once** — its shape
    /// is identical for every candidate, and re-normalising it per candidate was ~45× wasted work —
    /// and every stored shape was normalised when the index was built, so the loop allocates nothing.
    public func scoredCandidates(
        stroke: Stroke,
        button: MouseButton,
        modifiers: [PointerEvent.Kind],
        in index: GestureIndex,
        triggerMatrix: WGTriggerMatrix = .empty
    ) -> [RecognitionMatch] {
        guard stroke.pathLength >= index.settings.minimumStrokeLength else { return [] }

        let live = StrokeNormalizer.normalize(stroke.points, sampleCount: index.settings.sampleCount)
        guard live.count == index.settings.sampleCount else { return [] }

        var candidates: [RecognitionMatch] = []
        candidates.reserveCapacity(index.gestures.count)
        for prepared in index.gestures {
            guard prepared.triggerButton == button else { continue }
            if let signature = prepared.triggerSignature, !triggerMatrix.allows(signature) { continue }
            guard areModifiersSatisfied(prepared.modifierRequirements, recorded: modifiers) else { continue }

            candidates.append(RecognitionMatch(
                intent: prepared.intent,
                intentIndex: prepared.intentIndex,
                distance: StrokeMatcher.distance(live, prepared.shape),
                modifierCount: prepared.modifierCount
            ))
        }
        return candidates.sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.intentIndex < rhs.intentIndex
        }
    }

    /// The best match, or `nil` when nothing is close enough.
    public func recognize(
        stroke: Stroke,
        button: MouseButton,
        modifiers: [PointerEvent.Kind],
        in index: GestureIndex,
        triggerMatrix: WGTriggerMatrix = .empty
    ) -> RecognitionMatch? {
        let scored = scoredCandidates(
            stroke: stroke,
            button: button,
            modifiers: modifiers,
            in: index,
            triggerMatrix: triggerMatrix
        )
        return bestCandidate(in: scored.filter { $0.distance <= index.settings.matchThreshold })
    }

    /// The best match **and** the nearest candidate, in a single pass.
    ///
    /// The tap thread needs both: a miss has to be reported together with the closest configured
    /// gesture, so "nothing matched" comes with a number instead of being a mystery. Scoring every
    /// gesture twice made the *miss* path — the slowest one there is — twice as slow as it needed
    /// to be.
    public func recognizeWithNearest(
        stroke: Stroke,
        button: MouseButton,
        modifiers: [PointerEvent.Kind],
        in index: GestureIndex,
        triggerMatrix: WGTriggerMatrix = .empty
    ) -> (match: RecognitionMatch?, nearest: RecognitionMatch?) {
        let scored = scoredCandidates(
            stroke: stroke,
            button: button,
            modifiers: modifiers,
            in: index,
            triggerMatrix: triggerMatrix
        )
        let passing = scored.filter { $0.distance <= index.settings.matchThreshold }
        return (bestCandidate(in: passing), scored.first)
    }

    // MARK: - Convenience: match straight against a target

    /// Builds an index on the spot and matches against it.
    ///
    /// Convenient for tests and diagnostics, but it rebuilds the index on **every call**. The
    /// event-tap thread must use the `GestureIndex` form instead — see `GestureIndex`.
    public func scoredCandidates(
        stroke: Stroke,
        button: MouseButton,
        modifiers: [PointerEvent.Kind],
        in target: WGTarget,
        triggerMatrix: WGTriggerMatrix = .empty
    ) -> [RecognitionMatch] {
        scoredCandidates(
            stroke: stroke,
            button: button,
            modifiers: modifiers,
            in: GestureIndex(target: target, settings: settings),
            triggerMatrix: triggerMatrix
        )
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
        recognize(
            stroke: stroke,
            button: button,
            modifiers: modifiers,
            in: GestureIndex(target: target, settings: settings),
            triggerMatrix: triggerMatrix
        )
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

    /// Whether every 手势修饰键 this gesture declares actually happened while the stroke was drawn.
    ///
    /// The requirements are already parsed and classified, so this loop does no string work.
    private func areModifiersSatisfied(
        _ requirements: [ModifierRequirement],
        recorded: [PointerEvent.Kind]
    ) -> Bool {
        for requirement in requirements {
            switch requirement {
            case .impossible:
                // A modifier this build cannot satisfy (a keyboard key).
                return false
            case .button(let button):
                guard recorded.contains(.down(button)) else { return false }
            case .scroll(let direction):
                guard recorded.contains(where: { kind in
                    guard case .scroll(_, let deltaY) = kind else { return false }
                    let recordedDirection = deltaY == 0 ? 0 : (deltaY > 0 ? 1 : -1)
                    return recordedDirection == direction
                }) else { return false }
            }
        }
        return true
    }
}
