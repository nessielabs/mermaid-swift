extension FlowchartDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        FlowchartSceneBuilder(diagram: self, context: context).build()
    }
}

struct FlowchartSceneBuilder {
    let diagram: FlowchartDiagram
    let context: RenderContext
    let config: ConfigValue
    var theme: Theme { context.theme }

    init(diagram: FlowchartDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("flowchart")
    }

    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }

    /// Class definitions (with `default` first) overlaid by inline style.
    func resolvedStyle(classes: [String], inline: ElementStyle) -> ElementStyle {
        var style = diagram.classDefinitions["default"] ?? ElementStyle()
        for name in classes { if let def = diagram.classDefinitions[name] { style = style.overlaid(with: def) } }
        return style.overlaid(with: inline)
    }

    func labelBlock(_ raw: String, style: ElementStyle, maxWidth: Double) -> TextBlock {
        let font = Font(family: style.fontFamily ?? theme.fontFamily, size: style.fontSize ?? theme.fontSize,
                        bold: style.bold ?? false, italic: style.italic ?? false)
        return TextBlock(LabelParser.parse(raw), font: font, measurer: context.measurer, maxWidth: maxWidth)
    }

    func build() -> Scene {
        let padding = setting("padding", 15)
        let wrapWidth = setting("wrappingWidth", 200)
        let margin = setting("diagramPadding", 8)
        var graph = LayeredGraph()
        graph.direction = diagram.direction
        graph.nodeSpacing = setting("nodeSpacing", 50)
        graph.rankSpacing = setting("rankSpacing", 50)

        let memberOf = Dictionary(diagram.subgraphs.flatMap { sg in sg.nodes.map { ($0, sg.id) } }, uniquingKeysWith: { a, _ in a })
        var nodeStyles: [String: ElementStyle] = [:]
        var nodeLabels: [String: TextBlock] = [:]
        for node in diagram.nodes {
            let style = resolvedStyle(classes: node.classes, inline: node.style)
            let label = labelBlock(node.label, style: style, maxWidth: wrapWidth)
            nodeStyles[node.id] = style
            nodeLabels[node.id] = label
            let size = node.shape.size(forLabel: Size(label.width, label.height), padding: padding)
            graph.nodes.append(.init(id: node.id, size: size, cluster: memberOf[node.id]))
        }
        var subgraphStyles: [String: ElementStyle] = [:]
        var subgraphTitles: [String: TextBlock] = [:]
        for sg in diagram.subgraphs {
            let style = resolvedStyle(classes: sg.classes, inline: sg.style)
            let title = labelBlock(sg.title, style: style, maxWidth: wrapWidth)
            subgraphStyles[sg.id] = style
            subgraphTitles[sg.id] = title
            graph.clusters.append(.init(id: sg.id, parent: sg.parent, labelSize: Size(title.width, title.height),
                                        direction: sg.direction))
        }
        var linkLabels: [TextBlock?] = []
        for link in diagram.links {
            let label = link.label.map { labelBlock($0, style: ElementStyle(), maxWidth: wrapWidth) }
            linkLabels.append(label?.isEmpty == false ? label : nil)
            graph.edges.append(.init(from: link.from, to: link.to,
                                     labelSize: linkLabels.last!.map { Size($0.width + 4, $0.height + 2) },
                                     minLength: link.length))
        }
        let layout = LayeredLayout.compute(graph)

        var items: [SceneItem] = []
        let depth = { (id: String) -> Int in
            var d = 0, current = diagram.subgraphs.first { $0.id == id }?.parent
            while let p = current { d += 1; current = diagram.subgraphs.first { $0.id == p }?.parent }
            return d
        }
        for sg in diagram.subgraphs.sorted(by: { depth($0.id) < depth($1.id) }) {
            guard let frame = layout.clusters[sg.id], let title = subgraphTitles[sg.id] else { continue }
            let paint = ShapePaint(fill: theme.clusterBkg, stroke: theme.clusterBorder, text: theme.titleColor)
                .applying(subgraphStyles[sg.id] ?? ElementStyle())
            var group: [SceneItem] = [.shape(ShapeItem(.rect(frame), fill: paint.fill,
                                                       stroke: Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash),
                                                       opacity: paint.opacity))]
            group.append(.text(TextItem(title, centeredAt: Point(frame.midX, frame.minY + 4 + title.height / 2), color: paint.text)))
            items.append(.group(GroupItem(id: sg.id, role: "cluster", items: group)))
        }

        let nodeByID = Dictionary(diagram.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func outline(_ id: String) -> [Point]? {
            if let frame = layout.nodes[id], let node = nodeByID[id] { return node.shape.outline(in: frame) }
            return layout.clusters[id].map(EdgeGeometry.rectOutline)
        }
        let defaultCurve = diagram.defaultLinkCurve ?? config["curve"]?.stringValue.flatMap(Curve.init(name:)) ?? .basis
        for (i, link) in diagram.links.enumerated() where link.stroke != .invisible {
            let route = layout.edges[i].points
            let style = diagram.defaultLinkStyle.overlaid(with: diagram.linkStyles[i] ?? ElementStyle())
            var width = link.stroke == .thick ? 3.5 : 1.5
            if let override = style.strokeWidth { width = override }
            let connector = Connector(
                route: route, sourceOutline: outline(link.from), targetOutline: outline(link.to),
                curve: link.curve ?? diagram.linkCurves[i] ?? defaultCurve,
                color: style.stroke ?? theme.lineColor, width: width,
                dash: style.strokeDash ?? (link.stroke == .dotted ? [3, 3] : []),
                startMarker: link.startMarker, endMarker: link.endMarker,
                label: linkLabels[i], labelCenter: layout.edges[i].labelCenter,
                labelColor: style.textColor ?? theme.textColor, labelBackground: theme.edgeLabelBackground,
                background: theme.background, id: link.id ?? "L_\(link.from)_\(link.to)_\(i)")
            items += connector.items()
        }

        for node in diagram.nodes {
            guard let frame = layout.nodes[node.id] else { continue }
            let paint = ShapePaint(fill: theme.mainBkg, stroke: theme.nodeBorder, text: theme.nodeTextColor, solid: theme.lineColor)
                .applying(nodeStyles[node.id] ?? ElementStyle())
            items.append(ShapeRenderer.items(node.shape, frame: frame, label: nodeLabels[node.id], paint: paint, id: node.id))
        }

        return DiagramCanvas(context: context, margin: margin).scene(content: items, size: layout.size)
    }
}
