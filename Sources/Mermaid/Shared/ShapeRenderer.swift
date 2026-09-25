/// Resolved colors and stroke for drawing one shape.
struct ShapePaint {
    var fill: Color
    var stroke: Color
    var strokeWidth: Double
    var dash: [Double]
    var text: Color
    var solid: Color
    var opacity: Double = 1

    init(fill: Color, stroke: Color, strokeWidth: Double = 1, dash: [Double] = [], text: Color, solid: Color? = nil) {
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.dash = dash
        self.text = text
        self.solid = solid ?? stroke
    }

    /// Applies explicit style overrides on top of these defaults.
    func applying(_ style: ElementStyle) -> ShapePaint {
        var paint = self
        if let fill = style.fill { paint.fill = fill }
        if let stroke = style.stroke { paint.stroke = stroke }
        if let width = style.strokeWidth { paint.strokeWidth = width }
        if let dash = style.strokeDash { paint.dash = dash }
        if let text = style.textColor { paint.text = text }
        if let opacity = style.opacity { paint.opacity = opacity }
        return paint
    }
}

/// Draws a node shape with an optional centered label.
enum ShapeRenderer {
    static func items(_ shape: NodeShape, frame: Rect, label: TextBlock?, paint: ShapePaint,
                      id: String? = nil, role: String = "node") -> SceneItem {
        let geometry = shape.geometry(in: frame)
        let stroke = geometry.stroked && paint.strokeWidth > 0
            ? Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash) : nil
        let fill: Color?
        switch geometry.fill {
        case .node: fill = paint.fill
        case .solid: fill = paint.solid
        case .none: fill = nil
        }
        var items: [SceneItem] = geometry.backgrounds.map { .shape(ShapeItem($0, fill: fill, stroke: stroke, opacity: paint.opacity)) }
        items.append(.shape(ShapeItem(geometry.body, fill: fill, stroke: stroke, opacity: paint.opacity)))
        let detailStroke = Stroke(paint.stroke, width: max(paint.strokeWidth, 1), dash: paint.dash)
        items += geometry.details.map { .shape(ShapeItem($0, stroke: detailStroke, opacity: paint.opacity)) }
        if let label, !label.isEmpty, !shape.isLabelless {
            items.append(.text(TextItem(label, centeredAt: geometry.labelCenter, color: paint.text)))
        }
        return .group(GroupItem(id: id, role: role, items: items))
    }
}
