extension C4Diagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        C4SceneBuilder(diagram: self, context: context).build()
    }
}

struct C4SceneBuilder {
    let diagram: C4Diagram
    let context: RenderContext
    let palette: C4Palette

    init(diagram: C4Diagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        palette = C4Palette(context: context)
    }

    /// Tag styles in tag order, overlaid by `UpdateElementStyle`.
    func style(of element: C4Diagram.Element) -> C4Diagram.ElementStyle {
        element.tags.compactMap { diagram.elementTags[$0] }.reduce(C4Diagram.ElementStyle()) { $0.overlaid(with: $1) }
            .overlaid(with: element.style)
    }

    func build() -> Scene {
        var boxes: [String: C4ElementBox] = [:]
        for element in diagram.elements {
            boxes[element.alias] = C4ElementBox(element, style: style(of: element), palette: palette, measurer: context.measurer)
        }
        var headers: [String: C4BoundaryHeader] = [:]
        for boundary in diagram.boundaries {
            headers[boundary.alias] = C4BoundaryHeader(boundary, palette: palette, measurer: context.measurer)
        }
        let gap = palette.shapeMargin * 1.6
        let layout = C4Layout.compute(diagram, C4Layout.Input(
            elementSizes: boxes.mapValues(\.size), headerSizes: headers.mapValues(\.size),
            shapesPerRow: diagram.shapesPerRow ?? palette.shapesPerRow,
            boundariesPerRow: diagram.boundariesPerRow ?? palette.boundariesPerRow,
            shapeGap: Size(gap, gap), boundaryGap: palette.shapeMargin, inset: 20))

        var items: [SceneItem] = []
        for boundary in diagram.boundaries {
            guard let frame = layout.boundaries[boundary.alias], let header = headers[boundary.alias] else { continue }
            items.append(header.items(in: frame, boundary: boundary, palette: palette))
        }
        var outlines: [String: [Point]] = [:]
        for (alias, frame) in layout.boundaries { outlines[alias] = EdgeGeometry.rectOutline(frame) }
        for (alias, frame) in layout.elements { outlines[alias] = boxes[alias]?.outline(in: frame) }
        // Labels keep clear of elements and of boundary titles.
        var obstacles = Array(layout.elements.values)
        for (alias, frame) in layout.boundaries {
            guard let header = headers[alias] else { continue }
            obstacles.append(Rect(x: frame.minX, y: frame.minY + 8, width: frame.width, height: header.size.height + 8))
        }
        let relationships = C4RelationshipRenderer(diagram: diagram, palette: palette, measurer: context.measurer,
                                                   outlines: outlines, elementFrames: Array(layout.elements.values), obstacles: obstacles,
                                                   background: context.theme.background)
        let (lines, labels) = relationships.items()
        items += lines
        for element in diagram.elements {
            guard let frame = layout.elements[element.alias], let box = boxes[element.alias] else { continue }
            items.append(box.items(in: frame, id: element.alias))
        }
        items += labels
        let bounds = items.compactMap(\.inkBounds).reduce(Rect(x: 0, y: 0, width: layout.size.width, height: layout.size.height)) { $0.union($1) }
        let content = items.map { $0.offsetBy(dx: -bounds.minX, dy: -bounds.minY) }
        let canvas = DiagramCanvas(context: context, margin: palette.diagramMarginY * 2, title: diagram.title)
        return canvas.scene(content: content, size: bounds.size)
    }
}

/// A boundary's title block: bold label, `[type]`, and description.
struct C4BoundaryHeader {
    var lines: [(block: TextBlock, top: Double)] = []
    var size = Size.zero

    init(_ boundary: C4Diagram.Boundary, palette: C4Palette, measurer: any TextMeasurer) {
        let fonts: [(String, Font)] = [
            (boundary.label, palette.font("boundary", delta: 2, bold: true)),
            (boundary.type.isEmpty ? "" : "[\(boundary.type)]", palette.font("boundary", delta: -1, italic: true)),
            (boundary.description, palette.font("boundary", delta: -2)),
        ]
        var y = 0.0
        for (text, font) in fonts where !text.isEmpty {
            let block = TextBlock(LabelParser.parse(text), font: font, measurer: measurer,
                                  maxWidth: palette.wrap ? 360 : nil, forceWrap: palette.wrap)
            if !lines.isEmpty { y += 2 }
            lines.append((block, y))
            y += block.height
        }
        size = Size(lines.map(\.block.width).max() ?? 0, y)
    }

    func items(in frame: Rect, boundary: C4Diagram.Boundary, palette: C4Palette) -> SceneItem {
        var alignment = TextItem.Alignment.leading
        if case .deploymentNode(let nodeAlignment) = boundary.kind { alignment = nodeAlignment ?? .center }
        let isNode = alignment != .leading || { if case .deploymentNode = boundary.kind { return true }; return false }()
        let stroke = Stroke(boundary.style.border ?? palette.neutralLine, width: 1, dash: isNode ? [] : [7, 7])
        var items: [SceneItem] = [.shape(ShapeItem(.rect(frame, cornerRadius: 4), fill: boundary.style.background, stroke: stroke))]
        let color = boundary.style.font ?? palette.neutralText
        let inner = frame.insetBy(dx: 12, dy: 0)
        for line in lines {
            let box = Rect(x: inner.minX, y: frame.minY + 12 + line.top, width: inner.width, height: line.block.height)
            items.append(.text(TextItem(line.block, frame: box, alignment: alignment, color: color)))
        }
        return .group(GroupItem(id: boundary.alias, role: "c4-boundary", items: items))
    }
}
