extension ClassSceneBuilder {
    /// Relation connectors with markers, labels and cardinalities, then the
    /// dotted connectors from notes to their classes.
    func relationItems(_ layout: LayeredLayout, _ measured: Measured) -> [SceneItem] {
        let curve = config["curve"]?.stringValue.flatMap(Curve.init(name:)) ?? .basis
        var items: [SceneItem] = []
        for (i, relation) in diagram.relations.enumerated() {
            let route = layout.edges[i]
            let source = outline(relation.from, layout), target = outline(relation.to, layout)
            let connector = Connector(
                route: route.points, sourceOutline: source, targetOutline: target, curve: curve,
                color: theme.lineColor, width: 1, dash: relation.line == .dashed ? [3, 3] : [],
                startMarker: Self.marker(relation.fromEnd), endMarker: Self.marker(relation.toEnd),
                label: measured.relationLabels[i], labelCenter: route.labelCenter,
                labelColor: theme.textColor, labelBackground: theme.edgeLabelBackground,
                background: theme.background, id: "id_\(relation.from)_\(relation.to)_\(i + 1)")
            var group = connector.items()
            let clipped = Connector.removingNearDuplicates(EdgeGeometry.clip(route.points, source: source, target: target))
            group += decorations(relation, clipped: clipped, drawn: Self.densified(curve.path(through: clipped).flattened()),
                                 frames: (layout.nodes[relation.from], layout.nodes[relation.to]),
                                 cardinalities: measured.cardinalities[i])
            items += group
        }
        for (k, (note, target)) in attachedNotes.enumerated() {
            let route = layout.edges[diagram.relations.count + k]
            let connector = Connector(
                route: route.points, sourceOutline: outline(note.id, layout), targetOutline: outline(target, layout),
                curve: curve, color: theme.lineColor, width: 1, dash: [2, 3],
                labelColor: theme.textColor, background: theme.background, id: "edgeNote\(k)")
            items += connector.items()
        }
        return items
    }

    /// Lollipop circles on class-to-class ends and the cardinality labels.
    /// `points` is the route clipped to its endpoints, `drawn` the stroke
    /// as flattened points, and `frames` the endpoint boxes.
    func decorations(_ relation: ClassDiagram.Relation, clipped points: [Point], drawn: [Point],
                     frames: (from: Rect?, to: Rect?),
                     cardinalities: (from: TextBlock?, to: TextBlock?)) -> [SceneItem] {
        guard points.count >= 2 else { return [] }
        var items: [SceneItem] = []
        let ends: [(end: ClassDiagram.RelationEnd, text: TextBlock?, atStart: Bool, isInterface: Bool, frame: Rect?)] = [
            (relation.fromEnd, cardinalities.from, true, isInterface(relation.from), frames.from),
            (relation.toEnd, cardinalities.to, false, isInterface(relation.to), frames.to),
        ]
        for end in ends {
            let tip = end.atStart ? points[0] : points[points.count - 1]
            let inward = ((end.atStart ? points[1] : points[points.count - 2]) - tip).normalized
            if end.end == .lollipop, !end.isInterface {
                let r = Self.lollipopDiameter / 2
                items.append(.shape(ShapeItem(.circle(center: tip + inward * r, radius: r), fill: theme.background,
                                              stroke: Stroke(theme.lineColor, width: 1))))
            }
            guard let block = end.text else { continue }
            let frame = Self.terminalLabelFrame(
                tip: tip, inward: inward, travel: end.atStart ? inward : inward * -1,
                size: Size(block.width, block.height), clearance: Self.decorationLength(end.end) + 3,
                avoiding: end.frame, stroke: drawn)
            items.append(.text(TextItem(block, centeredAt: frame.center, color: theme.textColor)))
        }
        return items
    }

    /// Samples a polyline every couple of points, so containment tests see
    /// long straight segments too.
    static func densified(_ points: [Point], step: Double = 2) -> [Point] {
        guard let first = points.first else { return [] }
        var result = [first]
        for (a, b) in zip(points, points.dropFirst()) {
            let count = max(1, Int((a.distance(to: b) / step).rounded(.up)))
            result += (1...count).map { a.interpolated(to: b, Double($0) / Double(count)) }
        }
        return result
    }

    func isInterface(_ id: String) -> Bool { diagram.interfaces.contains { $0.id == id } }

    /// Where a cardinality label goes: just past the end decoration along
    /// the edge and beside the line. The right of the direction of travel
    /// is preferred, so both labels of a straight edge share a side, but a
    /// placement that overlaps the endpoint's box or the stroke itself (as
    /// on a curving or slanted edge) loses to the other side or to one
    /// further along the edge.
    static func terminalLabelFrame(tip: Point, inward: Point, travel: Point, size: Size, clearance: Double,
                                   avoiding node: Rect?, stroke: [Point]) -> Rect {
        func extent(_ v: Point) -> Double { abs(v.x) * size.width / 2 + abs(v.y) * size.height / 2 }
        let preferred = Point(travel.y, -travel.x)
        var best: (penalty: Double, frame: Rect)?
        for along in [0.0, 8, 16, 24] {
            for side in [preferred, preferred * -1] {
                let center = tip + inward * (clearance + along + extent(inward)) + side * (extent(side) + 4)
                let frame = Rect(center: center, size: size)
                let padded = frame.insetBy(dx: -2, dy: -2)
                var penalty = along / 100
                if let node, node.intersects(frame) { penalty += 4 }
                if stroke.contains(where: padded.contains) { penalty += 2 }
                if best.map({ penalty < $0.penalty }) ?? true { best = (penalty, frame) }
            }
        }
        return best?.frame ?? Rect(center: tip, size: size)
    }
}
