extension TimelineDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        let layout = TimelineLayout.compute(self, context: context)
        let theme = context.theme
        var items: [SceneItem] = []
        let lineColor = theme.textColor

        // Connectors sit beneath the nodes so dashed lines never cross
        // event text (mermaid.js draws them on top).
        for arrow in layout.arrows.sorted(by: { !$0.dashed && $1.dashed }) {
            items += Self.arrowItems(arrow, color: lineColor)
        }
        for (i, node) in layout.nodes.enumerated() {
            var fill = theme.scaleColor(node.colorIndex)
            if node.kind == .event { fill = Self.brightened(fill, by: 1.2) }
            let frame = node.frame
            var group: [SceneItem] = [
                .shape(ShapeItem(Self.nodePath(frame), fill: fill)),
                .shape(ShapeItem(.polyline([Point(frame.minX, frame.maxY), Point(frame.maxX, frame.maxY)]),
                                 stroke: Stroke(theme.scaleInverseColor(node.colorIndex), width: 3))),
            ]
            let textTop = frame.minY + max((frame.height - node.text.height) / 2, 0)
            group.append(.text(TextItem(node.text, frame: Rect(x: frame.minX, y: textTop, width: frame.width,
                                                              height: node.text.height),
                                        color: theme.scaleLabelColor(node.colorIndex))))
            let role: String
            switch node.kind {
            case .section: role = "section"
            case .period: role = "period"
            case .event: role = "event"
            }
            items.append(.group(GroupItem(id: "\(role)-\(i)", role: role, items: group)))
        }

        var bounds = layout.bounds
        if let title = title ?? context.title, !title.isEmpty {
            let block = context.label(title, size: 2 * theme.fontSize, bold: true)
            let top = bounds.minY - block.height - 16
            items.append(.text(TextItem(block, frame: Rect(x: bounds.midX - block.width / 2, y: top,
                                                           width: block.width, height: block.height),
                                        color: theme.titleColor)))
            bounds = bounds.union(Rect(x: bounds.midX - block.width / 2, y: top, width: block.width, height: block.height))
        }
        let content = items.map { $0.offsetBy(dx: -bounds.minX, dy: -bounds.minY) }
        var plain = context
        plain.title = nil
        return DiagramCanvas(context: plain, margin: 20).scene(content: content, size: bounds.size)
    }

    /// A box with rounded top corners and a square bottom, like mermaid's
    /// timeline nodes.
    static func nodePath(_ r: Rect) -> Path {
        let radius = min(5, r.height / 2, r.width / 2)
        var path = Path()
        path.move(to: Point(r.minX, r.maxY))
        path.line(to: Point(r.minX, r.minY + radius))
        path.appendArc(center: Point(r.minX + radius, r.minY + radius), radius: radius, from: 180, to: 270, connect: true)
        path.line(to: Point(r.maxX - radius, r.minY))
        path.appendArc(center: Point(r.maxX - radius, r.minY + radius), radius: radius, from: 270, to: 360, connect: true)
        path.line(to: Point(r.maxX, r.maxY))
        path.close()
        return path
    }

    /// CSS `filter: brightness(k)`, which mermaid applies to event boxes.
    static func brightened(_ color: Color, by k: Double) -> Color {
        Color(red: color.red * k, green: color.green * k, blue: color.blue * k, alpha: color.alpha)
    }

    /// A line with mermaid's timeline arrowhead: a 6×4 triangle scaled by
    /// the stroke width, its tip one stroke width past the line's end.
    static func arrowItems(_ arrow: TimelineLayout.Arrow, color: Color) -> [SceneItem] {
        let direction = (arrow.to - arrow.from).normalized
        let normal = Point(-direction.y, direction.x)
        let w = arrow.width
        let tip = arrow.to + direction * w
        let base = tip - direction * (6 * w)
        let line = Path.polyline([arrow.from, base + direction * w])
        let head = Path.polygon([tip, base + normal * (2 * w), base - normal * (2 * w)])
        return [
            .shape(ShapeItem(line, stroke: Stroke(color, width: w, dash: arrow.dashed ? [5, 5] : []))),
            .shape(ShapeItem(head, fill: color)),
        ]
    }
}
