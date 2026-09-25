extension EntityRelationshipSceneBuilder {
    func build() -> Scene {
        var graph = LayeredGraph()
        graph.direction = diagram.direction
        graph.nodeSpacing = setting("nodeSpacing", 140)
        graph.rankSpacing = setting("rankSpacing", 80)

        let memberOf = Dictionary(diagram.subgraphs.flatMap { sg in sg.entities.map { ($0, sg.id) } },
                                  uniquingKeysWith: { first, _ in first })
        let labels: [TextBlock?] = diagram.relationships.map { relationship in
            guard !relationship.label.isEmpty else { return nil }
            return context.label(relationship.label, size: theme.fontSize * 0.875)
        }
        let labelSizes = labels.map { $0.map { Size($0.width + 8, $0.height + 4) } }
        // Self-relationships loop beside their entity; widen its slot so the
        // loop and its label clear the neighbors.
        var loopRoom: [String: Double] = [:]
        for (relationship, labelSize) in zip(diagram.relationships, labelSizes) where relationship.from == relationship.to {
            let along = diagram.direction.isHorizontal ? labelSize?.height : labelSize?.width
            loopRoom[relationship.from] = max(loopRoom[relationship.from] ?? 0,
                                              EntityRelationshipRouter.loopExtent + (along ?? 0) + 8)
        }
        var boxes: [String: EntityBox] = [:]
        var styles: [String: ElementStyle] = [:]
        for entity in diagram.entities {
            let style = resolvedStyle(classes: entity.classes, inline: entity.style)
            let box = entityBox(entity, style: style)
            boxes[entity.name] = box
            styles[entity.name] = style
            var size = box.size
            if let loopRoom = loopRoom[entity.name] {
                if diagram.direction.isHorizontal { size.height += 2 * loopRoom } else { size.width += 2 * loopRoom }
            }
            graph.nodes.append(.init(id: entity.name, size: size, cluster: memberOf[entity.name]))
        }
        var titles: [String: TextBlock] = [:]
        for sg in diagram.subgraphs {
            let title = context.label(sg.title)
            titles[sg.id] = title
            graph.clusters.append(.init(id: sg.id, parent: sg.parent, labelSize: Size(title.width, title.height),
                                        direction: sg.direction))
        }
        for (relationship, labelSize) in zip(diagram.relationships, labelSizes) {
            // Loops are drawn beside the entity, so the layout needs no slot.
            let isLoop = relationship.from == relationship.to
            graph.edges.append(.init(from: relationship.from, to: relationship.to,
                                     labelSize: isLoop ? nil : labelSize))
        }
        let layout = LayeredLayout.compute(graph)
        func frame(_ id: String) -> Rect? {
            if let box = boxes[id], let slot = layout.nodes[id] { return Rect(center: slot.center, size: box.size) }
            return layout.clusters[id]
        }

        var items = clusterItems(layout, titles: titles)
        let drawn = diagram.relationships.indices.filter {
            frame(diagram.relationships[$0].from) != nil && frame(diagram.relationships[$0].to) != nil
        }
        let router = EntityRelationshipRouter(direction: diagram.direction)
        let lines = router.lines(
            routes: drawn.map { layout.edges[$0] },
            frames: drawn.map { (frame(diagram.relationships[$0].from)!, frame(diagram.relationships[$0].to)!) },
            reaches: drawn.map { (CrowsFoot(diagram.relationships[$0].fromCardinality).reach,
                                  CrowsFoot(diagram.relationships[$0].toCardinality).reach) },
            labelSizes: drawn.map { labelSizes[$0] })
        for (line, i) in zip(lines, drawn) {
            items += relationshipItems(diagram.relationships[i], index: i, line: line, label: labels[i])
        }
        let (odd, even) = rowFills
        for entity in diagram.entities {
            guard let frame = frame(entity.name), let box = boxes[entity.name] else { continue }
            let style = styles[entity.name] ?? ElementStyle()
            let paint = EntityBox.Paint(
                header: style.fill ?? theme.mainBkg, oddRow: odd, evenRow: style.fill ?? even,
                stroke: style.stroke ?? theme.nodeBorder, strokeWidth: style.strokeWidth ?? 1,
                dash: style.strokeDash ?? [], text: style.textColor ?? theme.nodeTextColor,
                opacity: style.opacity ?? 1)
            items.append(box.items(in: frame, paint: paint, id: "entity-\(entity.name)"))
        }
        return DiagramCanvas(context: context, margin: 8).scene(content: items, size: layout.size)
    }

    /// Subgraph boxes, outermost first so inner ones draw on top.
    func clusterItems(_ layout: LayeredLayout, titles: [String: TextBlock]) -> [SceneItem] {
        func depth(_ id: String) -> Int {
            var d = 0, current = diagram.subgraphs.first { $0.id == id }?.parent
            while let parent = current, d < diagram.subgraphs.count {
                d += 1
                current = diagram.subgraphs.first { $0.id == parent }?.parent
            }
            return d
        }
        return diagram.subgraphs.sorted { depth($0.id) < depth($1.id) }.compactMap { sg in
            guard let frame = layout.clusters[sg.id], let title = titles[sg.id] else { return nil }
            let style = resolvedStyle(classes: sg.classes, inline: sg.style)
            let paint = ShapePaint(fill: theme.clusterBkg, stroke: theme.clusterBorder, text: theme.titleColor)
                .applying(style)
            let box = SceneItem.shape(ShapeItem(.rect(frame), fill: paint.fill,
                                                stroke: Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash),
                                                opacity: paint.opacity))
            let text = SceneItem.text(TextItem(title, centeredAt: Point(frame.midX, frame.minY + 4 + title.height / 2),
                                               color: paint.text))
            return .group(GroupItem(id: sg.id, role: "cluster", items: [box, text]))
        }
    }

    /// A relationship line (dashed when non-identifying) with its label and
    /// the crow's foot notation for the cardinality at each end.
    func relationshipItems(_ relationship: EntityRelationshipDiagram.Relationship, index: Int,
                           line: EntityRelationshipRouter.Line, label: TextBlock?) -> [SceneItem] {
        let points = line.points
        guard points.count >= 2 else { return [] }
        let dash: [Double] = relationship.identifying ? [] : [8, 8]
        var items: [SceneItem]
        if let path = line.path {
            items = [.shape(ShapeItem(path, stroke: Stroke(theme.lineColor, width: 1, dash: dash, join: .round)))]
            if let label, let center = line.labelCenter {
                items.append(.shape(ShapeItem(.rect(Rect(center: center, size: Size(label.width + 4, label.height + 2))),
                                              fill: theme.edgeLabelBackground)))
                items.append(.text(TextItem(label, centeredAt: center, color: theme.textColor)))
            }
        } else {
            items = Connector(
                route: points, curve: config["curve"]?.stringValue.flatMap(Curve.init(name:)) ?? .basis,
                color: theme.lineColor, width: 1, dash: dash, label: label, labelCenter: line.labelCenter,
                labelColor: theme.textColor, labelBackground: theme.edgeLabelBackground,
                background: theme.background).items()
        }
        let n = points.count
        items += CrowsFoot(relationship.toCardinality).items(
            tip: points[n - 1], direction: points[n - 1] - points[n - 2], color: theme.lineColor,
            background: theme.background)
        items += CrowsFoot(relationship.fromCardinality).items(
            tip: points[0], direction: points[0] - points[1], color: theme.lineColor, background: theme.background)
        let id = "rel-\(relationship.from)-\(relationship.to)-\(index)"
        return [.group(GroupItem(id: id, role: "relationship", items: items))]
    }
}

extension CrowsFoot {
    init(_ cardinality: EntityRelationshipDiagram.Cardinality) {
        switch cardinality {
        case .zeroOrOne: self = .zeroOrOne
        case .exactlyOne: self = .exactlyOne
        case .zeroOrMore: self = .zeroOrMore
        case .oneOrMore: self = .oneOrMore
        case .mdParent: self = .parent
        }
    }
}
