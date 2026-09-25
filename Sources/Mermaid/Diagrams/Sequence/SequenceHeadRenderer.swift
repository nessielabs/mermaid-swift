/// Draws participant heads: shapes that hold their label, or glyphs
/// (stick figure, boundary, control, entity) with the label underneath.
enum SequenceHeadRenderer {
    static func items(_ actor: SequenceLayout.Actor, frame: Rect, palette: SequencePalette, role: String) -> SceneItem {
        let paint = ShapePaint(fill: palette.actorBkg, stroke: palette.actorBorder, text: palette.actorTextColor)
        switch actor.kind {
        case .participant:
            let items: [SceneItem] = [
                .shape(ShapeItem(.rect(frame, cornerRadius: 3), fill: paint.fill, stroke: Stroke(paint.stroke))),
                .text(TextItem(actor.label, centeredAt: frame.center, color: paint.text)),
            ]
            return .group(GroupItem(id: actor.id, role: role, items: items))
        case .database:
            return ShapeRenderer.items(.cylinder, frame: frame, label: actor.label, paint: paint, id: actor.id, role: role)
        case .collections:
            return ShapeRenderer.items(.stackedRect, frame: frame, label: actor.label, paint: paint, id: actor.id, role: role)
        case .queue:
            return ShapeRenderer.items(.horizontalCylinder, frame: frame, label: actor.label, paint: paint, id: actor.id, role: role)
        case .actor, .boundary, .control, .entity:
            let glyph = Rect(x: actor.x - SequenceLayout.glyphSize.width / 2, y: frame.minY,
                             width: SequenceLayout.glyphSize.width, height: SequenceLayout.glyphSize.height)
            var items = glyphItems(actor.kind, in: glyph, palette: palette)
            let labelCenter = Point(actor.x, glyph.maxY + SequenceLayout.glyphGap + actor.label.height / 2)
            items.append(.text(TextItem(actor.label, centeredAt: labelCenter, color: palette.actorTextColor)))
            return .group(GroupItem(id: actor.id, role: role, items: items))
        }
    }

    /// The glyph of an icon-style participant, drawn in a 40×40 box.
    static func glyphItems(_ kind: SequenceDiagram.ParticipantKind, in box: Rect, palette: SequencePalette) -> [SceneItem] {
        let stroke = Stroke(palette.glyphColor, width: 2, cap: .round, join: .round)
        let cx = box.midX, top = box.minY
        func circle(_ center: Point, _ radius: Double) -> SceneItem {
            .shape(ShapeItem(.circle(center: center, radius: radius), fill: palette.actorBkg, stroke: stroke))
        }
        func lines(_ segments: [[Point]]) -> SceneItem {
            var path = Path()
            for segment in segments { path.append(.polyline(segment)) }
            return .shape(ShapeItem(path, stroke: stroke))
        }
        switch kind {
        case .actor:
            return [
                lines([
                    [Point(cx, top + 15), Point(cx, top + 28)],
                    [Point(cx - 12, top + 20), Point(cx + 12, top + 20)],
                    [Point(cx - 10, top + 39), Point(cx, top + 28), Point(cx + 10, top + 39)],
                ]),
                circle(Point(cx, top + 8), 7),
            ]
        case .boundary:
            return [
                lines([[Point(cx - 17, top + 6), Point(cx - 17, top + 34)], [Point(cx - 17, top + 20), Point(cx - 9, top + 20)]]),
                circle(Point(cx + 5, top + 20), 14),
            ]
        case .control:
            return [
                circle(Point(cx, top + 22), 14),
                lines([[Point(cx + 5, top + 3), Point(cx - 1, top + 8), Point(cx + 5, top + 13)]]),
            ]
        case .entity:
            return [
                circle(Point(cx, top + 18), 14),
                lines([[Point(cx - 15, top + 36), Point(cx + 15, top + 36)]]),
            ]
        default:
            return []
        }
    }
}
