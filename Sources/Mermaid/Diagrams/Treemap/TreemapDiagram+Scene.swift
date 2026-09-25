extension TreemapDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        TreemapSceneBuilder(diagram: self, context: context).build()
    }
}

/// Draws a treemap the way mermaid.js does: tinted section boxes with a
/// header (name and total), and leaves tinted with their section's color
/// showing a label and value sized to fill the cell.
struct TreemapSceneBuilder {
    let diagram: TreemapDiagram
    let context: RenderContext
    let config: ConfigValue
    var theme: Theme { context.theme }

    init(diagram: TreemapDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("treemap")
    }

    static let headerHeight = 25.0

    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }

    /// The laid-out cells for the configured canvas (`nodeWidth` × 10 by
    /// `nodeHeight` × 10, as in mermaid.js).
    func cells() -> [TreemapLayout.Cell] {
        let width = max(10, setting("nodeWidth", 100) * 10), height = max(10, setting("nodeHeight", 40) * 10)
        let layout = TreemapLayout(headerHeight: Self.headerHeight, sectionPadding: 10,
                                   innerPadding: max(0, setting("padding", 10)))
        return layout.layout(diagram.roots, in: Rect(x: 0, y: 0, width: width, height: height))
    }

    func build() -> Scene {
        let cells = cells()
        let colors = sectionColors(cells)
        let format = NumberFormat.mermaidValueFormat(config["valueFormat"]?.stringValue ?? ",")
        let showValues = config["showValues"]?.boolValue ?? true
        var items: [SceneItem] = []
        let branches = breadthFirst(cells).filter { cells[$0].depth > 0 && !cells[$0].children.isEmpty }
        for index in branches {
            items.append(section(cells[index], color: colors[index] ?? .clear, format: showValues ? format : nil))
        }
        let leaves = cells.indices.filter { cells[$0].depth > 0 && cells[$0].children.isEmpty }
        let dense = leaves.count > 20
        for index in leaves {
            let cell = cells[index]
            // A leaf takes its section's color; a top-level leaf has no section,
            // so it gets a color of its own rather than mermaid's invisible one.
            // A styled section passes its fill on to its leaves.
            let owner = cell.depth > 1 ? cell.parent ?? 0 : index
            let color = (owner != index ? style(for: cells[owner].node).fill?.withAlpha(1) : nil) ?? colors[owner]
            items.append(leaf(cell, index: index, color: color ?? theme.primaryColor, dense: dense,
                              format: showValues ? format : nil))
        }
        let size = cells.first.map { Size($0.frame.width, $0.frame.height) } ?? .zero
        return DiagramCanvas(context: context, margin: setting("diagramPadding", 8), title: diagram.title ?? context.title)
            .scene(content: items, size: size)
    }

    /// Cell indices in breadth-first order, as d3's `descendants()` lists them.
    func breadthFirst(_ cells: [TreemapLayout.Cell]) -> [Int] {
        guard !cells.isEmpty else { return [] }
        var order = [0], i = 0
        while i < order.count { order += cells[order[i]].children; i += 1 }
        return order
    }

    /// mermaid.js colors cells with an ordinal scale over names: the virtual
    /// root takes the first (transparent) slot and each newly seen section
    /// name takes the next section color, in breadth-first order.
    func sectionColors(_ cells: [TreemapLayout.Cell]) -> [Int: Color] {
        var byName: [String: Color] = [:]
        var next = 0
        let palette = theme.sectionColors
        func color(for name: String) -> Color {
            if let known = byName[name] { return known }
            let assigned = palette[next % palette.count]
            next += 1
            byName[name] = assigned
            return assigned
        }
        var result: [Int: Color] = [:]
        for index in breadthFirst(cells) where cells[index].depth > 0 {
            let cell = cells[index]
            if !cell.children.isEmpty || cell.depth == 1 { result[index] = color(for: cell.node.name) }
        }
        return result
    }

    func style(for node: TreemapDiagram.Node) -> ElementStyle {
        node.className.flatMap { diagram.classDefinitions[$0] } ?? ElementStyle()
    }

    /// Dark or light text, whichever reads on `fill` laid over the background.
    func contrastingText(on fill: Color) -> Color {
        let visible = theme.background.mixed(with: fill.withAlpha(1), amount: fill.alpha)
        return visible.luminance > 0.36 ? Color(hex: 0x222222) : Color(hex: 0xF4F4F4)
    }

    private func section(_ cell: TreemapLayout.Cell, color: Color, format: (@Sendable (Double) -> String)?) -> SceneItem {
        let style = style(for: cell.node)
        let frame = cell.frame
        let fill = style.fill ?? color.withAlpha(0.6)
        let stroke = style.stroke ?? color.darkened(25).withAlpha(0.4)
        var items: [SceneItem] = [
            .shape(ShapeItem(.rect(frame), fill: fill,
                             stroke: Stroke(stroke, width: style.strokeWidth ?? 2, dash: style.strokeDash ?? []),
                             opacity: style.opacity ?? 1)),
        ]
        let textColor = style.textColor ?? contrastingText(on: fill)
        let header = Rect(x: frame.minX, y: frame.minY, width: frame.width, height: min(Self.headerHeight, frame.height))
        var valueWidth = 0.0
        if let format, cell.value > 0 {
            let font = Font(family: theme.fontFamily, size: 10, italic: true)
            let block = TextBlock(RichText(plain: format(cell.value)), font: font, measurer: context.measurer)
            if block.width < frame.width - 30 {
                valueWidth = block.width
                items.append(.text(TextItem(block, frame: Rect(x: header.maxX - 10 - block.width, y: header.minY,
                                                               width: block.width, height: header.height),
                                            alignment: .trailing, color: textColor)))
            }
        }
        let available = frame.width - 6 - (valueWidth > 0 ? valueWidth + 20 : 6)
        let fitting = TextFitting(measurer: context.measurer, font: context.font(size: 12, bold: true), minimumSize: 12)
        if let label = fitting.fitSingleLine(cell.node.name, width: available, height: header.height) {
            items.append(.text(TextItem(label, frame: Rect(x: header.minX + 6, y: header.minY, width: label.width, height: header.height),
                                        alignment: .leading, color: textColor)))
        }
        return .group(GroupItem(id: cell.node.name, role: "treemap-section", items: items))
    }

    private func leaf(_ cell: TreemapLayout.Cell, index: Int, color: Color, dense: Bool,
                      format: (@Sendable (Double) -> String)?) -> SceneItem {
        let style = style(for: cell.node)
        let frame = cell.frame
        let fill = style.fill ?? color.withAlpha(0.3)
        var items: [SceneItem] = [
            .shape(ShapeItem(.rect(frame), fill: fill,
                             stroke: Stroke(style.stroke ?? color, width: style.strokeWidth ?? 3, dash: style.strokeDash ?? []),
                             opacity: style.opacity ?? 1)),
        ]
        let textColor = style.textColor ?? contrastingText(on: fill)
        if let (label, value) = leafText(cell, dense: dense, format: format) {
            let spacing = dense ? 1.0 : 2.0
            let total = label.height + (value.map { $0.height + spacing } ?? 0)
            let top = frame.midY - total / 2
            items.append(.text(TextItem(label, frame: Rect(x: frame.minX, y: top, width: frame.width, height: label.height),
                                        color: textColor)))
            if let value {
                items.append(.text(TextItem(value, frame: Rect(x: frame.minX, y: top + label.height + spacing,
                                                               width: frame.width, height: value.height), color: textColor)))
            }
        }
        return .group(GroupItem(id: "leaf\(index)", role: "treemap-leaf", items: items))
    }

    /// The largest label (and value beneath it, at 60% of the label size)
    /// that fits the cell, following mermaid.js's font sizes: 38 px shrinking
    /// to 8 px, or 16 px to 4 px when there are more than 20 leaves. Labels
    /// wrap at word boundaries when that keeps them larger.
    func leafText(_ cell: TreemapLayout.Cell, dense: Bool,
                  format: (@Sendable (Double) -> String)?) -> (TextBlock, TextBlock?)? {
        let padding = dense ? 2.0 : 4.0
        let (base, minimum, baseValue, minimumValue) = dense ? (16.0, 4.0, 14.0, 4.0) : (38.0, 8.0, 28.0, 6.0)
        let width = cell.frame.width - 2 * padding, height = cell.frame.height - 2 * padding
        guard width >= (dense ? 8 : 10), height >= (dense ? 8 : 10) else { return nil }
        let text = LabelParser.parse(cell.node.name)
        let valueText = format.map { $0(cell.value) }
        var size = base
        while size >= minimum {
            let font = context.font(size: size)
            let valueSize = max(minimumValue, min(baseValue, (size * 0.6).rounded()))
            let value = valueText.map {
                TextBlock(RichText(plain: $0), font: context.font(size: valueSize), measurer: context.measurer)
            }
            let valueHeight = value.map { $0.height + (dense ? 1 : 2) } ?? 0
            let single = TextBlock(text, font: font, measurer: context.measurer)
            let wrapped = TextBlock(text, font: font, measurer: context.measurer, maxWidth: width, forceWrap: true)
            for candidate in [single, wrapped] where candidate.width <= width && candidate.height + valueHeight <= height {
                if candidate.lines.count > 1, TextFitting.breaksWords(candidate, of: text) { continue }
                let fittingValue = value.flatMap { $0.width <= width ? $0 : nil }
                return (candidate, fittingValue)
            }
            size -= 1
        }
        return nil
    }
}
