import CoreGraphics
import Foundation

/// Turns a drawn trajectory into a form that can be compared with a stored gesture no matter
/// where on screen it was drawn, how large it was, or how fast it was drawn.
///
/// The transform is: resample to a fixed number of *equidistant* points (kills speed and
/// sample-rate differences), translate so the stroke starts at the origin (kills position),
/// then scale so the total path length is 1 (kills size).
///
/// Rotation and reflection are deliberately **not** normalised away: an up-stroke and a
/// down-stroke must stay distinguishable.
public enum StrokeNormalizer {
    /// - Returns: `sampleCount` normalised points, or an empty array when the stroke has no
    ///   length and therefore nothing to compare.
    public static func normalize(_ points: [CGPoint], sampleCount: Int) -> [CGPoint] {
        guard sampleCount > 1 else { return [] }
        let resampled = resample(points, count: sampleCount)
        guard resampled.count == sampleCount, let origin = resampled.first else { return [] }

        let translated = resampled.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        let length = pathLength(translated)
        guard length > 0 else { return [] }
        return translated.map { CGPoint(x: $0.x / length, y: $0.y / length) }
    }

    /// Resamples a polyline into `count` points spaced equally along its arc length.
    public static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard count > 1 else { return points.isEmpty ? [] : [points[0]] }
        guard points.count > 1 else {
            return points.isEmpty ? [] : Array(repeating: points[0], count: count)
        }

        let interval = pathLength(points) / CGFloat(count - 1)
        guard interval > 0 else {
            return Array(repeating: points[0], count: count)
        }

        var result: [CGPoint] = [points[0]]
        var accumulated: CGFloat = 0
        var previous = points[0]

        for point in points.dropFirst() {
            var segment = distance(previous, point)
            guard segment > 0 else { continue }

            while accumulated + segment >= interval {
                let ratio = (interval - accumulated) / segment
                let next = CGPoint(
                    x: previous.x + (point.x - previous.x) * ratio,
                    y: previous.y + (point.y - previous.y) * ratio
                )
                result.append(next)
                previous = next
                segment = distance(previous, point)
                accumulated = 0
                if result.count == count { return result }
            }

            accumulated += segment
            previous = point
        }

        while result.count < count {
            result.append(points[points.count - 1])
        }
        return result
    }

    public static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        var previous = points[0]
        for point in points.dropFirst() {
            total += distance(previous, point)
            previous = point
        }
        return total
    }
}

/// Compares normalised strokes.
public enum StrokeMatcher {
    /// Mean distance between two equally sized normalised point lists.
    ///
    /// Because both sides are scaled to a path length of 1, the result is a fraction of the
    /// stroke length: 0 is an exact match.
    public static func distance(_ lhs: [CGPoint], _ rhs: [CGPoint]) -> CGFloat {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return .infinity }
        var total: CGFloat = 0
        for index in lhs.indices {
            // Spelled out rather than calling the module-level `distance(_:_:)` for two points,
            // which this overload would shadow.
            let dx = lhs[index].x - rhs[index].x
            let dy = lhs[index].y - rhs[index].y
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total / CGFloat(lhs.count)
    }

    /// Distance between a live stroke and a stored gesture definition.
    public static func distance(
        stroke: Stroke,
        definition: WGStrokeStep,
        sampleCount: Int
    ) -> CGFloat {
        let live = StrokeNormalizer.normalize(stroke.points, sampleCount: sampleCount)
        let stored = StrokeNormalizer.normalize(definition.drawingOrderPoints, sampleCount: sampleCount)
        return distance(live, stored)
    }
}
