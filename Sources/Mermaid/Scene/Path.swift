import Foundation

/// A vector path made of lines and cubic Bézier curves.
///
/// Shapes such as ellipses and arcs are converted to cubic curves when
/// they are built, so every renderer needs only four primitives.
public struct Path: Hashable, Sendable {
    public enum Element: Hashable, Sendable {
        case move(Point)
        case line(Point)
        case curve(Point, Point, Point)
        case close
    }

    public private(set) var elements: [Element] = []

    public init() {}

    static func fromElements(_ elements: [Element]) -> Path {
        var path = Path()
        path.elements = elements
        return path
    }

    public var isEmpty: Bool { elements.isEmpty }

    public mutating func move(to p: Point) { elements.append(.move(p)) }
    public mutating func line(to p: Point) { elements.append(.line(p)) }
    public mutating func curve(to p: Point, control1: Point, control2: Point) {
        elements.append(.curve(control1, control2, p))
    }
    public mutating func close() { elements.append(.close) }

    public mutating func append(_ other: Path) { elements += other.elements }

    /// The bounding box of all points and control points. Control points can
    /// lie outside the drawn curve, so this may be slightly larger than the
    /// ink, which is the safe direction for sizing a canvas.
    public var bounds: Rect? {
        Rect.bounding(elements.flatMap { element -> [Point] in
            switch element {
            case .move(let p), .line(let p): return [p]
            case .curve(let a, let b, let c): return [a, b, c]
            case .close: return []
            }
        })
    }

    public func transformed(_ transform: (Point) -> Point) -> Path {
        var path = Path()
        path.elements = elements.map {
            switch $0 {
            case .move(let p): return .move(transform(p))
            case .line(let p): return .line(transform(p))
            case .curve(let a, let b, let c): return .curve(transform(a), transform(b), transform(c))
            case .close: return .close
            }
        }
        return path
    }

    public func offsetBy(dx: Double, dy: Double) -> Path {
        transformed { Point($0.x + dx, $0.y + dy) }
    }
}

// MARK: - Shape constructors

extension Path {
    public static func polyline(_ points: [Point]) -> Path {
        var path = Path()
        for (i, p) in points.enumerated() {
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        return path
    }

    public static func polygon(_ points: [Point]) -> Path {
        var path = polyline(points)
        if !points.isEmpty { path.close() }
        return path
    }

    public static func rect(_ r: Rect, cornerRadius: Double = 0) -> Path {
        let radius = min(cornerRadius, r.width / 2, r.height / 2)
        guard radius > 0 else {
            return polygon([r.origin, Point(r.maxX, r.minY), Point(r.maxX, r.maxY), Point(r.minX, r.maxY)])
        }
        var path = Path()
        path.move(to: Point(r.minX + radius, r.minY))
        path.line(to: Point(r.maxX - radius, r.minY))
        path.appendArc(center: Point(r.maxX - radius, r.minY + radius), radius: radius, from: -90, to: 0, connect: true)
        path.line(to: Point(r.maxX, r.maxY - radius))
        path.appendArc(center: Point(r.maxX - radius, r.maxY - radius), radius: radius, from: 0, to: 90, connect: true)
        path.line(to: Point(r.minX + radius, r.maxY))
        path.appendArc(center: Point(r.minX + radius, r.maxY - radius), radius: radius, from: 90, to: 180, connect: true)
        path.line(to: Point(r.minX, r.minY + radius))
        path.appendArc(center: Point(r.minX + radius, r.minY + radius), radius: radius, from: 180, to: 270, connect: true)
        path.close()
        return path
    }

    public static func ellipse(in r: Rect) -> Path {
        var path = Path()
        path.appendArc(center: r.center, radiusX: r.width / 2, radiusY: r.height / 2, from: 0, to: 360, connect: false)
        path.close()
        return path
    }

    public static func circle(center: Point, radius: Double) -> Path {
        ellipse(in: Rect(center: center, size: Size(radius * 2, radius * 2)))
    }

    /// Appends an elliptical arc between two angles in degrees, measured
    /// clockwise from the positive x axis (y points down). Uses cubic
    /// segments of at most 90°.
    public mutating func appendArc(center: Point, radiusX: Double, radiusY: Double,
                                   from start: Double, to end: Double, connect: Bool) {
        let point = { (deg: Double) in
            Point(center.x + radiusX * cos(deg * .pi / 180), center.y + radiusY * sin(deg * .pi / 180))
        }
        if connect { line(to: point(start)) } else { move(to: point(start)) }
        let segments = max(1, Int((abs(end - start) / 90).rounded(.up)))
        let step = (end - start) / Double(segments)
        let k = 4.0 / 3.0 * tan(step * .pi / 180 / 4)
        for i in 0..<segments {
            let a0 = (start + Double(i) * step) * .pi / 180
            let a1 = (start + Double(i + 1) * step) * .pi / 180
            let c1 = Point(center.x + radiusX * (cos(a0) - k * sin(a0)), center.y + radiusY * (sin(a0) + k * cos(a0)))
            let c2 = Point(center.x + radiusX * (cos(a1) + k * sin(a1)), center.y + radiusY * (sin(a1) - k * cos(a1)))
            curve(to: Point(center.x + radiusX * cos(a1), center.y + radiusY * sin(a1)), control1: c1, control2: c2)
        }
    }

    public mutating func appendArc(center: Point, radius: Double, from start: Double, to end: Double, connect: Bool) {
        appendArc(center: center, radiusX: radius, radiusY: radius, from: start, to: end, connect: connect)
    }
}
