import CoreGraphics
import Foundation

/// Finds gestures that can never fire because another gesture in the same gesture set wins every
/// time for the same input.
///
/// **Identical shapes are legitimate in WGestures**, so this is not a "duplicate shape" check.
/// `拷贝` and `剪切` are both an up-stroke in the user's real configuration and only the extra
/// left-button press tells them apart: without the modifier only the plain one is eligible, with it
/// the more specific one wins (`GestureRecognizer.bestCandidate` prefers more modifier steps). The
/// two are perfectly reachable.
///
/// A real conflict therefore needs all three of:
/// 1. the same **trigger** (the button that starts the gesture),
/// 2. the same **gesture-modifier requirement**, and
/// 3. trajectories closer than the recogniser's match threshold.
///
/// Then the matcher picks exactly one of them for any drawing, and the other is dead — stored,
/// listed, and never fired. That is what happened when a re-recorded 「Copy」 was given the plain
/// right stroke that 「Forward」 already owned.
public enum WGStrokeConflict {
    /// A gesture that will beat `stroke` for the same input.
    public struct Twin: Equatable, Sendable {
        /// Index of the twin in the array it was found in.
        public var index: Int
        public var name: String
        /// Normalised distance: 0 means the two trajectories are identical.
        public var distance: CGFloat
    }

    /// The nearest gesture that collides with `gesture`, or `nil` when its shape is free.
    ///
    /// The candidate is a whole intent rather than a bare stroke on purpose: what a gesture competes
    /// with depends on its trigger and its 手势修饰键 as much as on its shape, and taking only a
    /// stroke made it far too easy to forget those (and then compare against everything).
    ///
    /// - Parameters:
    ///   - gesture: the gesture that is about to be stored; it must carry its stroke.
    ///   - intents: every gesture in the same gesture set, including the candidate itself.
    ///   - index: the candidate's position in `intents`, so it is not compared with itself.
    public static func nearestTwin(
        toCandidate gesture: WGIntent,
        in intents: [WGIntent],
        excluding index: Int? = nil,
        threshold: CGFloat = RecognitionSettings().matchThreshold
    ) -> Twin? {
        guard let stroke = gesture.strokeStep else { return nil }
        let candidate = StrokeNormalizer.normalize(
            stroke.drawingOrderPoints,
            sampleCount: RecognitionSettings().sampleCount
        )
        guard !candidate.isEmpty else { return nil }

        let expectedTrigger = triggerSignature(gesture.triggerSteps)
        let expectedModifiers = modifierSignature(gesture.modifierSteps)

        var best: Twin?
        for (position, intent) in intents.enumerated() {
            // A disabled gesture never fires, so it cannot take a shape away from anyone.
            guard intent.enabled, position != index, let other = intent.strokeStep else { continue }
            // Different trigger or different modifier requirement → both can still fire.
            guard triggerSignature(intent.triggerSteps) == expectedTrigger,
                  modifierSignature(intent.modifierSteps) == expectedModifiers
            else { continue }

            let points = StrokeNormalizer.normalize(
                other.drawingOrderPoints,
                sampleCount: RecognitionSettings().sampleCount
            )
            let distance = StrokeMatcher.distance(candidate, points)
            guard distance <= threshold else { continue }
            if best == nil || distance < best!.distance {
                best = Twin(index: position, name: intent.name, distance: distance)
            }
        }
        return best
    }

    /// Every gesture in `intents` that another one beats for the same input, mapped to the name of
    /// that twin.
    ///
    /// Used to mark rows in the settings list, so an already-broken configuration is visible instead
    /// of merely feeling broken.
    public static func collisions(
        in intents: [WGIntent],
        threshold: CGFloat = RecognitionSettings().matchThreshold
    ) -> [Int: String] {
        let entries: [(index: Int, name: String, trigger: [String], modifiers: [String], points: [CGPoint])] =
            intents.enumerated().compactMap { position, intent in
                guard intent.enabled, let stroke = intent.strokeStep else { return nil }
                let points = StrokeNormalizer.normalize(
                    stroke.drawingOrderPoints,
                    sampleCount: RecognitionSettings().sampleCount
                )
                guard !points.isEmpty else { return nil }
                return (
                    position,
                    intent.name,
                    triggerSignature(intent.triggerSteps),
                    modifierSignature(intent.modifierSteps),
                    points
                )
            }

        var result: [Int: String] = [:]
        var closest: [Int: CGFloat] = [:]

        for outer in entries.indices {
            for inner in entries.indices where inner > outer {
                let lhs = entries[outer]
                let rhs = entries[inner]
                guard lhs.trigger == rhs.trigger, lhs.modifiers == rhs.modifiers else { continue }
                let distance = StrokeMatcher.distance(lhs.points, rhs.points)
                guard distance <= threshold else { continue }
                for (subject, twin) in [(lhs, rhs), (rhs, lhs)] {
                    if let previous = closest[subject.index], previous <= distance { continue }
                    closest[subject.index] = distance
                    result[subject.index] = twin.name
                }
            }
        }
        return result
    }

    // MARK: - Signatures

    /// The buttons a gesture can be started with.
    ///
    /// Only mouse buttons are considered: keyboard and screen-edge triggers are not implemented, and
    /// `GestureRecognizer.isTriggerSatisfied` rejects anything else outright.
    static func triggerSignature(_ steps: [WGStep]) -> [String] {
        steps.compactMap { step in
            guard case .keyDown(let key) = step,
                  case .mouse(let button) = WGInputToken(key: key.key)
            else { return nil }
            return button.legacyToken
        }
    }

    /// What the gesture requires to have happened during the stroke, in the same terms the
    /// recogniser uses.
    ///
    /// Scroll steps collapse to a direction, exactly like `areModifiersSatisfied` does, so
    /// `VSCROLL:11` and `VSCROLL:12` are recognised as competing for the same input. Sorting makes
    /// the comparison order-insensitive.
    static func modifierSignature(_ steps: [WGStep]) -> [String] {
        steps.map { step -> String in
            guard case .keyDown(let key) = step else { return "STEP:\(step.typeName)" }
            switch WGInputToken(key: key.key) {
            case .mouse(let button):
                return button.legacyToken
            case .verticalScroll(let value), .horizontalScroll(let value):
                return "SCROLL:\(value == 0 ? 0 : (value > 0 ? 1 : -1))"
            case .key(let name):
                // Keyboard modifiers make an intent ineligible entirely; keep them distinct.
                return "KEY:\(name)"
            }
        }
        .sorted()
    }
}
