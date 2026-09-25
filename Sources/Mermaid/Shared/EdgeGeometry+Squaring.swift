extension EdgeGeometry {
    /// The outward unit normal of the side of `frame` nearest to `point`.
    static func outwardNormal(of frame: Rect, at point: Point) -> Point {
        let distances: [(Double, Point)] = [
            (abs(point.y - frame.minY), Point(0, -1)), (abs(point.y - frame.maxY), Point(0, 1)),
            (abs(point.x - frame.minX), Point(-1, 0)), (abs(point.x - frame.maxX), Point(1, 0)),
        ]
        return distances.min { $0.0 < $1.0 }!.1
    }

    /// Bends a clipped route so its last `length` units arrive straight
    /// through the side of `frame` it ends on, perpendicular to that side.
    ///
    /// End notations such as crow's feet read correctly only when the line
    /// meets the box head-on; a route that arrives diagonally gains a point
    /// `length` out from the box, and bends already on that perpendicular
    /// but closer than `length` move out to it. Other interior bends
    /// within twice `length` of the box are dropped (except `keeping`, such
    /// as a label anchor) so the curve does not hook into the stub.
    static func squaringEnd(_ points: [Point], at frame: Rect, length: Double, keeping: Point? = nil) -> [Point] {
        guard points.count >= 2, length > 0 else { return points }
        let tip = points[points.count - 1]
        let normal = outwardNormal(of: frame, at: tip)
        var result = Array(points.dropLast())
        // Drop interior bends that sit on the approach line inside the stub.
        while result.count > 1, let last = result.last {
            let offset = last - tip
            let along = offset.x * normal.x + offset.y * normal.y
            let across = abs(offset.x * normal.y - offset.y * normal.x)
            let onApproach = across < 1 && along < length
            let crowding = along < 2 * length && last != keeping
            guard onApproach || crowding else { break }
            result.removeLast()
        }
        let previous = result[result.count - 1] - tip
        let along = previous.x * normal.x + previous.y * normal.y
        let across = abs(previous.x * normal.y - previous.y * normal.x)
        if across >= 1 || along < length {
            result.append(tip + normal * length)
        }
        result.append(tip)
        return result
    }
}
