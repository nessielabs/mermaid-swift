/// Interpolation used to draw an edge through its route points, named as
/// in Mermaid's `curve` configuration (d3 curve names).
public enum Curve: String, Hashable, Sendable, CaseIterable {
    case basis, linear, step, stepBefore, stepAfter, cardinal, catmullRom, monotoneX, monotoneY, natural, bumpX, bumpY

    /// Parses Mermaid's names, ignoring case (`basis`, `stepAfter`, ...).
    public init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else { return nil }
        self = match
    }

    /// Builds a path through `points`.
    public func path(through points: [Point]) -> Path {
        guard points.count > 2 else { return .polyline(points) }
        switch self {
        case .linear: return .polyline(points)
        case .basis: return Self.basis(points)
        case .step: return Self.step(points, t: 0.5)
        case .stepBefore: return Self.step(points, t: 0)
        case .stepAfter: return Self.step(points, t: 1)
        case .cardinal, .catmullRom, .natural, .monotoneX, .monotoneY: return Self.cardinal(points, tension: self == .cardinal ? 0 : 0.5)
        case .bumpX, .bumpY: return Self.bump(points, vertical: self == .bumpY)
        }
    }

    /// d3's `curveBasis`: a uniform cubic B-spline that starts and ends at
    /// the first and last points and treats interior points as controls.
    static func basis(_ p: [Point]) -> Path {
        var path = Path()
        path.move(to: p[0])
        path.line(to: (p[0] * 5 + p[1]) * (1.0 / 6))
        func segment(_ a: Point, _ b: Point, _ c: Point) {
            path.curve(to: (a + b * 4 + c) * (1.0 / 6), control1: (a * 2 + b) * (1.0 / 3), control2: (a + b * 2) * (1.0 / 3))
        }
        for i in 2..<p.count { segment(p[i - 2], p[i - 1], p[i]) }
        let n = p.count
        segment(p[n - 2], p[n - 1], p[n - 1])
        path.line(to: p[n - 1])
        return path
    }

    static func step(_ p: [Point], t: Double) -> Path {
        var path = Path()
        path.move(to: p[0])
        for (a, b) in zip(p, p.dropFirst()) {
            let x = a.x + (b.x - a.x) * t
            path.line(to: Point(x, a.y))
            path.line(to: Point(x, b.y))
            path.line(to: b)
        }
        return path
    }

    /// A cardinal spline through every point (tension 0.5 = Catmull-Rom).
    static func cardinal(_ p: [Point], tension: Double) -> Path {
        var path = Path()
        path.move(to: p[0])
        let k = (1 - tension) / 3
        for i in 0..<(p.count - 1) {
            let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
            path.curve(to: p2, control1: p1 + (p2 - p0) * k, control2: p2 - (p3 - p1) * k)
        }
        return path
    }

    static func bump(_ p: [Point], vertical: Bool) -> Path {
        var path = Path()
        path.move(to: p[0])
        for (a, b) in zip(p, p.dropFirst()) {
            if vertical {
                let my = (a.y + b.y) / 2
                path.curve(to: b, control1: Point(a.x, my), control2: Point(b.x, my))
            } else {
                let mx = (a.x + b.x) / 2
                path.curve(to: b, control1: Point(mx, a.y), control2: Point(mx, b.y))
            }
        }
        return path
    }
}
