import Foundation

/// Geometry shared by every diagram that draws connectors.
enum EdgeGeometry {
    /// Intersects segment `a`→`b` with a closed polygon, returning the hit
    /// closest to `a`.
    static func intersection(from a: Point, to b: Point, polygon: [Point]) -> Point? {
        var best: (t: Double, p: Point)?
        for (i, p) in polygon.enumerated() {
            let q = polygon[(i + 1) % polygon.count]
            let r = b - a, s = q - p
            let denom = r.x * s.y - r.y * s.x
            guard abs(denom) > 1e-9 else { continue }
            let t = ((p.x - a.x) * s.y - (p.y - a.y) * s.x) / denom
            let u = ((p.x - a.x) * r.y - (p.y - a.y) * r.x) / denom
            if t >= -1e-9, t <= 1 + 1e-9, u >= -1e-9, u <= 1 + 1e-9, best.map({ t < $0.t }) ?? true {
                best = (t, a + r * t)
            }
        }
        return best?.p
    }

    /// Trims a route so it starts on `source` and ends on `target`, each
    /// given as a closed outline. Interior points that fall inside an
    /// endpoint shape are dropped.
    static func clip(_ route: [Point], source: [Point]?, target: [Point]?) -> [Point] {
        var points = route
        guard points.count >= 2 else { return points }
        if let target, let outline = Rect.bounding(target) {
            while points.count > 2, outline.contains(points[points.count - 2]), inside(points[points.count - 2], target) {
                points.remove(at: points.count - 2)
            }
            if let hit = intersection(from: points[points.count - 2], to: points[points.count - 1], polygon: target)
                ?? intersection(from: points[points.count - 1], to: points[points.count - 2], polygon: target) {
                points[points.count - 1] = hit
            }
        }
        if let source, let outline = Rect.bounding(source) {
            while points.count > 2, outline.contains(points[1]), inside(points[1], source) {
                points.remove(at: 1)
            }
            if let hit = intersection(from: points[1], to: points[0], polygon: source)
                ?? intersection(from: points[0], to: points[1], polygon: source) {
                points[0] = hit
            }
        }
        return points
    }

    /// Even-odd point-in-polygon test.
    static func inside(_ p: Point, _ polygon: [Point]) -> Bool {
        var result = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { result.toggle() }
            j = i
        }
        return result
    }

    static func rectOutline(_ r: Rect) -> [Point] {
        [r.origin, Point(r.maxX, r.minY), Point(r.maxX, r.maxY), Point(r.minX, r.maxY)]
    }

    /// Samples an ellipse inscribed in `r` as a polygon.
    static func ellipseOutline(_ r: Rect, segments: Int = 48) -> [Point] {
        (0..<segments).map { i in
            let a = Double(i) / Double(segments) * 2 * .pi
            return Point(r.midX + r.width / 2 * cos(a), r.midY + r.height / 2 * sin(a))
        }
    }

    /// Moves the end of a polyline back by `distance` along its last
    /// segment, so a stroke stops at an arrowhead's base.
    static func shortenEnd(_ points: [Point], by distance: Double) -> [Point] {
        guard distance > 0, points.count >= 2 else { return points }
        var points = points
        let n = points.count
        let direction = (points[n - 1] - points[n - 2]).normalized
        let length = points[n - 1].distance(to: points[n - 2])
        points[n - 1] = points[n - 1] - direction * min(distance, max(0, length - 0.5))
        return points
    }

    static func shortenStart(_ points: [Point], by distance: Double) -> [Point] {
        shortenEnd(points.reversed(), by: distance).reversed()
    }
}
