import Foundation

extension SankeyDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        SankeySceneBuilder(diagram: self, context: context).build()
    }
}

/// Draws a sankey diagram like mermaid.js: d3-sankey geometry within
/// width × height, nodes colored from d3's Tableau 10 scheme (or
/// `nodeColors`), translucent links colored by `linkColor`, and node
/// labels beside the nodes.
struct SankeySceneBuilder {
    let diagram: SankeyDiagram
    let context: RenderContext
    let config: ConfigValue

    init(diagram: SankeyDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("sankey")
    }

    /// d3.schemeTableau10, which mermaid.js assigns to nodes in order.
    static let tableau10: [UInt32] = [0x4E79A7, 0xF28E2C, 0xE15759, 0x76B7B2, 0x59A14F,
                                      0xEDC949, 0xAF7AA1, 0xFF9DA7, 0x9C755F, 0xBAB0AB]

    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }
    var width: Double { setting("width", 600) }
    var height: Double { setting("height", 400) }
    var showValues: Bool { config["showValues"]?.boolValue ?? true }

    func nodeColor(_ index: Int) -> Color {
        let name = diagram.nodes[index]
        if let custom = config["nodeColors"]?[name]?.stringValue, let color = Color(css: custom) { return color }
        return Color(hex: Self.tableau10[index % Self.tableau10.count])
    }

    func layout() -> SankeyLayout {
        let alignment = SankeyLayout.Alignment(rawValue: config["nodeAlignment"]?.stringValue ?? "") ?? .justify
        // mermaid.js adds room for the value line under each label.
        let padding = setting("nodePadding", 12) + (showValues ? 15 : 0)
        var layout = SankeyLayout(nodeCount: diagram.nodes.count,
                                  links: diagram.links.map { ($0.source, $0.target, $0.value) },
                                  extent: Rect(x: 0, y: 0, width: width, height: height),
                                  nodeWidth: setting("nodeWidth", 10), nodePadding: padding, alignment: alignment)
        layout.compute()
        return layout
    }

    func build() -> Scene {
        let layout = layout()
        var items: [SceneItem] = [.group(GroupItem(role: "links", items: links(layout)))]
        items.append(.group(GroupItem(role: "nodes", items: layout.nodes.indices.map { i in
            .group(GroupItem(id: diagram.nodes[i], role: "node", items: [
                .shape(ShapeItem(.rect(layout.nodes[i].frame), fill: nodeColor(i))),
            ]))
        })))
        items.append(.group(GroupItem(role: "node-labels", items: labels(layout))))
        var frame = Rect(x: 0, y: 0, width: width, height: height)
        if let content = items.compactMap(\.bounds).reduce(nil, { $0?.union($1) ?? $1 }) { frame = frame.union(content) }
        let shifted = items.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        return DiagramCanvas(context: context, margin: 0).scene(content: shifted, size: frame.size)
    }

    // MARK: - Links

    /// A link as a filled ribbon of constant vertical thickness following
    /// d3's horizontal link curve (control points at the midpoint x).
    static func ribbon(from start: Point, to end: Point, thickness: Double) -> Path {
        let half = thickness / 2, midX = (start.x + end.x) / 2
        var path = Path()
        path.move(to: Point(start.x, start.y - half))
        path.curve(to: Point(end.x, end.y - half), control1: Point(midX, start.y - half), control2: Point(midX, end.y - half))
        path.line(to: Point(end.x, end.y + half))
        path.curve(to: Point(start.x, start.y + half), control1: Point(midX, end.y + half), control2: Point(midX, start.y + half))
        path.close()
        return path
    }

    func links(_ layout: SankeyLayout) -> [SceneItem] {
        let mode = config["linkColor"]?.stringValue ?? "gradient"
        return layout.links.enumerated().map { index, link in
            let source = layout.nodes[link.source], target = layout.nodes[link.target]
            let start = Point(source.x1, link.y0), end = Point(target.x0, link.y1)
            let path = Self.ribbon(from: start, to: end, thickness: max(1, link.width))
            let shape: ShapeItem
            switch mode {
            case "source": shape = ShapeItem(path, fill: nodeColor(link.source), opacity: 0.5)
            case "target": shape = ShapeItem(path, fill: nodeColor(link.target), opacity: 0.5)
            default:
                if mode != "gradient", let color = Color(css: mode) {
                    shape = ShapeItem(path, fill: color, opacity: 0.5)
                } else {
                    let gradient = LinearGradient(from: nodeColor(link.source), at: Point(start.x, 0),
                                                  to: nodeColor(link.target), at: Point(end.x, 0))
                    shape = ShapeItem(path, fill: nodeColor(link.source), opacity: 0.5, gradient: gradient)
                }
            }
            let id = "\(diagram.nodes[link.source])->\(diagram.nodes[link.target])-\(index)"
            return .group(GroupItem(id: id, role: "link", items: [.shape(shape)]))
        }
    }

    // MARK: - Labels

    func labelText(_ index: Int, _ node: SankeyLayout.Node) -> String {
        guard showValues else { return diagram.nodes[index] }
        let prefix = config["prefix"]?.stringValue ?? "", suffix = config["suffix"]?.stringValue ?? ""
        // mermaid.js joins the name and value with a newline that SVG
        // renders as a space.
        return "\(diagram.nodes[index]) \(prefix)\(ChartNumber.format((node.value * 100).rounded() / 100))\(suffix)"
    }

    func labels(_ layout: SankeyLayout) -> [SceneItem] {
        let outlined = config["labelStyle"]?.stringValue == "outlined"
        // Outlined labels sit on the side facing away from the layer of
        // the largest node; legacy labels by which half of the chart the
        // node is in.
        let centralLayer = layout.nodes.max { $0.value < $1.value }?.layer ?? 0
        let halo = context.theme.color("mainBkg") ?? context.theme.background
        return layout.nodes.enumerated().flatMap { index, node -> [SceneItem] in
            let block = context.text(RichText(plain: labelText(index, node)), size: 14)
            let leftSide = outlined ? node.layer < centralLayer : node.x0 >= width / 2
            let at = Point(leftSide ? node.x0 - 6 : node.x1 + 6, (node.y0 + node.y1) / 2)
            let anchor: TextAnchor = leftSide ? .trailing : .leading
            let text = TextItem(block, at: at, anchor: anchor, color: context.theme.textColor)
            guard outlined else { return [.text(text)] }
            // A halo in the background color, drawn as offset copies, keeps
            // labels readable over links in both renderers.
            let offsets = stride(from: 0.0, to: 360, by: 45).map { Point(2 * cos($0 * .pi / 180), 2 * sin($0 * .pi / 180)) }
            let ring: [SceneItem] = offsets.map { offset in
                var copy = text
                copy.color = halo
                return SceneItem.text(copy).offsetBy(dx: offset.x, dy: offset.y)
            }
            return ring + [.text(text)]
        }
    }
}
