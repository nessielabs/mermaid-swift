/// Draws the shapes of a state diagram: state boxes (with an optional
/// description section), pseudo-states, notes and composite frames.
enum StateShapes {
    /// Corner radius of state boxes and composite frames (mermaid.js'
    /// `state.radius`).
    static let cornerRadius = 5.0

    /// A rounded state box. With a `body`, the title sits in a band at the
    /// top, separated from the description lines by a rule.
    static func stateBox(frame: Rect, title: TextBlock, body: TextBlock?, paint: ShapePaint,
                         padding: Double, id: String) -> SceneItem {
        let stroke = paint.strokeWidth > 0 ? Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash) : nil
        var items: [SceneItem] = [
            .shape(ShapeItem(.rect(frame, cornerRadius: cornerRadius), fill: paint.fill, stroke: stroke, opacity: paint.opacity)),
        ]
        if let body, !body.isEmpty {
            // The rule splits the box into a title band and a body band, each
            // with the text centered and 1.5 × padding of vertical space.
            let ruleY = frame.minY + title.height + padding * 1.5
            items.append(.text(TextItem(title, centeredAt: Point(frame.midX, (frame.minY + ruleY) / 2), color: paint.text)))
            items.append(.shape(ShapeItem(.polyline([Point(frame.minX, ruleY), Point(frame.maxX, ruleY)]),
                                          stroke: Stroke(paint.stroke, width: max(paint.strokeWidth, 1)),
                                          opacity: paint.opacity)))
            items.append(.text(TextItem(body, centeredAt: Point(frame.midX, (ruleY + frame.maxY) / 2), color: paint.text)))
        } else {
            items.append(.text(TextItem(title, centeredAt: frame.center, color: paint.text)))
        }
        return .group(GroupItem(id: id, role: "state", items: items))
    }

    /// The filled circle of a start state.
    static func start(frame: Rect, color: Color, id: String) -> SceneItem {
        .group(GroupItem(id: id, role: "state-start", items: [
            .shape(ShapeItem(.ellipse(in: frame), fill: color, stroke: Stroke(color, width: 1))),
        ]))
    }

    /// The bull's-eye of an end state: a ring around a filled disc.
    static func end(frame: Rect, color: Color, background: Color, id: String) -> SceneItem {
        let inner = frame.insetBy(dx: frame.width * 0.22, dy: frame.height * 0.22)
        return .group(GroupItem(id: id, role: "state-end", items: [
            .shape(ShapeItem(.ellipse(in: frame.insetBy(dx: 0.75, dy: 0.75)), fill: background,
                             stroke: Stroke(color, width: 1.5))),
            .shape(ShapeItem(.ellipse(in: inner), fill: color)),
        ]))
    }

    /// The solid bar of a fork or join.
    static func bar(frame: Rect, color: Color, id: String) -> SceneItem {
        .group(GroupItem(id: id, role: "state-fork", items: [
            .shape(ShapeItem(.rect(frame, cornerRadius: min(frame.width, frame.height) / 3), fill: color)),
        ]))
    }

    /// A note: a square-cornered box with the note colors.
    static func note(frame: Rect, text: TextBlock, paint: ShapePaint, id: String) -> SceneItem {
        .group(GroupItem(id: id, role: "note", items: [
            .shape(ShapeItem(.rect(frame), fill: paint.fill, stroke: Stroke(paint.stroke, width: paint.strokeWidth))),
            .text(TextItem(text, centeredAt: frame.center, color: paint.text)),
        ]))
    }

    /// A composite state's frame: a rounded box whose top band, filled with
    /// `paint.fill`, holds the title above a body filled with `bodyFill`.
    static func composite(frame: Rect, title: TextBlock, titleBand: Double, paint: ShapePaint,
                          bodyFill: Color, id: String) -> SceneItem {
        let stroke = Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash)
        let band = min(titleBand, frame.height)
        let body = Rect(x: frame.minX, y: frame.minY + band, width: frame.width, height: frame.height - band)
        var items: [SceneItem] = [
            .shape(ShapeItem(.rect(frame, cornerRadius: cornerRadius), fill: paint.fill, stroke: stroke, opacity: paint.opacity)),
        ]
        if body.height > 0 {
            items.append(.shape(ShapeItem(roundedBottom(body, radius: cornerRadius), fill: bodyFill, stroke: stroke,
                                          opacity: paint.opacity)))
        }
        if !title.isEmpty {
            items.append(.text(TextItem(title, centeredAt: Point(frame.midX, frame.minY + band / 2), color: paint.text)))
        }
        return .group(GroupItem(id: id, role: "composite", items: items))
    }

    /// A rectangle with square top corners and rounded bottom corners.
    static func roundedBottom(_ r: Rect, radius: Double) -> Path {
        let k = min(radius, r.width / 2, r.height)
        var path = Path()
        path.move(to: r.origin)
        path.line(to: Point(r.maxX, r.minY))
        path.line(to: Point(r.maxX, r.maxY - k))
        path.appendArc(center: Point(r.maxX - k, r.maxY - k), radius: k, from: 0, to: 90, connect: true)
        path.line(to: Point(r.minX + k, r.maxY))
        path.appendArc(center: Point(r.minX + k, r.maxY - k), radius: k, from: 90, to: 180, connect: true)
        path.close()
        return path
    }
}
