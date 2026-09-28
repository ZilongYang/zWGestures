import CoreGraphics

/// Rectangle arithmetic for the on-screen trail.
///
/// The overlay used to invalidate the **whole view** whenever it redrew, which meant re-uploading a
/// full-screen layer (4608×2592 ≈ 12 M pixels on a 27" Retina display) for the sake of a few moving
/// pixels. That made frames expensive enough for the fade to advance in coarse jumps, and a frame
/// that skipped past `alpha == 0` left a faint copy of the trail on screen — the ghost the user
/// reported. Invalidate only what the stroke actually occupies instead.
public enum TrailBounds {
    /// The bounding box a stroked polyline covers, inflated by half the line width.
    ///
    /// Returns `nil` for an empty point list, which is what makes "nothing to draw" distinguishable
    /// from "a zero-sized rectangle at the origin".
    public static func of(points: [CGPoint], lineWidth: CGFloat) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y)
            maxY = Swift.max(maxY, point.y)
        }
        // Round caps/joins stick out by half the line width, plus a pixel for antialiasing.
        let slack = lineWidth / 2 + 1
        return CGRect(
            x: minX - slack,
            y: minY - slack,
            width: (maxX - minX) + slack * 2,
            height: (maxY - minY) + slack * 2
        )
    }

    /// The smallest rectangle containing both, treating `nil` as "nothing".
    public static func union(_ lhs: CGRect?, _ rhs: CGRect?) -> CGRect? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case (let rect?, nil): rect
        case (nil, let rect?): rect
        case (let a?, let b?): a.union(b)
        }
    }
}
