extension ClassSceneBuilder {
    /// Namespace boxes, outermost first so nested ones draw on top.
    func clusterItems(_ layout: LayeredLayout, _ measured: Measured) -> [SceneItem] {
        let parents = Dictionary(drawnNamespaces.map { ($0.namespace.id, $0.parent) }, uniquingKeysWith: { a, _ in a })
        func depth(_ id: String) -> Int {
            var d = 0, current = parents[id] ?? nil
            while let parent = current { d += 1; current = parents[parent] ?? nil }
            return d
        }
        return drawnNamespaces.map(\.namespace.id).sorted { depth($0) < depth($1) }.compactMap { id in
            guard let frame = layout.clusters[id] else { return nil }
            var items: [SceneItem] = [.shape(ShapeItem(.rect(frame), fill: theme.clusterBkg,
                                                       stroke: Stroke(theme.clusterBorder, width: 1)))]
            if let title = measured.namespaceTitles[id] {
                items.append(.text(TextItem(title, centeredAt: Point(frame.midX, frame.minY + 4 + title.height / 2),
                                            color: theme.titleColor)))
            }
            return .group(GroupItem(id: id, role: "namespace", items: items))
        }
    }

    /// Class boxes, notes, and lollipop interfaces.
    func nodeItems(_ layout: LayeredLayout, _ measured: Measured) -> [SceneItem] {
        var items: [SceneItem] = []
        let basePaint = ShapePaint(fill: theme.mainBkg, stroke: theme.nodeBorder,
                                   text: theme.color("classText", default: theme.primaryTextColor))
        for item in diagram.classes {
            guard let frame = layout.nodes[item.id], let box = measured.boxes[item.id] else { continue }
            let paint = basePaint.applying(measured.styles[item.id] ?? ElementStyle())
            items.append(box.items(in: frame, paint: paint, id: item.id))
        }
        for note in diagram.notes {
            guard let frame = layout.nodes[note.id], let text = measured.notes[note.id] else { continue }
            let textFrame = frame.insetBy(dx: Self.notePadding.width, dy: Self.notePadding.height)
            items.append(.group(GroupItem(id: note.id, role: "note", items: [
                .shape(ShapeItem(.rect(frame), fill: theme.noteBkgColor, stroke: Stroke(theme.noteBorderColor, width: 1))),
                .text(TextItem(text, frame: textFrame, alignment: .leading, color: theme.noteTextColor)),
            ])))
        }
        for interface in diagram.interfaces {
            guard let frame = layout.nodes[interface.id] else { continue }
            items.append(interfaceItem(interface, frame: frame, owner: layout.nodes[interface.classID],
                                       label: measured.interfaces[interface.id] ?? .empty))
        }
        return items
    }

    /// A lollipop: a hollow circle with the interface name on the side
    /// facing away from the class it is attached to.
    func interfaceItem(_ interface: ClassDiagram.Interface, frame: Rect, owner: Rect?, label: TextBlock) -> SceneItem {
        let d = Self.lollipopDiameter
        let center = frame.center
        let away = owner.map { center - $0.center } ?? Point(0, -1)
        var labelCenter: Point
        if diagram.direction.isHorizontal {
            let side: Double = away.x >= 0 ? 1 : -1
            labelCenter = Point(center.x + side * (d / 2 + 4 + label.width / 2), center.y)
        } else {
            let side: Double = away.y >= 0 ? 1 : -1
            labelCenter = Point(center.x, center.y + side * (d / 2 + 2 + label.height / 2))
        }
        if label.isEmpty { labelCenter = center }
        return .group(GroupItem(id: interface.id, role: "interface", items: [
            .shape(ShapeItem(.circle(center: center, radius: d / 2), fill: theme.background,
                             stroke: Stroke(theme.lineColor, width: 1))),
            .text(TextItem(label, centeredAt: labelCenter, color: theme.textColor)),
        ]))
    }
}
