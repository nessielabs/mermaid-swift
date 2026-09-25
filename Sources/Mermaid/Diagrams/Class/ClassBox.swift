/// A measured UML class box: a header with annotations and the bold,
/// centered name, then left-aligned attribute and method compartments
/// separated by dividers.
struct ClassBox {
    /// One member line; static members are underlined.
    struct Line {
        var block: TextBlock
        var underline: Bool
    }

    var annotations: [TextBlock] = []
    var title: TextBlock
    var attributes: [Line] = []
    var methods: [Line] = []
    /// False when `hideEmptyMembersBox` drops both empty compartments.
    var showsCompartments = true

    /// Space between text and the box's left and right edges.
    var padding: Double
    /// Space above and below the text of each compartment.
    var margin: Double
    /// Gap between consecutive member lines.
    var lineGap = 2.0

    init(_ item: ClassDiagram.Class, font: Font, measurer: any TextMeasurer,
         padding: Double, margin: Double, hideEmptyMembers: Bool) {
        self.padding = padding
        self.margin = margin
        func block(_ text: String, bold: Bool = false, italic: Bool = false) -> TextBlock {
            TextBlock(RichText(lines: [[RichText.Span(text, bold: bold, italic: italic)]]), font: font, measurer: measurer)
        }
        annotations = item.annotations.map { block("«" + $0 + "»") }
        title = block(item.displayName, bold: true)
        func line(_ member: ClassMember) -> Line {
            Line(block: block(member.displayText, italic: member.classifier == .abstract),
                 underline: member.classifier == .static)
        }
        attributes = item.attributes.map(line)
        methods = item.methods.map(line)
        showsCompartments = !(hideEmptyMembers && attributes.isEmpty && methods.isEmpty)
    }

    var headerHeight: Double {
        let text = (annotations + [title]).map(\.height).reduce(0, +)
        return text + 2 * margin
    }

    func compartmentHeight(_ lines: [Line]) -> Double {
        guard !lines.isEmpty else { return margin }
        let text = lines.map(\.block.height).reduce(0, +) + Double(lines.count - 1) * lineGap
        return text + 2 * margin
    }

    var size: Size {
        let header = (annotations + [title]).map(\.width).max() ?? 0
        let members = (attributes + methods).map(\.block.width).max() ?? 0
        var height = headerHeight
        if showsCompartments { height += compartmentHeight(attributes) + compartmentHeight(methods) }
        return Size(max(header, members) + 2 * padding, height)
    }

    /// Draws the box in `frame` (at least `size`), with text and dividers
    /// in the paint's colors.
    func items(in frame: Rect, paint: ShapePaint, id: String?) -> SceneItem {
        let stroke = paint.strokeWidth > 0 ? Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash) : nil
        var items: [SceneItem] = [.shape(ShapeItem(.rect(frame), fill: paint.fill, stroke: stroke, opacity: paint.opacity))]
        var y = frame.minY + margin
        for block in annotations + [title] {
            items.append(.text(TextItem(block, centeredAt: Point(frame.midX, y + block.height / 2), color: paint.text)))
            y += block.height
        }
        guard showsCompartments else { return .group(GroupItem(id: id, role: "class", items: items)) }
        let divider = Stroke(paint.stroke, width: max(paint.strokeWidth, 1))
        var top = frame.minY + headerHeight
        for lines in [attributes, methods] {
            items.append(.shape(ShapeItem(.polyline([Point(frame.minX, top), Point(frame.maxX, top)]),
                                          stroke: divider, opacity: paint.opacity)))
            y = top + margin
            for line in lines {
                let textFrame = Rect(x: frame.minX + padding, y: y, width: line.block.width, height: line.block.height)
                let text = TextItem(line.block, frame: textFrame, alignment: .leading, color: paint.text)
                items.append(.text(text))
                if line.underline { items += underline(text) }
                y += line.block.height + lineGap
            }
            top += compartmentHeight(lines)
        }
        return .group(GroupItem(id: id, role: "class", items: items))
    }

    /// Underlines each line of a text item just below its baseline.
    private func underline(_ text: TextItem) -> [SceneItem] {
        text.block.lines.map { line in
            let origin = text.lineOrigin(line)
            let y = origin.y + 2
            return .shape(ShapeItem(.polyline([Point(origin.x, y), Point(origin.x + line.width, y)]),
                                    stroke: Stroke(text.color, width: 1)))
        }
    }
}
