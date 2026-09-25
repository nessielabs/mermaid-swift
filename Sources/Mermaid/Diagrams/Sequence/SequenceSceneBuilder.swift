/// Turns a `SequenceLayout` into scene items, back to front: boxes, `rect`
/// highlights, lifelines, frames, activations, messages, notes, heads.
struct SequenceSceneBuilder {
    let layout: SequenceLayout
    let settings: SequenceSettings
    let palette: SequencePalette

    static let lineWidth = 1.5

    func items() -> [SceneItem] {
        var items: [SceneItem] = layout.groups.map(group)
        let frames = layout.frames.sorted { $0.depth < $1.depth }
        items += frames.filter { $0.kind == .rect }.map { frame in
            .shape(ShapeItem(.rect(frame.frame), fill: frame.fill ?? palette.rectBkgColor))
        }
        items += layout.actors.map(lifeline)
        items += frames.filter { $0.kind != .rect }.map(self.frame)
        items += layout.activations.sorted { $0.depth < $1.depth }.map { activation in
            .shape(ShapeItem(.rect(activation.frame), fill: palette.activationBkgColor, stroke: Stroke(palette.activationBorderColor)))
        }
        items += layout.messages.enumerated().map { message($1, index: $0) }
        items += layout.notes.map(note)
        for actor in layout.actors {
            items.append(SequenceHeadRenderer.items(actor, frame: actor.head, palette: palette, role: "actor"))
            if let foot = actor.foot {
                items.append(SequenceHeadRenderer.items(actor, frame: foot, palette: palette, role: "actor-bottom"))
            }
            if actor.isDestroyed { items.append(cross(at: Point(actor.x, actor.lifelineBottom))) }
        }
        return items
    }

    func group(_ group: SequenceLayout.Group) -> SceneItem {
        var items: [SceneItem] = [.shape(ShapeItem(.rect(group.frame), fill: group.color, stroke: Stroke(palette.groupBorder)))]
        if let title = group.title {
            items.append(.text(TextItem(title, frame: group.titleFrame, color: palette.groupTextColor)))
        }
        return .group(GroupItem(role: "box", items: items))
    }

    /// The lifeline, interrupted where a message label or frame condition
    /// crosses it so the text stays readable.
    func lifeline(_ actor: SequenceLayout.Actor) -> SceneItem {
        var blockers = layout.messages.filter { !$0.isSelf && !$0.label.isEmpty }.map(\.labelFrame)
        for frame in layout.frames {
            if frame.condition != nil { blockers.append(textExtent(frame.conditionFrame, width: frame.condition?.width ?? 0)) }
            for divider in frame.dividers where divider.label != nil {
                blockers.append(textExtent(divider.labelFrame, width: divider.label?.width ?? 0))
            }
        }
        let gaps = blockers
            .filter { $0.minX - 2 < actor.x && actor.x < $0.maxX + 2 }
            .map { ($0.minY - 2, $0.maxY + 2) }
            .sorted { $0.0 < $1.0 }
        var path = Path()
        var y = actor.lifelineTop
        for (start, end) in gaps where end > y && start < actor.lifelineBottom {
            if start > y { path.append(.polyline([Point(actor.x, y), Point(actor.x, start)])) }
            y = max(y, end)
        }
        if y < actor.lifelineBottom { path.append(.polyline([Point(actor.x, y), Point(actor.x, actor.lifelineBottom)])) }
        return .group(GroupItem(id: "lifeline-\(actor.id)", role: "lifeline",
                                items: [.shape(ShapeItem(path, stroke: Stroke(palette.actorLineColor, width: 1)))]))
    }

    /// The part of a centered text box that the text covers.
    func textExtent(_ frame: Rect, width: Double) -> Rect {
        Rect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height)
    }

    func frame(_ frame: SequenceLayout.Frame) -> SceneItem {
        let dashed = Stroke(palette.labelBoxBorderColor, width: Self.lineWidth, dash: [4, 3])
        let r = frame.frame, tag = frame.tagFrame
        var items: [SceneItem] = [.shape(ShapeItem(.rect(r), stroke: dashed))]
        let corner = min(8, tag.height / 2)
        let pentagon = Path.polygon([
            tag.origin, Point(tag.maxX, tag.minY), Point(tag.maxX, tag.maxY - corner),
            Point(tag.maxX - corner, tag.maxY), Point(tag.minX, tag.maxY),
        ])
        items.append(.shape(ShapeItem(pentagon, fill: palette.labelBoxBkgColor, stroke: Stroke(palette.labelBoxBorderColor, width: 1))))
        items.append(.text(TextItem(frame.tag, centeredAt: Point(tag.midX - corner / 4, tag.midY), color: palette.labelTextColor)))
        if let condition = frame.condition {
            items.append(.text(TextItem(condition, frame: frame.conditionFrame, color: palette.loopTextColor)))
        }
        for divider in frame.dividers {
            items.append(.shape(ShapeItem(.polyline([Point(r.minX, divider.y), Point(r.maxX, divider.y)]), stroke: dashed)))
            if let label = divider.label {
                items.append(.text(TextItem(label, frame: divider.labelFrame, color: palette.loopTextColor)))
            }
        }
        return .group(GroupItem(role: frame.kind.rawValue, items: items))
    }

    func note(_ note: SequenceLayout.Note) -> SceneItem {
        let textFrame = note.frame.insetBy(dx: settings.noteMargin, dy: settings.noteMargin)
        return .group(GroupItem(role: "note", items: [
            .shape(ShapeItem(.rect(note.frame), fill: palette.noteBkgColor, stroke: Stroke(palette.noteBorderColor))),
            .text(TextItem(note.text, frame: textFrame, alignment: note.alignment, color: palette.noteTextColor)),
        ]))
    }

    /// The destruction mark at the end of a destroyed lifeline.
    func cross(at center: Point) -> SceneItem {
        let h = SequenceLayoutBuilder.crossSize / 2
        var path = Path.polyline([Point(center.x - h, center.y - h), Point(center.x + h, center.y + h)])
        path.append(.polyline([Point(center.x - h, center.y + h), Point(center.x + h, center.y - h)]))
        return .shape(ShapeItem(path, stroke: Stroke(palette.signalColor, width: 2, cap: .round)))
    }
}
