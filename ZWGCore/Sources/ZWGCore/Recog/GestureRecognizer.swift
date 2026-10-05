import CoreGraphics
import Foundation

/// Tunables for gesture recognition.
public struct RecognitionSettings: Sendable, Equatable {
    /// Number of equidistant points both strokes are resampled to before comparison.
    ///
    /// Only used by the arc-length metric, i.e. by retracing gestures.
    public var sampleCount: Int
    /// Strokes shorter than this (in screen points) are never recognised — otherwise a
    /// twitchy click would be matched against whatever it vaguely resembles.
    public var minimumStrokeLength: CGFloat
    /// Largest mean normalised arc-length distance still accepted as a match, as a fraction of the
    /// stroke length. Applies to retracing gestures only; calibrated in `GestureRecognizerTests`.
    public var matchThreshold: CGFloat
    /// Largest structure distance still accepted as a match. Applies to everything that is not a
    /// retrace. Calibrated in `GestureRecognizerTests` against hand-drawn distortions.
    public var structureThreshold: CGFloat
    /// Tunables of the structure descriptor itself.
    public var structure: StrokeStructureSettings

    public init(
        sampleCount: Int = 32,
        minimumStrokeLength: CGFloat = 30,
        matchThreshold: CGFloat = 0.10,
        structureThreshold: CGFloat = 0.15,
        structure: StrokeStructureSettings = StrokeStructureSettings()
    ) {
        self.sampleCount = sampleCount
        self.minimumStrokeLength = minimumStrokeLength
        self.matchThreshold = matchThreshold
        self.structureThreshold = structureThreshold
        self.structure = structure
    }

    public func threshold(for metric: StrokeMetric) -> CGFloat {
        switch metric {
        case .structure: structureThreshold
        case .arcLength: matchThreshold
        }
    }
}

public struct RecognitionMatch: Sendable, Equatable {
    public var intent: WGIntent
    public var intentIndex: Int
    /// Distance to the stored trajectory under `metric`; 0 is exact.
    public var distance: CGFloat
    /// How many gesture-modifier steps the intent required.
    public var modifierCount: Int
    /// Which metric produced `distance`. The two are not comparable with each other, so anything
    /// that displays the number (the debug HUD, the settings window) has to show this too.
    public var metric: StrokeMetric

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

        let points = stroke.points
        let liveArc = StrokeNormalizer.normalize(points, sampleCount: index.settings.sampleCount)
        guard liveArc.count == index.settings.sampleCount else { return [] }

        // 结构签名只与画出来的形状有关，对所有候选都一样，所以整条笔画只算一次。没有任何
        // 结构类候选（罕见：整份配置都是闭环手势）时连算都不算。
        let liveStructure = index.usesStructure
            ? StrokeStructure.make(from: points, settings: index.settings.structure)
            : nil

        var candidates: [RecognitionMatch] = []
        candidates.reserveCapacity(index.gestures.count)
        for prepared in index.gestures {
            guard prepared.triggerButton == button else { continue }
            if let signature = prepared.triggerSignature, !triggerMatrix.allows(signature) { continue }
            guard areModifiersSatisfied(prepared.modifierRequirements, recorded: modifiers) else { continue }

            candidates.append(RecognitionMatch(
                intent: prepared.intent,
                intentIndex: prepared.intentIndex,
                distance: prepared.distance(
                    liveArc: liveArc,
                    liveStructure: liveStructure,
                    settings: index.settings
                ),
                modifierCount: prepared.modifierCount,
                metric: prepared.metric
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
        return bestCandidate(in: scored.filter { $0.distance <= index.settings.threshold(for: $0.metric) })
    }

    /// The best match **and** the nearest candidate, in a single pass.
    ///
    /// The tap thread needs both: a miss has to be reported together with the closest configured
    /// gesture, so "nothing matched" comes with a number instead of being a mystery. Scoring every
    /// gesture twice made the *miss* path — the slowest one there is — twice as slow as it needed
    /// to be.
    ///
    /// Note that the two metrics measure different things, so a "nearest" candidate is only
    /// meaningful together with its `metric` — which the match carries.
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
        let passing = scored.filter { $0.distance <= index.settings.threshold(for: $0.metric) }
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
    /// Putting the list order ahead of the shape distance was originally justified by "two
    /// different shapes cannot both pass the threshold". **That claim was measured and is false**
    /// (2026-10-06): in the reference configuration the closest distinct pair was 0.100 apart under
    /// the old arc-length metric, so `Enter` (earlier in the list) took L-shaped drawings away from
    /// `Close`. What makes the order-first rule safe now is the metric, not the threshold: with the
    /// structure metric the closest two genuinely different shapes are 0.283 apart (Enter vs
    /// Fullscreen), so the only candidates that ever both pass are genuine duplicates — which is
    /// exactly when list order *should* decide. `GestureRecognizerTests` and
    /// `ShapeOverProportionsTests` pin both halves of that down.
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
