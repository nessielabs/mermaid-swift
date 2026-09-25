import Foundation

extension MindmapDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        MindmapSceneBuilder(diagram: self, context: context).build()
    }
}

/// Draws a mindmap like mermaid.js: the root in the git0 color, each
/// top-level branch in its own section color shared by its descendants,
/// and tapering curved edges that thin out with depth.
struct MindmapSceneBuilder {
    let diagram: MindmapDiagram
    let context: RenderContext
    let config: ConfigValue
    var theme: Theme { context.theme }

    init(diagram: MindmapDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("mindmap")
    }

    /// A node flattened in pre-order, with everything needed to draw it.
    struct Placed {
        var node: MindmapDiagram.Node
        var label: TextBlock
        /// The shape's box (what the outline is drawn in).
        var box: Size
        /// Offset of the box's origin from the extent's origin.
        var inset: Point
        /// Top-level branch index; nil for the root.
        var section: Int?
    }

    var algorithm: MindmapLayout.Algorithm {
        let name = (context.config["layout"]?.stringValue ?? config["layoutAlgorithm"]?.stringValue ?? "").lowercased()
        return name == "tidy-tree" ? .tidyTree : .radial
    }

    /// Flattens the tree, measures every node and runs the layout.
    func layout() -> (placed: [Placed], layout: MindmapLayout) {
        guard let root = diagram.root else { return ([], MindmapLayout(items: [])) }
        let padding = config["padding"]?.numberValue ?? 10
        let maxWidth = config["maxNodeWidth"]?.numberValue ?? 200
        var placed: [Placed] = []
        var items: [MindmapLayout.Item] = []
        func visit(_ node: MindmapDiagram.Node, parent: Int?, depth: Int, section: Int?) {
            let label = context.label(node.label, maxWidth: maxWidth, forceWrap: true)
            let box = node.shape.size(label: Size(label.width, label.height), padding: padding,
                                      fontSize: theme.fontSize, hasIcon: node.icon != nil)
            let extent = node.shape.outline(in: Rect(x: 0, y: 0, width: box.width, height: box.height), padding: padding)
                .bounds ?? Rect(x: 0, y: 0, width: box.width, height: box.height)
            let index = items.count
            placed.append(Placed(node: node, label: label, box: box, inset: Point(-extent.minX, -extent.minY), section: section))
            items.append(.init(parent: parent, depth: depth, size: Size(extent.width, extent.height)))
            if let parent { items[parent].children.append(index) }
            for (k, child) in node.children.enumerated() {
                visit(child, parent: index, depth: depth + 1, section: section ?? k % 11)
            }
        }
        visit(root, parent: nil, depth: 0, section: nil)
        var layout = MindmapLayout(items: items)
        layout.run(algorithm)
        return (placed, layout)
    }

    func build() -> Scene {
        let (placed, layout) = layout()
        let frames = layout.frames
        let scale = theme.sectionColors
        let rootColor = GitGraphPalette(theme: theme).branchColor(0)
        func fill(_ section: Int?) -> Color { section.map { scale[($0 + 1) % scale.count] } ?? rootColor }

        var edges: [SceneItem] = []
        for (i, item) in layout.items.enumerated() {
            guard let p = item.parent else { continue }
            let depth = layout.items[p].depth + 1
            let width = depth <= 4 ? 14 - 3 * Double(depth) : 3
            edges.append(.group(GroupItem(id: "edge_\(p)_\(i)", role: "mindmap-edge", items: [
                .shape(ShapeItem(edgePath(from: layout.items[p].center, to: item.center, fromRoot: p == 0),
                                 stroke: Stroke(fill(placed[i].section), width: width, cap: .round))),
            ])))
        }
        var nodes: [SceneItem] = []
        for (i, entry) in placed.enumerated() {
            let box = Rect(x: frames[i].minX + entry.inset.x, y: frames[i].minY + entry.inset.y,
                           width: entry.box.width, height: entry.box.height)
            nodes.append(node(entry, in: box, fill: fill(entry.section), index: i))
        }
        let (content, size) = (edges + nodes).normalizedToOrigin()
        return DiagramCanvas(context: context, margin: config["diagramPadding"]?.numberValue ?? 10)
            .scene(content: content, size: size)
    }

    /// A gentle curve: straight out of the root, otherwise leaving and
    /// arriving along the direction away from the root (radial) or
    /// horizontally (tidy tree).
    private func edgePath(from a: Point, to b: Point, fromRoot: Bool) -> Path {
        var path = Path()
        path.move(to: a)
        let length = a.distance(to: b)
        let direction: Point
        switch algorithm {
        case .radial: direction = fromRoot ? (b - a).normalized : b.normalized
        case .tidyTree: direction = Point(b.x >= a.x ? 1 : -1, 0)
        }
        path.curve(to: b, control1: a + direction * (length * 0.4), control2: b - direction * (length * 0.4))
        return path
    }

    private func node(_ entry: Placed, in box: Rect, fill: Color, index: Int) -> SceneItem {
        let padding = config["padding"]?.numberValue ?? 10
        let shape = entry.node.shape
        let text = fill.luminance > 0.33 ? Color(hex: 0x222222) : Color.white
        let outline = shape.outline(in: box, padding: padding)
        var items: [SceneItem] = [.shape(ShapeItem(outline, fill: fill))]
        if shape == .default {
            items.append(.shape(ShapeItem(.polyline([Point(box.minX, box.maxY), Point(box.maxX, box.maxY)]),
                                          stroke: Stroke(fill.adjusted(hue: 180).darkened(10), width: 3))))
        }
        // Clouds and bangs bulge unevenly past their box; center on the ink.
        var labelArea = shape == .cloud || shape == .bang ? outline.bounds ?? box : box
        if let icon = entry.node.icon {
            let glyph = TextBlock(RichText(plain: Self.glyph(for: icon)), font: context.font(size: 24), measurer: context.measurer)
            let iconCenter: Point
            if shape == .circle {
                iconCenter = Point(box.midX, box.minY + 25 + padding / 2)
                labelArea = Rect(x: box.minX, y: box.minY + 50, width: box.width, height: box.height - 50)
            } else {
                iconCenter = Point(box.minX + 30, box.midY)
                labelArea = Rect(x: box.minX + 50, y: box.minY, width: box.width - 50, height: box.height)
            }
            items.append(.text(TextItem(glyph, centeredAt: iconCenter, color: text)))
        }
        items.append(.text(TextItem(entry.label, centeredAt: labelArea.center, color: text)))
        let classes = ["mindmap-node", entry.section.map { "section-\($0)" } ?? "section-root"] + entry.node.classes
        return .group(GroupItem(id: "node_\(index)", role: classes.joined(separator: " "), items: items))
    }

    /// Icon fonts are not available natively, so common Font Awesome and
    /// Material Design icon names map to similar Unicode symbols; anything
    /// else shows a neutral marker.
    static func glyph(for icon: String) -> String {
        let name = icon.split(separator: " ").last.map(String.init)?.lowercased() ?? ""
        let table: [(String, String)] = [
            ("book", "📖"), ("skull", "☠"), ("user", "👤"), ("person", "👤"), ("home", "🏠"), ("house", "🏠"),
            ("star", "★"), ("heart", "♥"), ("cog", "⚙"), ("gear", "⚙"), ("check", "✓"), ("lightbulb", "💡"),
            ("bulb", "💡"), ("flag", "⚑"), ("globe", "🌐"), ("envelope", "✉"), ("mail", "✉"), ("clock", "🕒"),
            ("calendar", "📅"), ("search", "🔍"), ("magnify", "🔍"), ("code", "⌨"), ("cloud", "☁"), ("lock", "🔒"),
            ("phone", "☎"), ("music", "♪"), ("camera", "📷"), ("car", "🚗"), ("tree", "🌳"), ("bolt", "⚡"),
            ("rocket", "🚀"), ("wrench", "🔧"), ("tools", "🔧"), ("chart", "📊"), ("database", "🛢"), ("file", "📄"),
            ("folder", "📁"), ("pencil", "✎"), ("pen", "✎"), ("comment", "💬"), ("bell", "🔔"), ("leaf", "🍃"),
            ("fire", "🔥"), ("warning", "⚠"), ("alert", "⚠"), ("info", "ℹ"), ("question", "?"), ("link", "🔗"),
        ]
        return table.first { name.contains($0.0) }?.1 ?? "◆"
    }
}
