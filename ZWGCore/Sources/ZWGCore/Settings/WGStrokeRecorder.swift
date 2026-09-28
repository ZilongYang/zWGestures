import CoreGraphics
import Foundation

/// Turns a freshly drawn trajectory into the `StrokeStep` stored in the configuration.
///
/// The input is **screen coordinates, y increasing downwards, in drawing order** — exactly what a
/// capture view produces (`StrokeCanvasView` is flipped so its coordinates match). The output
/// negates y, because the configuration's convention is y growing upwards for simple and arbitrary
/// strokes alike; that rule is documented at length in `docs/ROADMAP.md` §6 and has been gotten
/// wrong twice, so this file is written to be checked by its own round trip rather than by
/// inspection.
///
/// Two encodings are produced:
/// - an **axis-aligned 「simple」 stroke** on WGestures' 50-unit grid when the drawing is close
///   enough to a straight or right-angled path (32 of the 36 gestures in the user's real
///   configuration are stored this way), and
/// - the **freehand point list** otherwise.
///
/// Which one is used is decided by measurement, not by a heuristic guess: the candidate simple form
/// is compared against the drawing with the *same* normalised matcher the recogniser uses, and is
/// only kept when the two are within `simpleFormTolerance`. A stroke that would be stored but no
/// longer recognised is therefore impossible.
public enum WGStrokeRecorder {
    /// The shortest drawing accepted, in screen points.
    ///
    /// Matches `RecognitionSettings.minimumStrokeLength`: a stored definition shorter than this
    /// could never be matched, because a live stroke that short is rejected before comparison.
    public static let defaultMinimumLength: CGFloat = 30

    /// Grid spacing of a simple stroke, in the configuration's units.
    public static let gridUnit: CGFloat = 50

    /// Largest normalised distance between the drawing and its snapped simple form that is still
    /// accepted. Well under `RecognitionSettings.matchThreshold` (0.10) so the stored gesture keeps
    /// a comfortable margin against the live strokes it must recognise.
    public static let simpleFormTolerance: CGFloat = 0.06

    /// Most points stored for a freehand stroke. The original app stores 3–8; more than this only
    /// bloats the file because the matcher resamples to 32 points anyway.
    public static let maximumFreehandPoints = 12

    public enum Failure: Error, LocalizedError, Equatable {
        case tooShort(length: CGFloat, minimum: CGFloat)
        case empty

        public var errorDescription: String? {
            switch self {
            case .empty:
                "没有画出手势。在画布上按住并拖动画一个形状。"
            case .tooShort(let length, let minimum):
                String(
                    format: "画得太短了（%.0f 点，至少需要 %.0f 点）。画得长一点再试。",
                    length, minimum
                )
            }
        }
    }

    /// Encodes a drawing.
    ///
    /// - Parameters:
    ///   - screenPoints: trajectory in screen orientation (y downwards), in drawing order.
    ///   - minimumLength: strokes shorter than this are rejected.
    /// - Returns: the stroke to store, with y negated for the configuration.
    public static func encode(
        screenPoints: [CGPoint],
        minimumLength: CGFloat = defaultMinimumLength
    ) throws -> WGStrokeStep {
        let points = screenPoints.filter { $0.x.isFinite && $0.y.isFinite }
        guard points.count >= 2 else { throw Failure.empty }

        let length = StrokeNormalizer.pathLength(points)
        guard length >= minimumLength else {
            throw Failure.tooShort(length: length, minimum: minimumLength)
        }

        if let simple = simpleForm(for: points) {
            return simple
        }
        return freehandForm(for: points)
    }

    /// The direction text the drawing currently encodes, for live feedback while drawing.
    ///
    /// Deliberately the same code path as `encode` (minus the length gate), so the preview cannot
    /// disagree with what would be stored.
    public static func directionPreview(screenPoints: [CGPoint]) -> String {
        guard screenPoints.count >= 2 else { return "（还没画）" }
        if let simple = simpleForm(for: screenPoints) {
            return simple.directionDescription
        }
        return freehandForm(for: screenPoints).directionDescription
    }

    // MARK: - Simple form

    /// A right-angled, grid-aligned version of the drawing, or `nil` when the drawing is not close
    /// enough to one.
    static func simpleForm(for points: [CGPoint]) -> WGStrokeStep? {
        let length = StrokeNormalizer.pathLength(points)
        guard length > 0 else { return nil }

        // Coarse simplification first: a hand-drawn straight line has hundreds of points that are
        // all within a pixel or two of the chord.
        let coarse = simplify(points, tolerance: max(4, length * 0.05))
        guard (2...4).contains(coarse.count) else { return nil }

        var encoded: [Int] = [0, 0]
        var cursor = CGPoint.zero
        for (from, to) in zip(coarse, coarse.dropFirst()) {
            let dx = to.x - from.x
            let dy = to.y - from.y
            guard abs(dx) > 1 || abs(dy) > 1 else { continue }

            // Snap to the dominant axis; only a genuinely diagonal move keeps both components.
            let step: CGPoint
            if abs(dx) >= abs(dy) * 1.6 {
                step = CGPoint(x: dx > 0 ? gridUnit : -gridUnit, y: 0)
            } else if abs(dy) >= abs(dx) * 1.6 {
                step = CGPoint(x: 0, y: dy > 0 ? gridUnit : -gridUnit)
            } else {
                step = CGPoint(
                    x: dx > 0 ? gridUnit : -gridUnit,
                    y: dy > 0 ? gridUnit : -gridUnit
                )
            }
            cursor.x += step.x
            cursor.y += step.y
            // Configuration y grows upwards, the drawing's y grows downwards.
            encoded.append(contentsOf: [Int(cursor.x), Int(-cursor.y)])
        }

        guard encoded.count >= 4 else { return nil }
        let candidate = WGStrokeStep(isSimple: true, points: encoded)

        // Accept only if the snapped shape still matches the drawing under the recogniser's own
        // metric — this is what makes "stored but unrecognisable" impossible.
        let drawn = StrokeNormalizer.normalize(points, sampleCount: 32)
        let snapped = StrokeNormalizer.normalize(candidate.drawingOrderPoints, sampleCount: 32)
        guard StrokeMatcher.distance(drawn, snapped) <= simpleFormTolerance else { return nil }

        return candidate
    }

    // MARK: - Freehand form

    /// The drawing's own points, decimated, with the start moved to the origin and y negated.
    ///
    /// Relative coordinates are deliberate: after normalisation the recogniser only looks at the
    /// shape, and a stroke that starts at (0, 0) is readable in the file — unlike the original's
    /// absolute screen positions such as `969, 546`, which mean nothing outside the screen they were
    /// recorded on.
    static func freehandForm(for points: [CGPoint]) -> WGStrokeStep {
        var simplified = simplify(points, tolerance: 2.5)
        if simplified.count > maximumFreehandPoints {
            simplified = StrokeNormalizer.resample(simplified, count: maximumFreehandPoints)
        }
        let origin = simplified.first ?? .zero
        var encoded: [Int] = []
        for point in simplified {
            encoded.append(Int((point.x - origin.x).rounded()))
            encoded.append(Int((-(point.y - origin.y)).rounded()))
        }
        return WGStrokeStep(isSimple: false, points: encoded)
    }

    // MARK: - Geometry

    /// Ramer–Douglas–Peucker simplification.
    static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var farthest: CGFloat = 0
        var index = 0
        let first = points[0]
        let last = points[points.count - 1]

        for position in 1..<(points.count - 1) {
            let distance = perpendicularDistance(points[position], from: first, to: last)
            if distance > farthest {
                farthest = distance
                index = position
            }
        }

        guard farthest > tolerance else { return [first, last] }
        let head = simplify(Array(points[0...index]), tolerance: tolerance)
        let tail = simplify(Array(points[index...]), tolerance: tolerance)
        return head.dropLast() + tail
    }

    static func perpendicularDistance(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let denominator = (dx * dx + dy * dy).squareRoot()
        guard denominator > 0 else {
            return ((point.x - start.x) * (point.x - start.x) + (point.y - start.y) * (point.y - start.y)).squareRoot()
        }
        return abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x) / denominator
    }
}
