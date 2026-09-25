import Foundation

/// A point in diagram space. Diagram space has its origin at the top left
/// with y increasing downward, matching SVG.
public struct Point: Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point(0, 0)

    public static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
    public static func - (a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y) }
    public static func * (a: Point, k: Double) -> Point { Point(a.x * k, a.y * k) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: Point) -> Double { (other - self).length }

    /// The unit vector pointing the same way, or zero for the zero vector.
    public var normalized: Point {
        let l = length
        return l == 0 ? .zero : Point(x / l, y / l)
    }

    public func interpolated(to other: Point, _ t: Double) -> Point {
        Point(x + (other.x - x) * t, y + (other.y - y) * t)
    }

    public var description: String { "(\(x), \(y))" }
}

public struct Size: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(_ width: Double, _ height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Size(0, 0)
}

public struct Rect: Hashable, Sendable, CustomStringConvertible {
    public var origin: Point
    public var size: Size

    public init(x: Double, y: Double, width: Double, height: Double) {
        origin = Point(x, y)
        size = Size(width, height)
    }

    public init(center: Point, size: Size) {
        self.init(x: center.x - size.width / 2, y: center.y - size.height / 2,
                  width: size.width, height: size.height)
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }
    public var width: Double { size.width }
    public var height: Double { size.height }
    public var center: Point { Point(midX, midY) }

    public func insetBy(dx: Double, dy: Double) -> Rect {
        Rect(x: minX + dx, y: minY + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    public func offsetBy(dx: Double, dy: Double) -> Rect {
        Rect(x: minX + dx, y: minY + dy, width: width, height: height)
    }

    public func union(_ other: Rect) -> Rect {
        let x0 = min(minX, other.minX), y0 = min(minY, other.minY)
        return Rect(x: x0, y: y0, width: max(maxX, other.maxX) - x0, height: max(maxY, other.maxY) - y0)
    }

    public func contains(_ p: Point) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }

    public func intersects(_ other: Rect) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }

    /// The smallest rectangle containing every point, or nil for none.
    public static func bounding(_ points: some Sequence<Point>) -> Rect? {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else { return nil }
        var x0 = first.x, y0 = first.y, x1 = first.x, y1 = first.y
        while let p = iterator.next() {
            x0 = min(x0, p.x); y0 = min(y0, p.y); x1 = max(x1, p.x); y1 = max(y1, p.y)
        }
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public var description: String { "(\(minX), \(minY), \(width), \(height))" }
}
