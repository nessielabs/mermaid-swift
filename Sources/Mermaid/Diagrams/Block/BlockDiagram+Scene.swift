extension BlockDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        BlockSceneBuilder(diagram: self, context: context).build()
    }
}

/// Draws a block diagram: composites as translucent cluster boxes, blocks
/// in their shapes (stretched to their grid cell like mermaid.js, except
/// shapes that must keep their proportions), block arrows, and straight
/// edges between blocks with labels at their midpoints.
struct BlockSceneBuilder {
    let diagram: BlockDiagram
    let context: RenderContext
    let config: ConfigValue
    var theme: Theme { context.theme }

    init(diagram: BlockDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("block")
    }

    var padding: Double { max(0, config["padding"]?.numberValue ?? 8) }

    /// Class definitions (`default` first) overlaid by the block's own style.
    func style(of block: BlockDiagram.Block) -> ElementStyle {
        var style = diagram.classDefinitions["default"] ?? ElementStyle()
        for name in block.classes { if let def = diagram.classDefinitions[name] { style = style.overlaid(with: def) } }
        return style.overlaid(with: block.style)
    }

    func label(of block: BlockDiagram.Block) -> TextBlock {
        let style = style(of: block)
        let font = Font(family: style.fontFamily ?? theme.fontFamily, size: style.fontSize ?? theme.fontSize,
                        bold: style.bold ?? false, italic: style.italic ?? false)
        return TextBlock(LabelParser.parse(block.label), font: font, measurer: context.measurer)
    }

    /// The natural size of a leaf block around its label.
    func leafSize(_ block: BlockDiagram.Block) -> Size {
        let text = label(of: block)
        let p = padding
        switch block.kind {
        case .arrow(let directions):
            return BlockArrowShape.size(directions, label: Size(text.width, text.height), padding: p)
        case .node(let shape):
            // Horizontal padding is doubled so blocks do not hug their text.
            return shape.size(forLabel: Size(text.width + 2 * p, text.height), padding: p)
        case .space, .composite:
            return .zero
        }
    }

    func headerHeight(_ block: BlockDiagram.Block) -> Double {
        guard block.id != "root", !block.label.trimmingWhitespace().isEmpty else { return 0 }
        return label(of: block).height + 4
    }

    func layout() -> (frames: [String: Rect], size: Size) {
        var layout = BlockLayout(diagram: diagram, padding: padding, leafSize: leafSize, headerHeight: headerHeight)
        let size = layout.run()
        return (layout.frames, size)
    }

    /// The drawn frame of a block inside its grid cell: most shapes fill the
    /// cell; circles, diamonds and unspanned block arrows keep their natural
    /// size, centered, as mermaid.js draws them.
    func shapeFrame(_ block: BlockDiagram.Block, cell: Rect) -> Rect {
        let natural = leafSize(block)
        switch block.kind {
        case .node(.circle), .node(.doubleCircle), .node(.diamond):
            let side = min(natural.width, cell.width, cell.height)
            return Rect(center: cell.center, size: Size(side, side))
        case .arrow:
            let width = block.span > 1 ? cell.width : min(natural.width, cell.width)
            return Rect(center: cell.center, size: Size(width, min(natural.height, cell.height)))
        default:
            return cell
        }
    }

    func outline(_ block: BlockDiagram.Block, frame: Rect) -> [Point] {
        switch block.kind {
        case .node(let shape): return shape.outline(in: frame)
        case .arrow(let directions): return BlockArrowShape.outline(directions, in: frame, padding: padding)
        default: return EdgeGeometry.rectOutline(frame)
        }
    }

    func build() -> Scene {
        let (cells, size) = layout()
        var composites: [SceneItem] = [], leaves: [SceneItem] = []
        var outlines: [String: [Point]] = [:]
        // Outer composites first so nested ones draw on top of them.
        func visit(_ id: String) {
            guard let block = diagram.blocks[id] else { return }
            for childID in block.children {
                guard let child = diagram.blocks[childID], let cell = cells[childID] else { continue }
                switch child.kind {
                case .space: continue
                case .composite:
                    composites.append(composite(child, frame: cell))
                    outlines[childID] = EdgeGeometry.rectOutline(cell)
                    visit(childID)
                case .node, .arrow:
                    let frame = shapeFrame(child, cell: cell)
                    outlines[childID] = outline(child, frame: frame)
                    leaves.append(leaf(child, frame: frame))
                }
            }
        }
        visit("root")
        let edges = diagram.edges.enumerated().flatMap { edge($0.element, index: $0.offset, outlines: outlines) }
        let margin = config["diagramPadding"]?.numberValue ?? 8
        return DiagramCanvas(context: context, margin: margin).scene(content: composites + leaves + edges, size: size)
    }

    private func composite(_ block: BlockDiagram.Block, frame: Rect) -> SceneItem {
        let style = style(of: block)
        let paint = ShapePaint(fill: theme.clusterBkg.withAlpha(0.5), stroke: theme.clusterBorder.withAlpha(0.5),
                               text: theme.titleColor).applying(style)
        var items: [SceneItem] = [
            .shape(ShapeItem(.rect(frame, cornerRadius: style.cornerRadius ?? 0), fill: paint.fill,
                             stroke: paint.strokeWidth > 0 ? Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash) : nil,
                             opacity: paint.opacity)),
        ]
        let header = headerHeight(block)
        if header > 0 {
            items.append(.text(TextItem(label(of: block), centeredAt: Point(frame.midX, frame.minY + padding / 2 + header / 2),
                                        color: paint.text)))
        }
        return .group(GroupItem(id: block.id, role: "block-composite", items: items))
    }

    private func leaf(_ block: BlockDiagram.Block, frame: Rect) -> SceneItem {
        let paint = ShapePaint(fill: theme.mainBkg, stroke: theme.nodeBorder, text: theme.nodeTextColor, solid: theme.lineColor)
            .applying(style(of: block))
        let text = label(of: block)
        switch block.kind {
        case .arrow(let directions):
            let polygon = BlockArrowShape.outline(directions, in: frame, padding: padding)
            return .group(GroupItem(id: block.id, role: "block-arrow", items: [
                .shape(ShapeItem(.polygon(polygon), fill: paint.fill,
                                 stroke: paint.strokeWidth > 0 ? Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash) : nil,
                                 opacity: paint.opacity)),
                .text(TextItem(text, centeredAt: BlockArrowShape.labelCenter(directions, in: frame), color: paint.text)),
            ]))
        case .node(let shape):
            return ShapeRenderer.items(shape, frame: frame, label: text, paint: paint, id: block.id, role: "block")
        default:
            return .group(GroupItem(id: block.id, items: []))
        }
    }

    private func edge(_ edge: BlockDiagram.Edge, index: Int, outlines: [String: [Point]]) -> [SceneItem] {
        guard edge.stroke != .invisible, let source = outlines[edge.from], let target = outlines[edge.to],
              let a = Rect.bounding(source)?.center, let b = Rect.bounding(target)?.center else { return [] }
        let text = edge.label.flatMap { $0.isEmpty ? nil : context.label($0) }
        let connector = Connector(
            route: [a, a.interpolated(to: b, 0.5), b], sourceOutline: source, targetOutline: target, curve: .linear,
            color: theme.lineColor, width: edge.stroke == .thick ? 3.5 : 1.5, dash: edge.stroke == .dotted ? [3, 3] : [],
            startMarker: edge.startMarker, endMarker: edge.endMarker, label: text, labelCenter: nil,
            labelColor: theme.textColor, labelBackground: theme.edgeLabelBackground, background: theme.background,
            id: "\(index + 1)-\(edge.from)-\(edge.to)")
        return connector.items()
    }
}
