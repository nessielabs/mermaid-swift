/// Routes architecture edges orthogonally between the sides they name.
///
/// Every route leaves its source perpendicular to the declared side and
/// enters its target the same way: straight when the endpoints line up,
/// with one elbow when the sides are perpendicular (`a:T -- L:b`), and
/// with a centered jog or short stubs otherwise.
struct ArchitectureEdgeRouter {
    let diagram: ArchitectureDiagram
    let layout: ArchitectureLayout
    let iconSize: Double
    let titles: [String: TextBlock]

    /// How far a route runs straight out of a side before turning, when
    /// it cannot reach the other end directly.
    static let stub = 20.0

    func route(_ edge: ArchitectureDiagram.Edge) -> [Point] {
        let a = anchor(edge.from, side: edge.fromSide, useGroup: edge.fromGroup)
        let b = anchor(edge.to, side: edge.toSide, useGroup: edge.toGroup)
        let obstacles = diagram.nodes.filter { $0.kind == .service && $0.id != edge.from && $0.id != edge.to }
            .compactMap { layout.nodes[$0.id]?.insetBy(dx: 2, dy: 2) }
        // The direct route unless an alternative crosses fewer services.
        let candidates = [Self.connect(a, edge.fromSide, b, edge.toSide)]
            + Self.detours(a, edge.fromSide, b, edge.toSide)
        let best = candidates.enumerated().min { lhs, rhs in
            let l = Self.crossings(lhs.element, obstacles), r = Self.crossings(rhs.element, obstacles)
            return l != r ? l < r : lhs.offset < rhs.offset
        }
        return Self.simplify(best?.element ?? candidates[0])
    }

    /// Routes that leave and enter through short stubs and turn once in
    /// either order between them.
    static func detours(_ a: Point, _ sa: ArchitectureDiagram.Side, _ b: Point, _ sb: ArchitectureDiagram.Side) -> [[Point]] {
        let s1 = a + sa.outward * stub, s2 = b + sb.outward * stub
        return [[a, s1, Point(s2.x, s1.y), s2, b], [a, s1, Point(s1.x, s2.y), s2, b]]
    }

    /// How many of `frames` a polyline passes through.
    static func crossings(_ route: [Point], _ frames: [Rect]) -> Int {
        frames.filter { frame in
            let outline = EdgeGeometry.rectOutline(frame)
            return zip(route, route.dropFirst()).contains { a, b in
                frame.contains(a) || frame.contains(b) || EdgeGeometry.intersection(from: a, to: b, polygon: outline) != nil
            }
        }.count
    }

    /// Where an edge meets a node's side: the icon's edge midpoint (below
    /// the title for `B`), a junction's center, or, with `{group}`, the
    /// point on the enclosing group's border level with the node.
    func anchor(_ id: String, side: ArchitectureDiagram.Side, useGroup: Bool) -> Point {
        guard let frame = layout.nodes[id], let node = diagram.node(id) else { return .zero }
        if node.kind == .junction { return frame.center }
        let icon = Rect(x: frame.midX - iconSize / 2, y: frame.minY, width: iconSize, height: iconSize)
        if useGroup, let parent = node.parent, let group = layout.groups[parent] {
            switch side {
            case .left: return Point(group.minX, icon.midY)
            case .right: return Point(group.maxX, icon.midY)
            case .top: return Point(icon.midX, group.minY)
            case .bottom: return Point(icon.midX, group.maxY)
            }
        }
        switch side {
        case .left: return Point(icon.minX, icon.midY)
        case .right: return Point(icon.maxX, icon.midY)
        case .top: return Point(icon.midX, icon.minY)
        case .bottom: return Point(icon.midX, titles[id].map { icon.maxY + 6 + $0.height } ?? icon.maxY)
        }
    }

    /// An orthogonal path from `a` leaving through `sa` to `b` entered
    /// through `sb`.
    static func connect(_ a: Point, _ sa: ArchitectureDiagram.Side, _ b: Point, _ sb: ArchitectureDiagram.Side) -> [Point] {
        let da = sa.outward, db = sb.outward
        func ahead(_ from: Point, _ d: Point, _ to: Point) -> Double { (to.x - from.x) * d.x + (to.y - from.y) * d.y }

        if sa.isHorizontal == sb.isHorizontal {
            if da.x == -db.x, da.y == -db.y, ahead(a, da, b) > 0 {
                // Facing sides: straight, or a jog halfway across.
                if sa.isHorizontal {
                    if abs(a.y - b.y) < 0.5 { return [a, b] }
                    let x = (a.x + b.x) / 2
                    return [a, Point(x, a.y), Point(x, b.y), b]
                }
                if abs(a.x - b.x) < 0.5 { return [a, b] }
                let y = (a.y + b.y) / 2
                return [a, Point(a.x, y), Point(b.x, y), b]
            }
            if da == db {
                // Same side on both ends: loop around the outside.
                if sa.isHorizontal {
                    let x = da.x > 0 ? max(a.x, b.x) + stub : min(a.x, b.x) - stub
                    return [a, Point(x, a.y), Point(x, b.y), b]
                }
                let y = da.y > 0 ? max(a.y, b.y) + stub : min(a.y, b.y) - stub
                return [a, Point(a.x, y), Point(b.x, y), b]
            }
        } else {
            // Perpendicular sides: one elbow when both ends can reach it.
            let corner = sa.isHorizontal ? Point(b.x, a.y) : Point(a.x, b.y)
            if ahead(a, da, corner) > 0, ahead(b, db, corner) > 0 { return [a, corner, b] }
        }
        // Otherwise leave and enter through short stubs joined by an elbow.
        let s1 = a + da * stub, s2 = b + db * stub
        let corner = sb.isHorizontal ? Point(s1.x, s2.y) : Point(s2.x, s1.y)
        return [a, s1, corner, s2, b]
    }

    /// Drops repeated and collinear interior points.
    static func simplify(_ points: [Point]) -> [Point] {
        var result: [Point] = []
        for p in points {
            if let last = result.last, last.distance(to: p) < 0.5 { continue }
            if result.count >= 2 {
                let a = result[result.count - 2], b = result[result.count - 1]
                let cross = (b.x - a.x) * (p.y - b.y) - (b.y - a.y) * (p.x - b.x)
                if abs(cross) < 0.5 { result.removeLast() }
            }
            result.append(p)
        }
        return result
    }
}
