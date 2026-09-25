extension RequirementSceneBuilder {
    func build() -> Scene {
        let nodes = nodes()
        var graph = LayeredGraph()
        graph.direction = diagram.direction
        graph.nodeSpacing = setting("nodeSpacing", 50)
        graph.rankSpacing = setting("rankSpacing", 50)
        graph.nodes = nodes.map { .init(id: $0.name, size: $0.box.size) }
        let labelFont = context.font()
        let labels = diagram.relationships.map { relationship in
            TextBlock(RichText(plain: "<<\(relationship.type.rawValue)>>"), font: labelFont, measurer: context.measurer)
        }
        graph.edges = zip(diagram.relationships, labels).map { relationship, label in
            .init(from: relationship.source, to: relationship.target, labelSize: Size(label.width + 8, label.height + 4))
        }
        let layout = LayeredLayout.compute(graph)

        let lineColor = theme.color("relationColor", default: theme.lineColor)
        var items: [SceneItem] = []
        for (i, relationship) in diagram.relationships.enumerated() {
            guard let source = layout.nodes[relationship.source], let target = layout.nodes[relationship.target] else { continue }
            let contains = relationship.type == .contains
            // Square both ends so markers meet their boxes head-on.
            let anchor = layout.edges[i].labelCenter
            var points = Connector.removingNearDuplicates(EdgeGeometry.clip(
                layout.edges[i].points, source: EdgeGeometry.rectOutline(source), target: EdgeGeometry.rectOutline(target)))
            guard points.count >= 2 else { continue }
            points = EdgeGeometry.squaringEnd(points, at: target, length: Self.markerLength + 8, keeping: anchor)
            points = EdgeGeometry.squaringEnd(points.reversed(), at: source, length: Self.markerLength + 8,
                                              keeping: anchor).reversed()
            let connector = Connector(
                route: points, curve: config["curve"]?.stringValue.flatMap(Curve.init(name:)) ?? .basis,
                color: lineColor, width: 1, dash: contains ? [] : [10, 7], label: labels[i], labelCenter: anchor,
                labelColor: theme.color("relationLabelColor", default: theme.textColor),
                labelBackground: theme.color("relationLabelBackground", default: theme.edgeLabelBackground),
                background: theme.background)
            let n = points.count
            let edge = connector.items() + (contains
                ? Self.containsMarker(tip: points[0], direction: points[0] - points[1], color: lineColor,
                                      background: theme.background)
                : Self.arrowMarker(tip: points[n - 1], direction: points[n - 1] - points[n - 2], color: lineColor))
            let id = "\(relationship.source)-\(relationship.target)-\(i)"
            items.append(.group(GroupItem(id: id, role: "relationship", items: edge)))
        }
        let fill = theme.color("requirementBackground", default: theme.primaryColor)
        let stroke = theme.color("requirementBorderColor", default: theme.primaryBorderColor)
        let borderSize = context.config["themeVariables"]?["requirementBorderSize"].flatMap {
            $0.numberValue ?? $0.stringValue.flatMap(ElementStyle.length)
        } ?? 1
        let text = theme.color("requirementTextColor", default: theme.primaryTextColor)
        for node in nodes {
            guard let frame = layout.nodes[node.name] else { continue }
            let paint = RequirementBox.Paint(
                fill: node.style.fill ?? fill, stroke: node.style.stroke ?? stroke,
                strokeWidth: node.style.strokeWidth ?? borderSize, dash: node.style.strokeDash ?? [],
                text: node.style.textColor ?? text, opacity: node.style.opacity ?? 1)
            items.append(node.box.items(in: frame, paint: paint, id: node.name, role: node.role))
        }
        return DiagramCanvas(context: context, margin: 8).scene(content: items, size: layout.size)
    }

    /// How far markers reach back from their box.
    static let markerLength = 16.0

    /// The `contains` marker at the container's end: a ring with a cross.
    static func containsMarker(tip: Point, direction: Point, color: Color, background: Color) -> [SceneItem] {
        let d = direction.normalized, n = Point(-d.y, d.x)
        let radius = 8.0
        let center = tip - d * radius
        var cross = Path.polyline([center - d * radius, center + d * radius])
        cross.append(.polyline([center - n * radius, center + n * radius]))
        return [.shape(ShapeItem(.circle(center: center, radius: radius), fill: background, stroke: Stroke(color))),
                .shape(ShapeItem(cross, stroke: Stroke(color)))]
    }

    /// The open arrowhead at the target of every other relationship.
    static func arrowMarker(tip: Point, direction: Point, color: Color) -> [SceneItem] {
        let d = direction.normalized, n = Point(-d.y, d.x)
        let length = markerLength - 2, half = 7.0
        let path = Path.polyline([tip - d * length + n * half, tip, tip - d * length - n * half])
        return [.shape(ShapeItem(path, stroke: Stroke(color, width: 1, cap: .round, join: .miter)))]
    }
}
