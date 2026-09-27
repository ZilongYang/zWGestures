import CoreGraphics
import Foundation

/// A recorded pointer trajectory, in global screen coordinates.
public struct Stroke: Sendable, Equatable {
    public private(set) var points: [CGPoint]
    public private(set) var timestamps: [TimeInterval]

    public init(start: CGPoint, timestamp: TimeInterval) {
        points = [start]
        timestamps = [timestamp]
    }

    /// Appends `point` when it is far enough (and late enough) to be a meaningful sample.
    ///
    /// - Returns: whether the point was appended.
    @discardableResult
    public mutating func append(
        _ point: CGPoint,
        timestamp: TimeInterval,
        minDistance: CGFloat,
        minInterval: TimeInterval
    ) -> Bool {
        guard let previous = points.last, let previousTime = timestamps.last else {
            points.append(point)
            timestamps.append(timestamp)
            return true
        }
        guard distance(previous, point) >= minDistance,
              timestamp - previousTime >= minInterval
        else { return false }

        points.append(point)
        timestamps.append(timestamp)
        return true
    }

    public var startPoint: CGPoint { points.first ?? .zero }
    public var endPoint: CGPoint { points.last ?? .zero }
    public var duration: TimeInterval {
        guard let first = timestamps.first, let last = timestamps.last else { return 0 }
        return last - first
    }

    public var isEmpty: Bool { points.isEmpty }

    public var boundingBox: CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y)
            maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public var pathLength: CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// Total change of direction along the stroke, in radians. Small values mean a
    /// straight line; large values mean a curvy or multi-segment shape.
    public var totalTurn: CGFloat {
        guard points.count >= 3 else { return 0 }
        var total: CGFloat = 0
        for index in 1..<(points.count - 1) {
            let a = angle(from: points[index - 1], to: points[index])
            let b = angle(from: points[index], to: points[index + 1])
            var delta = b - a
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            total += abs(delta)
        }
        return total
    }

    /// Resamples the trajectory into `count` equally spaced points, keeping the shape.
    ///
    /// Used by the shape recogniser so that two strokes drawn at different speeds and
    /// sizes can be compared.
    public func resampled(count: Int) -> [CGPoint] {
        guard count > 1, points.count > 1 else {
            return Array(repeating: startPoint, count: Swift.max(count, 1))
        }

        let interval = pathLength / CGFloat(count - 1)
        guard interval > 0 else {
            return Array(repeating: startPoint, count: count)
        }

        var result: [CGPoint] = [startPoint]
        var accumulated: CGFloat = 0
        var previous = startPoint

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
            result.append(endPoint)
        }
        return result
    }
}

/// Euclidean distance between two points.
public func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}

/// Angle of the vector `a -> b`, in radians.
public func angle(from a: CGPoint, to b: CGPoint) -> CGFloat {
    atan2(b.y - a.y, b.x - a.x)
}
