extension ArchitectureDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        ArchitectureSceneBuilder(diagram: self, context: context).build()
    }
}

struct ArchitectureSceneBuilder {
    let diagram: ArchitectureDiagram
    let context: RenderContext
    let iconSize: Double
    let padding: Double
    let fontSize: Double
    let edgeColor: Color
    let arrowColor: Color
    let edgeWidth: Double
    let groupBorder: Color
    let groupBorderWidth: Double
    var theme: Theme { context.theme }

    init(diagram: ArchitectureDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        let config = context.section("architecture")
        iconSize = config["iconSize"]?.numberValue ?? 80
        padding = config["padding"]?.numberValue ?? 40
        fontSize = config["fontSize"]?.numberValue ?? 16
        let dark = context.theme.background.isDark
        // mermaid.js's defaults: #777 edges 3px wide, #000 dashed groups 2px wide.
        edgeColor = context.theme.color("archEdgeColor", default: dark ? context.theme.lineColor : Color(hex: 0x777777))
        arrowColor = context.theme.color("archEdgeArrowColor", default: edgeColor)
        edgeWidth = Self.length(context.config, "archEdgeWidth") ?? 3
        groupBorder = context.theme.color("archGroupBorderColor", default: dark ? context.theme.textColor : .black)
        groupBorderWidth = Self.length(context.config, "archGroupBorderWidth") ?? 2
    }

    /// Widths are theme variables too, but `Theme` only models colors, so
    /// they are read from the raw `themeVariables` configuration.
    static func length(_ config: ConfigValue, _ name: String) -> Double? {
        config["themeVariables"]?[name]?.numberValue
    }

    func font(bold: Bool = false) -> Font { Font(family: theme.fontFamily, size: fontSize, bold: bold) }

    func text(_ raw: String, maxWidth: Double? = nil) -> TextBlock {
        TextBlock(LabelParser.parse(raw), font: font(), measurer: context.measurer, maxWidth: maxWidth, forceWrap: maxWidth != nil)
    }

    func build() -> Scene {
        var titles: [String: TextBlock] = [:]
        var sizes: [String: Size] = [:], anchors: [String: Point] = [:]
        for node in diagram.nodes {
            if node.kind == .junction {
                sizes[node.id] = Size(12, 12)
                continue
            }
            let title = node.title.map { text($0, maxWidth: iconSize * 1.5) }
            titles[node.id] = title
            sizes[node.id] = Size(max(iconSize, title?.width ?? 0), iconSize + (title.map { $0.height + 6 } ?? 0))
            anchors[node.id] = Point((sizes[node.id]?.width ?? 0) / 2, iconSize / 2)
        }
        var headers: [String: GroupHeader] = [:]
        for group in diagram.groups {
            headers[group.id] = GroupHeader(group, iconSize: padding * 0.75, block: group.title.map { text($0) })
        }
        var labels: [Int: TextBlock] = [:]
        for (i, edge) in diagram.edges.enumerated() {
            if let label = edge.label, !label.isEmpty { labels[i] = text(label, maxWidth: 200) }
        }
        let layout = ArchitectureLayout.compute(diagram, ArchitectureLayout.Input(
            nodeSizes: sizes, nodeAnchors: anchors, groupHeaders: headers.mapValues(\.size),
            edgeLabels: labels.mapValues { Size($0.width, $0.height) },
            gap: max(iconSize * 0.75, 40), groupPadding: padding * 0.75))

        var items: [SceneItem] = []
        var labelItems: [SceneItem] = []
        for group in diagram.groups.sorted(by: { depth($0.id) < depth($1.id) }) {
            guard let frame = layout.groups[group.id], let header = headers[group.id] else { continue }
            items.append(.group(GroupItem(id: group.id, role: "architecture-group", items: [
                .shape(ShapeItem(.rect(frame), stroke: Stroke(groupBorder, width: groupBorderWidth, dash: [8, 8]))),
            ])))
            // Titles go on top of edges, which may cross the title band.
            labelItems.append(header.items(in: frame, text: theme.textColor, background: theme.background))
        }
        let router = ArchitectureEdgeRouter(diagram: diagram, layout: layout, iconSize: iconSize, titles: titles)
        for (i, edge) in diagram.edges.enumerated() {
            let route = router.route(edge)
            let connector = Connector(route: route, sourceOutline: nil, targetOutline: nil, curve: .linear,
                                      color: edgeColor, width: edgeWidth,
                                      startMarker: edge.arrowAtSource ? .arrow : .none,
                                      endMarker: edge.arrowAtTarget ? .arrow : .none,
                                      labelColor: theme.textColor, background: theme.background,
                                      id: "L_\(edge.from)_\(edge.to)_\(i)")
            items += connector.items().map { $0.recoloringMarkers(from: edgeColor, to: arrowColor) }
            if let label = labels[i] { labelItems.append(labelItem(label, on: route, id: "label_\(i)")) }
        }
        for node in diagram.nodes where node.kind == .service {
            guard let frame = layout.nodes[node.id] else { continue }
            items.append(serviceItems(node, frame: frame, title: titles[node.id]))
        }
        items += labelItems
        let bounds = items.compactMap(\.inkBounds).reduce(Rect(x: 0, y: 0, width: layout.size.width, height: layout.size.height)) { $0.union($1) }
        let content = items.map { $0.offsetBy(dx: -bounds.minX, dy: -bounds.minY) }
        return DiagramCanvas(context: context, margin: 16, title: diagram.title).scene(content: content, size: bounds.size)
    }

    func depth(_ group: String) -> Int {
        var d = 0, current = diagram.group(group)?.parent
        while let parent = current { d += 1; current = diagram.group(parent)?.parent }
        return d
    }

    // MARK: - Services

    func serviceItems(_ node: ArchitectureDiagram.Node, frame: Rect, title: TextBlock?) -> SceneItem {
        let icon = Rect(x: frame.midX - iconSize / 2, y: frame.minY, width: iconSize, height: iconSize)
        var items: [SceneItem]
        if let name = node.icon {
            items = ArchitectureIcons.items(name, in: icon)
        } else if let iconText = node.iconText {
            items = ArchitectureIcons.items("blank", in: icon)
            var small = font()
            small.size = fontSize * 0.8
            let block = TextBlock(LabelParser.parse(iconText), font: small, measurer: context.measurer,
                                  maxWidth: iconSize - 6, forceWrap: true)
            let lineHeight = block.height / Double(max(block.lines.count, 1))
            var clipped = block
            // Like mermaid's line clamp, keep only the lines that fit.
            let fitting = max(1, Int((iconSize - 2) / max(lineHeight, 1)))
            if clipped.lines.count > fitting {
                clipped.lines = Array(clipped.lines.prefix(fitting))
                clipped.height = lineHeight * Double(fitting)
            }
            items.append(.text(TextItem(clipped, centeredAt: icon.center, color: .white)))
        } else {
            var outline = Path()
            outline.move(to: Point(icon.minX, icon.maxY))
            outline.line(to: Point(icon.minX, icon.minY + 5))
            outline.curve(to: Point(icon.minX + 5, icon.minY), control1: Point(icon.minX, icon.minY + 2), control2: Point(icon.minX + 2, icon.minY))
            outline.line(to: Point(icon.maxX - 5, icon.minY))
            outline.curve(to: Point(icon.maxX, icon.minY + 5), control1: Point(icon.maxX - 2, icon.minY), control2: Point(icon.maxX, icon.minY + 2))
            outline.line(to: Point(icon.maxX, icon.maxY))
            outline.close()
            items = [.shape(ShapeItem(outline, stroke: Stroke(groupBorder, width: groupBorderWidth, dash: [8, 8])))]
        }
        if let title {
            items.append(.text(TextItem(title, frame: Rect(x: frame.minX, y: icon.maxY + 4, width: frame.width, height: title.height),
                                        alignment: .center, color: theme.textColor)))
        }
        return .group(GroupItem(id: node.id, role: "architecture-service", items: items))
    }

    // MARK: - Edge labels

    /// Places a label on the route's longest segment, turned to run along
    /// vertical segments as mermaid.js does.
    func labelItem(_ label: TextBlock, on route: [Point], id: String) -> SceneItem {
        var best = (route.first ?? .zero, route.last ?? .zero)
        for (a, b) in zip(route, route.dropFirst()) where a.distance(to: b) > best.0.distance(to: best.1) { best = (a, b) }
        let center = best.0.interpolated(to: best.1, 0.5)
        let vertical = abs(best.0.x - best.1.x) < 0.5 && abs(best.0.y - best.1.y) > 0.5
        let plateSize = vertical ? Size(label.height + 4, label.width + 8) : Size(label.width + 8, label.height + 4)
        return .group(GroupItem(id: id, role: "architecture-edge-label", items: [
            .shape(ShapeItem(.rect(Rect(center: center, size: plateSize), cornerRadius: 3), fill: theme.background)),
            .text(TextItem(label, centeredAt: center, color: theme.textColor, rotation: vertical ? -90 : 0)),
        ]))
    }
}

/// A group's title band: its icon and title at the top left.
struct GroupHeader {
    var icon: String?
    var iconSize: Double
    var block: TextBlock?

    init(_ group: ArchitectureDiagram.Group, iconSize: Double, block: TextBlock?) {
        icon = group.icon
        self.iconSize = iconSize
        self.block = block
    }

    var size: Size {
        let iconWidth = icon == nil ? 0 : iconSize + (block == nil ? 0 : 8)
        let height = max(icon == nil ? 0 : iconSize, block?.height ?? 0)
        return Size(iconWidth + (block?.width ?? 0), height)
    }

    /// The icon and title, on a plate so crossing edges pass beneath them.
    func items(in frame: Rect, text: Color, background: Color) -> SceneItem {
        let top = frame.minY + 12
        var x = frame.minX + 12
        var items: [SceneItem] = [.shape(ShapeItem(.rect(Rect(x: x - 3, y: top - 2, width: size.width + 6, height: size.height + 4),
                                                         cornerRadius: 3), fill: background))]
        if let icon {
            items += ArchitectureIcons.items(icon, in: Rect(x: x, y: top + (size.height - iconSize) / 2, width: iconSize, height: iconSize))
            x += iconSize + 8
        }
        if let block {
            items.append(.text(TextItem(block, frame: Rect(x: x, y: top, width: block.width, height: size.height),
                                        alignment: .leading, color: text)))
        }
        return .group(GroupItem(role: "architecture-group-title", items: items))
    }
}

private extension SceneItem {
    /// Recolors filled marker shapes (the only filled shapes in a connector).
    func recoloringMarkers(from old: Color, to new: Color) -> SceneItem {
        guard old != new else { return self }
        switch self {
        case .shape(var shape) where shape.fill == old:
            shape.fill = new
            shape.stroke?.color = new
            return .shape(shape)
        case .group(var group):
            group.items = group.items.map { $0.recoloringMarkers(from: old, to: new) }
            return .group(group)
        default:
            return self
        }
    }
}
