extension SequenceSceneBuilder {
    func message(_ placed: SequenceLayout.Message, index: Int) -> SceneItem {
        let m = placed.message
        let width = Self.lineWidth
        let stroke = Stroke(palette.signalColor, width: width, dash: m.line == .dotted ? [3, 3] : [], join: .round)
        var items: [SceneItem] = []
        let path: Path
        let endDirection: Point, startDirection: Point
        if let loopRight = placed.loopRight {
            (path, startDirection, endDirection) = selfLoop(placed, right: loopRight, width: width)
        } else {
            let d = Point(placed.end.x >= placed.start.x ? 1 : -1, 0)
            let start = placed.start + d * m.tail.inset(lineWidth: width)
            let end = placed.end - d * m.head.inset(lineWidth: width)
            path = .polyline([start, end])
            (startDirection, endDirection) = (d * -1, d)
        }
        items.append(.shape(ShapeItem(path, stroke: stroke)))
        items += m.head.items(tip: placed.end, direction: endDirection, color: palette.signalColor,
                              lineWidth: width, background: palette.background)
        items += m.tail.items(tip: placed.start, direction: startDirection, color: palette.signalColor,
                              lineWidth: width, background: palette.background)
        for dot in placed.dots {
            items.append(.shape(ShapeItem(.circle(center: dot, radius: SequenceLayoutBuilder.dotRadius), fill: palette.signalColor)))
        }
        if !placed.label.isEmpty {
            items.append(.text(TextItem(placed.label, frame: placed.labelFrame, alignment: placed.labelAlignment,
                                        color: palette.signalTextColor)))
        }
        if let number = placed.number {
            items.append(.shape(ShapeItem(.circle(center: number.center, radius: number.radius), fill: palette.signalColor)))
            items.append(.text(TextItem(number.text, centeredAt: number.center, color: palette.sequenceNumberColor)))
        }
        return .group(GroupItem(id: "message-\(index)", role: "message", items: items))
    }

    /// The path of a self-message: a curve (or, with `rightAngles`, three
    /// straight segments) out to `right` and back, with the directions its
    /// ends travel in.
    func selfLoop(_ placed: SequenceLayout.Message, right: Double, width: Double) -> (Path, Point, Point) {
        let m = placed.message
        let start = placed.start, end = placed.end
        if settings.rightAngles {
            let path = Path.polyline([
                start + Point(m.tail.inset(lineWidth: width), 0), Point(right, start.y), Point(right, end.y),
                end + Point(m.head.inset(lineWidth: width), 0),
            ])
            return (path, Point(-1, 0), Point(-1, 0))
        }
        let reach = (right - min(start.x, end.x)) * 4 / 3
        let c1 = Point(start.x + reach, start.y - 2), c2 = Point(end.x + reach, end.y + 2)
        var path = Path()
        path.move(to: start)
        path.curve(to: end, control1: c1, control2: c2)
        // Arrowheads follow the curve's tangents; the curve itself runs to
        // the tip, which the filled head covers.
        return (path, start - c1, end - c2)
    }
}
