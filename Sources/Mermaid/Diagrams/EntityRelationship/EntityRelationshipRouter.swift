/// Turns layout routes into relationship lines that suit crow's foot
/// notation: every end meets its entity head-on, ends sharing a side of
/// an entity are spread far enough apart that their symbols never touch,
/// and self-relationships loop out beside the entity.
struct EntityRelationshipRouter {
    /// Room between neighboring ends on one side: two symbol spreads plus
    /// a gap.
    static let endSpacing = 2 * CrowsFoot.spread + 26
    /// How far a self-relationship loops out from its entity.
    static let loopReach = 44.0
    /// The widest a loop's curve can bulge beyond `loopReach`.
    static let loopBulge = 39.0
    /// How far a loop, before its label, extends from its entity.
    static var loopExtent: Double { loopReach + loopBulge * 0.75 + 2 }

    let direction: LayeredGraph.Direction

    /// One routed relationship: a polyline to smooth, or a finished path
    /// for a self-loop.
    struct Line {
        var points: [Point]
        var path: Path?
        var labelCenter: Point?
    }

    /// Routes relationship `i` from `routes[i]` between `frames[i]`,
    /// keeping `reaches[i]` (the symbol lengths at each end) straight.
    func lines(routes: [LayeredLayout.Route], frames: [(source: Rect, target: Rect)],
               reaches: [(from: Double, to: Double)], labelSizes: [Size?]) -> [Line] {
        var points = routes.indices.map { i -> [Point] in
            guard frames[i].source != frames[i].target else { return [] }
            return Connector.removingNearDuplicates(EdgeGeometry.clip(
                routes[i].points, source: EdgeGeometry.rectOutline(frames[i].source),
                target: EdgeGeometry.rectOutline(frames[i].target)))
        }
        spreadEnds(&points, frames: frames)
        return routes.indices.map { i in
            let (source, target) = frames[i]
            if source == target { return loop(around: source, labelSize: labelSizes[i]) }
            guard points[i].count >= 2 else { return Line(points: [], labelCenter: nil) }
            let anchor = routes[i].labelCenter
            var line = EdgeGeometry.squaringEnd(points[i], at: target, length: reaches[i].to + 10, keeping: anchor)
            line = EdgeGeometry.squaringEnd(line.reversed(), at: source, length: reaches[i].from + 10,
                                            keeping: anchor).reversed()
            return Line(points: line, labelCenter: anchor)
        }
    }

    /// Redistributes ends that share a side of the same box evenly around
    /// the side's center, keeping their order.
    private func spreadEnds(_ points: inout [[Point]], frames: [(source: Rect, target: Rect)]) {
        struct Side: Hashable { var frame: Rect; var normal: Point }
        var groups: [Side: [(edge: Int, atEnd: Bool)]] = [:]
        for (i, line) in points.enumerated() where line.count >= 2 {
            for atEnd in [false, true] {
                let frame = atEnd ? frames[i].target : frames[i].source
                let tip = atEnd ? line[line.count - 1] : line[0]
                groups[Side(frame: frame, normal: EdgeGeometry.outwardNormal(of: frame, at: tip)), default: []]
                    .append((i, atEnd))
            }
        }
        for (side, ends) in groups where ends.count > 1 {
            let horizontal = side.normal.y != 0
            func coordinate(_ end: (edge: Int, atEnd: Bool)) -> Double {
                let line = points[end.edge]
                let tip = end.atEnd ? line[line.count - 1] : line[0]
                return horizontal ? tip.x : tip.y
            }
            let sorted = ends.sorted { coordinate($0) < coordinate($1) }
            let length = horizontal ? side.frame.width : side.frame.height
            let step = min(Self.endSpacing, (length - 2 * CrowsFoot.spread) / Double(sorted.count - 1))
            let center = horizontal ? side.frame.midX : side.frame.midY
            for (k, end) in sorted.enumerated() {
                let offset = center + (Double(k) - Double(sorted.count - 1) / 2) * step
                let index = end.atEnd ? points[end.edge].count - 1 : 0
                if horizontal { points[end.edge][index].x = offset } else { points[end.edge][index].y = offset }
            }
        }
    }

    /// A loop leaving and re-entering the side the layout reserved room
    /// on (the right in vertical layouts, the bottom in horizontal ones),
    /// with straight ends for the symbols and the label beside it.
    private func loop(around frame: Rect, labelSize: Size?) -> Line {
        let horizontal = direction.isHorizontal
        // `out` points away from the box; `across` runs along its side.
        let out = horizontal ? Point(0, 1) : Point(1, 0)
        let across = horizontal ? Point(1, 0) : Point(0, 1)
        let base = horizontal ? Point(frame.midX, frame.maxY) : Point(frame.maxX, frame.midY)
        let half = min((horizontal ? frame.width : frame.height) * 0.3, 30)
        let start = base - across * half, end = base + across * half
        let reach = Self.loopReach, bulge = min(half * 1.3, Self.loopBulge)
        var path = Path()
        path.move(to: start)
        path.line(to: start + out * reach)
        path.curve(to: end + out * reach, control1: start + out * (reach + bulge), control2: end + out * (reach + bulge))
        path.line(to: end)
        let labelCenter = labelSize.map { size -> Point in
            horizontal
                ? Point(base.x, base.y + reach + bulge * 0.75 + size.height / 2 + 2)
                : Point(base.x + reach + bulge * 0.75 + size.width / 2 + 2, base.y)
        }
        return Line(points: [start, start + out * reach, end + out * reach, end], path: path, labelCenter: labelCenter)
    }
}
