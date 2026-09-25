import Foundation

/// Sizes and outlines of mindmap nodes, following mermaid.js's mindmap
/// `svgDraw`: the label wraps at `maxNodeWidth`, padding doubles for
/// rectangles, rounded rectangles and hexagons, and clouds and bangs are
/// traced with the same arc sequences.
extension MindmapDiagram.Shape {
    /// The padding between label and outline for a configured `padding`.
    func padding(_ base: Double) -> Double {
        switch self {
        case .rect, .rounded, .hexagon: return base * 2
        default: return base
        }
    }

    /// The node size around a label of `label` size; `fontSize` adds the
    /// breathing room mermaid.js reserves under the text.
    func size(label: Size, padding base: Double, fontSize: Double, hasIcon: Bool) -> Size {
        let p = padding(base)
        var w = label.width + 2 * p
        var h = label.height + fontSize * 1.1 * 0.5 + p
        switch self {
        case .circle:
            let d = max(w, h + p)
            w = d; h = d
            if hasIcon { w += 50; h += 50 }
        case .cloud, .bang:
            // The arcs bulge beyond the box, so give the label a little more room.
            w += 2 * p; h += p
            if hasIcon { w += 50; h = max(h, 60) }
        default:
            if hasIcon { w += 50; h = max(h, 60) }
        }
        return Size(w, h)
    }

    /// The outline of a node occupying `r`.
    func outline(in r: Rect, padding base: Double) -> Path {
        switch self {
        case .default:
            // A plate with rounded top corners and a flat bottom, as `defaultBkg`.
            let rd = min(5, r.width / 2, r.height / 2)
            var path = Path()
            path.move(to: Point(r.minX, r.maxY))
            path.line(to: Point(r.minX, r.minY + rd))
            path.curve(to: Point(r.minX + rd, r.minY), control1: Point(r.minX, r.minY + rd * 0.45), control2: Point(r.minX + rd * 0.45, r.minY))
            path.line(to: Point(r.maxX - rd, r.minY))
            path.curve(to: Point(r.maxX, r.minY + rd), control1: Point(r.maxX - rd * 0.45, r.minY), control2: Point(r.maxX, r.minY + rd * 0.45))
            path.line(to: Point(r.maxX, r.maxY))
            path.close()
            return path
        case .rect: return .rect(r)
        case .rounded: return .rect(r, cornerRadius: padding(base))
        case .circle: return .circle(center: r.center, radius: min(r.width, r.height) / 2)
        case .hexagon: return NodeShape.hexagon.geometry(in: r).body
        case .cloud: return Self.cloud(in: r)
        case .bang: return Self.bang(in: r)
        }
    }

    /// Traces relative SVG arcs `(rx, ry, dx, dy)` from the top-left corner.
    private static func arcs(from origin: Point, _ steps: [(Double, Double, Double, Double)], sweep: Bool) -> Path {
        var path = Path()
        var current = origin
        path.move(to: current)
        for (rx, ry, dx, dy) in steps {
            let next = Point(current.x + dx, current.y + dy)
            path.appendSVGArc(from: current, to: next, radiusX: rx, radiusY: ry, largeArc: false, sweep: sweep)
            current = next
        }
        path.close()
        return path
    }

    /// mermaid.js's cloud: ten outward-bulging arcs around the box.
    static func cloud(in r: Rect) -> Path {
        let w = r.width, h = r.height
        let r1 = 0.15 * w, r2 = 0.25 * w, r3 = 0.35 * w, r4 = 0.2 * w
        return arcs(from: r.origin, [
            (r1, r1, w * 0.25, -w * 0.1), (r3, r3, w * 0.4, -w * 0.1), (r2, r2, w * 0.35, w * 0.2),
            (r1, r1, w * 0.15, h * 0.35), (r4, r4, -w * 0.15, h * 0.65),
            (r2, r1, -w * 0.25, w * 0.15), (r3, r3, -w * 0.5, 0), (r1, r1, -w * 0.25, -w * 0.15),
            (r1, r1, -w * 0.1, -h * 0.35), (r4, r4, w * 0.1, -h * 0.65),
        ], sweep: true)
    }

    /// mermaid.js's bang: fourteen inward-curving arcs that make a burst.
    static func bang(in r: Rect) -> Path {
        let w = r.width, h = r.height, a = 0.15 * w
        return arcs(from: r.origin, [
            (a, a, w * 0.25, -h * 0.1), (a, a, w * 0.25, 0), (a, a, w * 0.25, 0), (a, a, w * 0.25, h * 0.1),
            (a, a, w * 0.15, h * 0.33), (a * 0.8, a * 0.8, 0, h * 0.34), (a, a, -w * 0.15, h * 0.33),
            (a, a, -w * 0.25, h * 0.15), (a, a, -w * 0.25, 0), (a, a, -w * 0.25, 0), (a, a, -w * 0.25, -h * 0.15),
            (a, a, -w * 0.1, -h * 0.33), (a * 0.8, a * 0.8, 0, -h * 0.34), (a, a, w * 0.1, -h * 0.33),
        ], sweep: false)
    }
}
