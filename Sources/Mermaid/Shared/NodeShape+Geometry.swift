/// The drawable parts of a node shape placed in a frame.
public struct ShapeGeometry: Sendable {
    public enum Fill: Sendable { case node, solid, none }

    /// The main outline, filled and stroked with the node's colors.
    public var body: Path
    /// Copies drawn behind the body with the same colors (stacked shapes).
    public var backgrounds: [Path] = []
    /// Extra lines stroked on top of the body.
    public var details: [Path] = []
    public var fill: Fill = .node
    public var stroked = true
    /// Where the label's center goes.
    public var labelCenter: Point
}

extension NodeShape {
    public func geometry(in r: Rect) -> ShapeGeometry {
        let (x0, y0, x1, y1, w, h, cx, cy) = (r.minX, r.minY, r.maxX, r.maxY, r.width, r.height, r.midX, r.midY)
        var g = ShapeGeometry(body: .rect(r), labelCenter: r.center)
        func poly(_ points: [(Double, Double)]) -> Path { .polygon(points.map { Point($0.0, $0.1) }) }
        func line(_ a: (Double, Double), _ b: (Double, Double)) -> Path { .polyline([Point(a.0, a.1), Point(b.0, b.1)]) }
        switch self {
        case .rect, .text:
            if self == .text { g.fill = .none; g.stroked = false }
        case .rounded: g.body = .rect(r, cornerRadius: 5)
        case .stadium: g.body = .rect(r, cornerRadius: h / 2)
        case .subroutine: g.details = [line((x0 + 8, y0), (x0 + 8, y1)), line((x1 - 8, y0), (x1 - 8, y1))]
        case .cylinder, .linedCylinder:
            let ry = NodeShape.capHeight(width: w)
            var body = Path()
            body.appendArc(center: Point(cx, y0 + ry), radiusX: w / 2, radiusY: ry, from: 180, to: 360, connect: false)
            body.line(to: Point(x1, y1 - ry))
            body.appendArc(center: Point(cx, y1 - ry), radiusX: w / 2, radiusY: ry, from: 0, to: 180, connect: true)
            body.close()
            g.body = body
            var rim = Path()
            rim.appendArc(center: Point(cx, y0 + ry), radiusX: w / 2, radiusY: ry, from: 0, to: 180, connect: false)
            g.details = [rim]
            if self == .linedCylinder {
                var second = Path()
                second.appendArc(center: Point(cx, y0 + 2.5 * ry), radiusX: w / 2, radiusY: ry, from: 0, to: 180, connect: false)
                g.details.append(second)
            }
            g.labelCenter = Point(cx, cy + ry / 2)
        case .horizontalCylinder:
            let rx = min(h / 4, w / 6)
            var body = Path()
            body.move(to: Point(x0 + rx, y0))
            body.line(to: Point(x1 - rx, y0))
            body.appendArc(center: Point(x1 - rx, cy), radiusX: rx, radiusY: h / 2, from: 270, to: 450, connect: true)
            body.line(to: Point(x0 + rx, y1))
            body.appendArc(center: Point(x0 + rx, cy), radiusX: rx, radiusY: h / 2, from: 90, to: 270, connect: true)
            body.close()
            g.body = body
            var rim = Path()
            rim.appendArc(center: Point(x1 - rx, cy), radiusX: rx, radiusY: h / 2, from: 90, to: 270, connect: false)
            g.details = [rim]
            g.labelCenter = Point(cx - rx / 2, cy)
        case .circle, .smallCircle: g.body = .ellipse(in: r)
        case .filledCircle: g.body = .ellipse(in: r); g.fill = .solid
        case .doubleCircle: g.body = .ellipse(in: r); g.details = [.ellipse(in: r.insetBy(dx: 5, dy: 5))]
        case .framedCircle:
            g.body = .ellipse(in: r)
            g.details = [.ellipse(in: r.insetBy(dx: 5, dy: 5))]
            g.backgrounds = []
        case .crossedCircle:
            g.body = .ellipse(in: r)
            let d = w / 2 * 0.7071
            g.details = [line((cx - d, cy - d), (cx + d, cy + d)), line((cx - d, cy + d), (cx + d, cy - d))]
        case .forkJoin: g.fill = .solid
        case .diamond: g.body = poly([(cx, y0), (x1, cy), (cx, y1), (x0, cy)])
        case .hexagon: let m = h / 4; g.body = poly([(x0 + m, y0), (x1 - m, y0), (x1, cy), (x1 - m, y1), (x0 + m, y1), (x0, cy)])
        case .leanRight: let k = h / 2; g.body = poly([(x0 + k, y0), (x1, y0), (x1 - k, y1), (x0, y1)])
        case .leanLeft: let k = h / 2; g.body = poly([(x0, y0), (x1 - k, y0), (x1, y1), (x0 + k, y1)])
        case .trapezoid: let k = h / 4; g.body = poly([(x0 + k, y0), (x1 - k, y0), (x1, y1), (x0, y1)])
        case .invertedTrapezoid: let k = h / 4; g.body = poly([(x0, y0), (x1, y0), (x1 - k, y1), (x0 + k, y1)])
        case .asymmetric:
            g.body = poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0 + h / 4, cy)])
            g.labelCenter = Point(cx + h / 8, cy)
        case .notchedRect: g.body = poly([(x0 + 12, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0 + 12)])
        case .linedRect: g.details = [line((x0 + 8, y0), (x0 + 8, y1))]
        case .hourglass: g.body = poly([(x0, y0), (x1, y0), (x0, y1), (x1, y1)])
        case .braceLeft, .braceRight, .braces:
            g.fill = .none
            g.stroked = false
            if self != .braceRight { g.details.append(Self.brace(x: x0 + 6, y0: y0, y1: y1, facing: -1)) }
            if self != .braceLeft { g.details.append(Self.brace(x: x1 - 6, y0: y0, y1: y1, facing: 1)) }
        case .bolt:
            g.body = poly([(x0 + 0.62 * w, y0), (x0 + 0.1 * w, y0 + 0.58 * h), (x0 + 0.45 * w, y0 + 0.58 * h),
                           (x0 + 0.3 * w, y1), (x0 + 0.9 * w, y0 + 0.4 * h), (x0 + 0.55 * w, y0 + 0.4 * h), (x0 + 0.8 * w, y0)])
        case .document, .linedDocument, .taggedDocument:
            let a = h * 0.08
            g.body = Self.wavyBottom(r, amplitude: a)
            g.labelCenter = Point(cx, cy - a)
            if self == .linedDocument { g.details = [line((x0 + 8, y0), (x0 + 8, y1 - a))] }
            if self == .taggedDocument { g.details = [line((x1 - w * 0.2, y1 - a * 0.6), (x1, y1 - a * 3))] }
        case .documents:
            let front = Rect(x: x0, y: y0 + 10, width: w - 10, height: h - 10)
            let a = front.height * 0.08
            g.body = Self.wavyBottom(front, amplitude: a)
            g.backgrounds = [Self.wavyBottom(front.offsetBy(dx: 10, dy: -10), amplitude: a),
                             Self.wavyBottom(front.offsetBy(dx: 5, dy: -5), amplitude: a)]
            g.labelCenter = Point(front.midX, front.midY - a)
        case .stackedRect:
            let front = Rect(x: x0, y: y0 + 10, width: w - 10, height: h - 10)
            g.body = .rect(front)
            g.backgrounds = [.rect(front.offsetBy(dx: 10, dy: -10)), .rect(front.offsetBy(dx: 5, dy: -5))]
            g.labelCenter = front.center
        case .delay:
            var body = Path()
            body.move(to: Point(x0, y0))
            body.line(to: Point(x1 - h / 2, y0))
            body.appendArc(center: Point(x1 - h / 2, cy), radius: h / 2, from: 270, to: 450, connect: true)
            body.line(to: Point(x0, y1))
            body.close()
            g.body = body
        case .curvedTrapezoid:
            var body = Path()
            body.move(to: Point(x0 + h / 4, y0))
            body.line(to: Point(x1 - h / 2, y0))
            body.appendArc(center: Point(x1 - h / 2, cy), radius: h / 2, from: 270, to: 450, connect: true)
            body.line(to: Point(x0 + h / 4, y1))
            body.line(to: Point(x0, cy))
            body.close()
            g.body = body
        case .dividedRect:
            g.details = [line((x0, y0 + h * 0.2), (x1, y0 + h * 0.2))]
            g.labelCenter = Point(cx, cy + h * 0.1)
        case .flag:
            let a = h * 0.08
            var body = Path()
            body.move(to: Point(x0, y0 + a))
            body.curve(to: Point(cx, y0 + a), control1: Point(x0 + w / 6, y0 - a), control2: Point(cx - w / 6, y0 - a))
            body.curve(to: Point(x1, y0 + a), control1: Point(cx + w / 6, y0 + 3 * a), control2: Point(x1 - w / 6, y0 + 3 * a))
            body.line(to: Point(x1, y1 - a))
            body.curve(to: Point(cx, y1 - a), control1: Point(x1 - w / 6, y1 + a), control2: Point(cx + w / 6, y1 + a))
            body.curve(to: Point(x0, y1 - a), control1: Point(cx - w / 6, y1 - 3 * a), control2: Point(x0 + w / 6, y1 - 3 * a))
            body.close()
            g.body = body
        case .triangle:
            g.body = poly([(cx, y0), (x1, y1), (x0, y1)])
            g.labelCenter = Point(cx, y0 + h * 0.62)
        case .flippedTriangle:
            g.body = poly([(x0, y0), (x1, y0), (cx, y1)])
            g.labelCenter = Point(cx, y0 + h * 0.38)
        case .windowPane: g.details = [line((x0 + 10, y0), (x0 + 10, y1)), line((x0, y0 + 10), (x1, y0 + 10))]
        case .notchedPentagon:
            let m = h / 4
            g.body = poly([(x0 + m, y0), (x1 - m, y0), (x1, y0 + m), (x1, y1), (x0, y1), (x0, y0 + m)])
        case .bowTieRect:
            let k = h / 4
            var body = Path()
            body.move(to: Point(x0 + k, y0))
            body.line(to: Point(x1, y0))
            body.curve(to: Point(x1, y1), control1: Point(x1 - k * 1.3, y0 + h / 3), control2: Point(x1 - k * 1.3, y1 - h / 3))
            body.line(to: Point(x0 + k, y1))
            body.curve(to: Point(x0 + k, y0), control1: Point(x0 - k * 0.3, y1 - h / 3), control2: Point(x0 - k * 0.3, y0 + h / 3))
            body.close()
            g.body = body
        case .taggedRect: g.details = [line((x1 - 12, y1), (x1, y1 - 12))]
        case .slopedRect:
            let s = h / 5
            g.body = poly([(x0, y0 + s), (x1, y0), (x1, y1), (x0, y1)])
            g.labelCenter = Point(cx, cy + s / 2)
        }
        return g
    }

    /// The outline used to attach edges, as a polygon.
    public func outline(in r: Rect) -> [Point] {
        switch self {
        case .text, .braceLeft, .braceRight, .braces: return EdgeGeometry.rectOutline(r)
        default: return geometry(in: r).body.flattened()
        }
    }

    private static func wavyBottom(_ r: Rect, amplitude a: Double) -> Path {
        let yb = r.maxY - a, w = r.width
        var path = Path()
        path.move(to: r.origin)
        path.line(to: Point(r.maxX, r.minY))
        path.line(to: Point(r.maxX, yb))
        path.curve(to: Point(r.midX, yb), control1: Point(r.maxX - w / 6, yb - 1.5 * a), control2: Point(r.midX + w / 6, yb - 1.5 * a))
        path.curve(to: Point(r.minX, yb), control1: Point(r.midX - w / 6, yb + 1.5 * a), control2: Point(r.minX + w / 6, yb + 1.5 * a))
        path.close()
        return path
    }

    private static func brace(x: Double, y0: Double, y1: Double, facing: Double) -> Path {
        let cy = (y0 + y1) / 2, k = 6 * facing
        var path = Path()
        path.move(to: Point(x - k, y0))
        path.curve(to: Point(x, y0 + 8), control1: Point(x - k * 0.2, y0), control2: Point(x, y0 + 3))
        path.line(to: Point(x, cy - 6))
        path.curve(to: Point(x + k, cy), control1: Point(x, cy - 2), control2: Point(x + k * 0.5, cy))
        path.curve(to: Point(x, cy + 6), control1: Point(x + k * 0.5, cy), control2: Point(x, cy + 2))
        path.line(to: Point(x, y1 - 8))
        path.curve(to: Point(x - k, y1), control1: Point(x, y1 - 3), control2: Point(x - k * 0.2, y1))
        return path
    }
}

extension Path {
    /// Approximates the path as a polygon by sampling curves.
    public func flattened(samplesPerCurve: Int = 8) -> [Point] {
        var points: [Point] = []
        var current = Point.zero
        for element in elements {
            switch element {
            case .move(let p), .line(let p):
                points.append(p)
                current = p
            case .curve(let c1, let c2, let p):
                for i in 1...samplesPerCurve {
                    let t = Double(i) / Double(samplesPerCurve), u = 1 - t
                    points.append(current * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + p * (t * t * t))
                }
                current = p
            case .close: break
            }
        }
        return points
    }
}
