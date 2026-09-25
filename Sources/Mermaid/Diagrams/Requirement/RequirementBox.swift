/// A requirement or element drawn as mermaid.js' `requirementBox`: a
/// centered `<<Stereotype>>` and bold name, a divider, then left-aligned
/// `Field: value` lines.
struct RequirementBox {
    let stereotype: TextBlock
    let name: TextBlock
    let body: [TextBlock]
    let size: Size

    /// Space around the content.
    static let padding = Size(16, 10)
    /// Space between the name and the body, split by the divider.
    static let gap = 20.0

    init(stereotype: TextBlock, name: TextBlock, body: [TextBlock]) {
        self.stereotype = stereotype
        self.name = name
        self.body = body.filter { !$0.isEmpty }
        let widths = [stereotype.width, name.width] + self.body.map(\.width)
        var height = stereotype.height + name.height + 2 * Self.padding.height
        if !self.body.isEmpty { height += Self.gap + self.body.map(\.height).reduce(0, +) }
        size = Size((widths.max() ?? 0) + 2 * Self.padding.width, height)
    }

    struct Paint {
        var fill: Color
        var stroke: Color
        var strokeWidth: Double
        var dash: [Double]
        var text: Color
        var opacity: Double
    }

    func items(in frame: Rect, paint: Paint, id: String, role: String) -> SceneItem {
        let stroke = paint.strokeWidth > 0 ? Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash) : nil
        var items: [SceneItem] = [.shape(ShapeItem(.rect(frame), fill: paint.fill, stroke: stroke, opacity: paint.opacity))]
        var y = frame.minY + Self.padding.height
        for block in [stereotype, name] {
            items.append(.text(TextItem(block, centeredAt: Point(frame.midX, y + block.height / 2), color: paint.text)))
            y += block.height
        }
        guard !body.isEmpty else { return .group(GroupItem(id: id, role: role, items: items)) }
        let divider = y + Self.gap / 2
        if let stroke {
            items.append(.shape(ShapeItem(.polyline([Point(frame.minX, divider), Point(frame.maxX, divider)]),
                                          stroke: stroke, opacity: paint.opacity)))
        }
        y += Self.gap
        for block in body {
            let line = Rect(x: frame.minX + Self.padding.width, y: y, width: frame.width - 2 * Self.padding.width,
                            height: block.height)
            items.append(.text(TextItem(block, frame: line, alignment: .leading, color: paint.text)))
            y += block.height
        }
        return .group(GroupItem(id: id, role: role, items: items))
    }
}
