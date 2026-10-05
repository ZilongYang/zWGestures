import CoreGraphics
import Foundation

/// How a stroke is compared with a stored gesture.
///
/// There are two metrics on purpose, and which one applies is decided by the **stored** gesture:
///
/// - `.structure` — the corner structure of the stroke (which way each segment goes and how long
///   it is relative to the whole). This is the default, and it is what makes an L-shaped gesture
///   recognisable no matter how long its two arms are drawn.
/// - `.arcLength` — the original metric: both strokes are resampled to a fixed number of
///   equidistant points along their arc length and scaled to a total length of 1, then compared
///   point by point.
///
/// The arc-length metric is kept for **retracing** strokes only (a stored trajectory that comes
/// back to where it started, e.g. `Web 搜索` = up then back down). Those gestures are taught and
/// drawn as elongated loops, and "an elongated oval still counts, a circle does not" was tuned
/// against this metric with real measurements (`GestureRecognizerTests`). Turning them into a
/// corner structure would make the loop break into 4+ segments and silently narrow that tolerance,
/// which is a worse outcome than keeping a second metric. See docs/ROADMAP.md §21.
public enum StrokeMetric: Sendable, Equatable {
    case structure
    case arcLength
}

/// Tunables for the structure descriptor.
public struct StrokeStructureSettings: Sendable, Equatable {
    /// Most points analysed when reducing a stroke to its structure.
    ///
    /// The descriptor only needs the corner geometry, and the live stroke can carry several hundred
    /// samples. Reducing to this many points first makes the cost **independent of stroke length**
    /// (a measured 1062 µs per stroke on the event-tap thread dropped to a fraction of that), and
    /// 48 samples still localise a corner far more precisely than the simplification tolerance
    /// cares about.
    public var maximumAnalysisPoints: Int
    /// Moving-average window applied before simplifying. Hand tremor is high frequency; a
    /// straight hand-drawn line must not turn into a zigzag the simplifier then believes in.
    public var smoothWindow: Int
    /// Simplification tolerance as a fraction of the stroke's bounding-box diagonal.
    public var toleranceFraction: CGFloat
    /// Lower bound for the simplification tolerance, in screen points. A small gesture must not be
    /// analysed at pixel-level detail.
    public var minimumTolerance: CGFloat
    /// Angle below which two neighbouring segments are considered one straight run (radians).
    public var mergeAngle: CGFloat
    /// Segments shorter than this fraction of the stroke are dropped before comparison.
    public var minimumSegmentFraction: CGFloat
    /// How much of the match cost comes from direction (the rest comes from segment length).
    ///
    /// Direction dominates deliberately: the user complaint this metric exists for is
    /// "the shape is obviously a down-then-right, but the horizontal is not long enough yet".
    /// Measured on the reference configuration: with 0.85 the closest two *genuinely different*
    /// shapes are 0.25 apart (Enter vs Fullscreen, which differ in the direction of their end
    /// segments), while an L whose arms are drawn 8:1 apart still sits 0.06 from its definition —
    /// it used to be 0.15 with a stronger length term, i.e. right at the threshold.
    public var directionWeight: CGFloat
    /// Cost of a segment that has no counterpart at all. High enough that a stroke with the wrong
    /// number of corners cannot pass by accident.
    public var gapCost: CGFloat

    public init(
        maximumAnalysisPoints: Int = 48,
        smoothWindow: Int = 5,
        toleranceFraction: CGFloat = 0.09,
        minimumTolerance: CGFloat = 8,
        mergeAngle: CGFloat = 25 * .pi / 180,
        minimumSegmentFraction: CGFloat = 0.04,
        directionWeight: CGFloat = 0.85,
        gapCost: CGFloat = 1.0
    ) {
        self.maximumAnalysisPoints = maximumAnalysisPoints
        self.smoothWindow = smoothWindow
        self.toleranceFraction = toleranceFraction
        self.minimumTolerance = minimumTolerance
        self.mergeAngle = mergeAngle
        self.minimumSegmentFraction = minimumSegmentFraction
        self.directionWeight = directionWeight
        self.gapCost = gapCost
    }
}

/// A polyline reduced to its corner structure.
///
/// This is the descriptor behind `.structure` matching: a list of segments, each with a unit
/// direction and a length expressed as a fraction of the whole stroke. Absolute size, position,
/// drawing speed and — the point of it all — *how long each arm happens to be* are all gone.
public struct StrokeStructure: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        /// Unit vector, in the same coordinate space as the input points.
        public var direction: CGVector
        /// Length of this segment as a fraction of the simplified stroke's total length.
        public var lengthFraction: CGFloat
    }

    public var segments: [Segment]
    /// Total length of the stroke this structure was made from, in screen points.
    public var pathLength: CGFloat

    /// - Returns: `nil` when the stroke has no length, or carries a non-finite point.
    public static func make(
        from points: [CGPoint],
        settings: StrokeStructureSettings = StrokeStructureSettings()
    ) -> StrokeStructure? {
        guard points.count >= 2 else { return nil }

        // One pass over the original: validate, measure, and pick the evenly spaced subset the
        // analysis runs on. Doing it in one loop (rather than `filter` + `boundingDiagonal` +
        // `pathLength`) is what keeps this affordable on the event-tap thread.
        var pathLength: CGFloat = 0
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        var previous = points[0]
        let budget = max(2, settings.maximumAnalysisPoints)
        let stride = max(1, (points.count - 1) / (budget - 1))
        var sampled: [CGPoint] = []
        sampled.reserveCapacity(budget + 1)

        for index in points.indices {
            let point = points[index]
            guard point.x.isFinite, point.y.isFinite else { return nil }
            if index > 0 {
                let dx = point.x - previous.x
                let dy = point.y - previous.y
                pathLength += (dx * dx + dy * dy).squareRoot()
            }
            if point.x < minX { minX = point.x }
            if point.x > maxX { maxX = point.x }
            if point.y < minY { minY = point.y }
            if point.y > maxY { maxY = point.y }
            if index % stride == 0 { sampled.append(point) }
            previous = point
        }
        guard pathLength > 0 else { return nil }
        if let last = points.last, sampled.last != last { sampled.append(last) }

        let diagonal = ((maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY)).squareRoot()
        let tolerance = max(settings.minimumTolerance, settings.toleranceFraction * diagonal)

        let smoothed = smooth(sampled, window: settings.smoothWindow)
        let simplified = simplify(smoothed, tolerance: tolerance)
        let merged = mergeStraightRuns(simplified, angle: settings.mergeAngle)
        let segments = rawSegments(merged)
        guard !segments.isEmpty else { return nil }

        // 丢掉可以忽略的小段（手抖残留），再把长度占比重新归一化。留下的小段只会让
        // 「段数」对不上，而那正是这个度量最看重的东西。
        var kept: [Segment] = []
        kept.reserveCapacity(segments.count)
        for segment in segments where segment.lengthFraction >= settings.minimumSegmentFraction {
            kept.append(segment)
        }
        if kept.isEmpty {
            var longest = segments[0]
            for segment in segments where segment.lengthFraction > longest.lengthFraction {
                longest = segment
            }
            kept = [longest]
        }

        var keptTotal: CGFloat = 0
        for segment in kept { keptTotal += segment.lengthFraction }
        guard keptTotal > 0 else { return nil }
        for index in kept.indices { kept[index].lengthFraction /= keptTotal }

        return StrokeStructure(segments: kept, pathLength: pathLength)
    }

    /// Alignment cost between two structures; 0 is an identical structure.
    ///
    /// A small dynamic-programming alignment over the two segment lists, because hand-drawn
    /// strokes do not always simplify to exactly the stored number of segments:
    ///
    /// - matching segment *i* with segment *j* costs `directionWeight × 方向差 + (1 − …) × 长度差`,
    ///   where 方向差 is the angle between them divided by 90° (so a right angle is a total miss
    ///   and a 30° wobble is nearly free);
    /// - leaving a segment unmatched costs `gapCost`, whatever its length — this is what stops a
    ///   2-segment L from being accepted as the 3-segment `Enter`, which is exactly the confusion
    ///   the user reported.
    ///
    /// The result is divided by the longer of the two segment counts.
    public static func distance(
        _ lhs: StrokeStructure,
        _ rhs: StrokeStructure,
        settings: StrokeStructureSettings = StrokeStructureSettings()
    ) -> CGFloat {
        let n = lhs.segments.count
        let m = rhs.segments.count
        guard n > 0, m > 0 else { return .infinity }

        // Both closed forms exist because one-segment gestures are the common case (17 of the 32
        // matchable gestures in the reference configuration). The gap terms of a one-row alignment
        // sum to (other − 1) × gapCost no matter which segment is matched, so only the best match
        // matters.
        if n == 1 {
            var best = CGFloat.greatestFiniteMagnitude
            for index in 0..<m {
                let cost = matchCost(lhs.segments[0], rhs.segments[index], settings: settings)
                if cost < best { best = cost }
            }
            return (CGFloat(m - 1) * settings.gapCost + best) / CGFloat(m)
        }
        if m == 1 {
            var best = CGFloat.greatestFiniteMagnitude
            for index in 0..<n {
                let cost = matchCost(lhs.segments[index], rhs.segments[0], settings: settings)
                if cost < best { best = cost }
            }
            return (CGFloat(n - 1) * settings.gapCost + best) / CGFloat(n)
        }

        // Equal segment counts take the diagonal, with no table at all: a monotonic alignment that
        // leaves a pair unmatched spends two `gapCost`s (≥ any match cost) where the diagonal
        // spends one match, so it can never win. This is the hot case (two L shapes, two 3-segment
        // shapes) and it is what keeps the event-tap path allocation free.
        if n == m, settings.gapCost >= 1 {
            var total: CGFloat = 0
            for index in 0..<n {
                total += matchCost(lhs.segments[index], rhs.segments[index], settings: settings)
            }
            return total / CGFloat(n)
        }
        guard n <= 64, m <= 64 else { return .infinity }

        let width = m + 1
        return withUnsafeTemporaryAllocation(of: CGFloat.self, capacity: (n + 1) * width) { cost in
            for index in cost.indices { cost[index] = 0 }
            for i in 1...n { cost[i * width] = cost[(i - 1) * width] + settings.gapCost }
            for j in 1...m { cost[j] = cost[j - 1] + settings.gapCost }

            for i in 1...n {
                for j in 1...m {
                    let match = cost[(i - 1) * width + (j - 1)]
                        + matchCost(lhs.segments[i - 1], rhs.segments[j - 1], settings: settings)
                    let dropLeft = cost[(i - 1) * width + j] + settings.gapCost
                    let dropRight = cost[i * width + (j - 1)] + settings.gapCost
                    cost[i * width + j] = min(match, min(dropLeft, dropRight))
                }
            }
            return cost[n * width + m] / CGFloat(max(n, m))
        }
    }

    private static func matchCost(
        _ lhs: Segment,
        _ rhs: Segment,
        settings: StrokeStructureSettings
    ) -> CGFloat {
        let dot = lhs.direction.dx * rhs.direction.dx + lhs.direction.dy * rhs.direction.dy
        let angle = acos(min(1, max(-1, dot)))
        let directionCost = min(1, angle / (.pi / 2))
        let lengthCost = abs(lhs.lengthFraction - rhs.lengthFraction)
        return settings.directionWeight * directionCost
            + (1 - settings.directionWeight) * lengthCost
    }

    // MARK: - Geometry

    /// Moving average of the interior points; the endpoints stay put (they are the meaningful
    /// "where the user put the pen down / picked it up").
    ///
    /// Only applied when the point list is dense enough for the average to mean something. A stored
    /// definition has 2–4 vertices, and averaging those *destroys the corner* — a 3-vertex L becomes
    /// a straight line, which would make every stored gesture look like a line (measured: 「关闭」
    /// scored 0.252 against its own definition before this guard was added).
    private static func smooth(_ points: [CGPoint], window: Int) -> [CGPoint] {
        guard window > 1, points.count >= Swift.max(8, window * 3) else { return points }
        let half = window / 2
        var result = points
        for index in 1..<(points.count - 1) {
            let low = Swift.max(0, index - half)
            let high = Swift.min(points.count - 1, index + half)
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            var position = low
            while position <= high {
                sumX += points[position].x
                sumY += points[position].y
                position += 1
            }
            let count = CGFloat(high - low + 1)
            result[index] = CGPoint(x: sumX / count, y: sumY / count)
        }
        return result
    }

    /// Ramer–Douglas–Peucker, iterative and index based (no array slices, so a few hundred sample
    /// points cost no extra copying).
    static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var pending: [(Int, Int)] = [(0, points.count - 1)]
        while let (first, last) = pending.popLast() {
            guard last > first + 1 else { continue }
            var farthest: CGFloat = 0
            var farthestIndex = -1
            for position in (first + 1)..<last {
                let value = perpendicularDistance(points[position], from: points[first], to: points[last])
                if value > farthest {
                    farthest = value
                    farthestIndex = position
                }
            }
            guard farthestIndex >= 0, farthest > tolerance else { continue }
            keep[farthestIndex] = true
            pending.append((first, farthestIndex))
            pending.append((farthestIndex, last))
        }

        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for index in points.indices where keep[index] { result.append(points[index]) }
        return result
    }

    /// Removes vertices between segments that point almost the same way, so an over-simplified
    /// rounded corner does not count as an extra corner.
    static func mergeStraightRuns(_ points: [CGPoint], angle: CGFloat) -> [CGPoint] {
        var vertices = points
        var didMerge = true
        while didMerge, vertices.count > 2 {
            didMerge = false
            for index in 0..<(vertices.count - 2) {
                let first = angleOf(vertices[index], vertices[index + 1])
                let second = angleOf(vertices[index + 1], vertices[index + 2])
                var delta = second - first
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                if abs(delta) < angle {
                    vertices.remove(at: index + 1)
                    didMerge = true
                    break
                }
            }
        }
        return vertices
    }

    private static func rawSegments(_ vertices: [CGPoint]) -> [Segment] {
        guard vertices.count > 1 else { return [] }
        var segments: [Segment] = []
        segments.reserveCapacity(vertices.count - 1)
        var total: CGFloat = 0
        for index in 0..<(vertices.count - 1) {
            let dx = vertices[index + 1].x - vertices[index].x
            let dy = vertices[index + 1].y - vertices[index].y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { continue }
            segments.append(Segment(direction: CGVector(dx: dx / length, dy: dy / length), lengthFraction: length))
            total += length
        }
        guard total > 0 else { return [] }
        for index in segments.indices { segments[index].lengthFraction /= total }
        return segments
    }

    private static func angleOf(_ from: CGPoint, _ to: CGPoint) -> CGFloat {
        atan2(to.y - from.y, to.x - from.x)
    }

    static func perpendicularDistance(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let denominator = (dx * dx + dy * dy).squareRoot()
        guard denominator > 0 else {
            let px = point.x - start.x
            let py = point.y - start.y
            return (px * px + py * py).squareRoot()
        }
        return abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x) / denominator
    }
}

/// Decides which metric applies to a stored gesture, and keeps the two implementations of
/// "how far apart are these two shapes" in one place so the recogniser, the settings window's
/// conflict warning and the recorder can never disagree.
public enum StrokeMatching {
    /// A stored trajectory that comes back to where it started is a *retrace*: the user draws it
    /// as a loop, and the calibrated loop tolerance only exists in the arc-length metric.
    public static func metric(forStoredPoints points: [CGPoint]) -> StrokeMetric {
        guard points.count > 1 else { return .structure }
        let length = StrokeNormalizer.pathLength(points)
        guard length > 0 else { return .structure }
        let start = points[0]
        let end = points[points.count - 1]
        // Spelled out rather than calling the module-level `distance(_:_:)`, which this type's own
        // `distance(_:_:settings:)` shadows.
        let dx = end.x - start.x
        let dy = end.y - start.y
        let startToEnd = (dx * dx + dy * dy).squareRoot()
        return startToEnd <= 0.10 * length ? .arcLength : .structure
    }

    public static func threshold(
        for metric: StrokeMetric,
        settings: RecognitionSettings = RecognitionSettings()
    ) -> CGFloat {
        switch metric {
        case .structure: settings.structureThreshold
        case .arcLength: settings.matchThreshold
        }
    }

    /// The metric-specific distance between a live drawing and a stored definition, both in
    /// screen coordinates and drawing order.
    ///
    /// Convenient form for the settings window and the recorder; the recogniser uses the
    /// precomputed `PreparedGesture` instead, so its hot path stays allocation free.
    public static func distance(
        livePoints: [CGPoint],
        storedPoints: [CGPoint],
        settings: RecognitionSettings = RecognitionSettings()
    ) -> CGFloat {
        switch metric(forStoredPoints: storedPoints) {
        case .structure:
            guard let live = StrokeStructure.make(from: livePoints, settings: settings.structure),
                  let stored = StrokeStructure.make(from: storedPoints, settings: settings.structure)
            else { return .infinity }
            return StrokeStructure.distance(live, stored, settings: settings.structure)

        case .arcLength:
            let live = StrokeNormalizer.normalize(livePoints, sampleCount: settings.sampleCount)
            let stored = StrokeNormalizer.normalize(storedPoints, sampleCount: settings.sampleCount)
            return StrokeMatcher.distance(live, stored)
        }
    }
}
