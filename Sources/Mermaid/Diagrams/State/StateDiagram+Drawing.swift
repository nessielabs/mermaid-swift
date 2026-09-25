extension StateSceneBuilder {
    /// Draws composites (outermost first), then transitions and note links,
    /// then states and notes on top.
    func draw(_ m: Measured, layout: LayeredLayout) -> [SceneItem] {
        let notes = attachedNotes(m, layout: layout)
        return composites(m, layout: layout) + transitions(m, layout: layout) + notes.links
            + states(m, layout: layout) + notes.boxes + standaloneNotes(m, layout: layout)
    }

    /// The frame of a simple state itself, centered in its layout node
    /// (which may be wider to hold notes).
    func stateFrame(_ id: String, _ m: Measured, _ layout: LayeredLayout) -> Rect? {
        guard let node = layout.nodes[id], let box = m.boxes[id] else { return nil }
        return Rect(center: node.center, size: box.size)
    }

    /// The outline transitions attach to.
    func outline(_ id: String, _ m: Measured, _ layout: LayeredLayout) -> [Point]? {
        if let frame = stateFrame(id, m, layout), let state = diagram.state(id) {
            switch state.kind {
            case .start, .end: return EdgeGeometry.ellipseOutline(frame)
            case .choice: return NodeShape.diamond.outline(in: frame)
            case .fork, .join: return EdgeGeometry.rectOutline(frame)
            case .state: return NodeShape.rounded.outline(in: frame)
            }
        }
        return (layout.nodes[id] ?? layout.clusters[id]).map(EdgeGeometry.rectOutline)
    }

    /// The number of composite states enclosing a state.
    func compositeDepth(_ id: String) -> Int {
        var depth = 0
        var current = diagram.state(id)?.parent
        var seen: Set<String> = []
        while let container = current, seen.insert(container).inserted {
            if let region = diagram.region(container) {
                current = region.composite
            } else {
                depth += 1
                current = diagram.state(container)?.parent
            }
        }
        return depth
    }

    // MARK: - Composites

    func composites(_ m: Measured, layout: LayeredLayout) -> [SceneItem] {
        var items: [SceneItem] = []
        let composites = diagram.states.filter(\.isComposite).map { ($0, compositeDepth($0.id)) }
        for (state, depth) in composites.sorted(by: { $0.1 < $1.1 }) {
            guard let frame = layout.clusters[state.id] else { continue }
            let title = m.compositeTitles[state.id] ?? .empty
            let style = m.styles[state.id] ?? ElementStyle()
            let paint = legible(ShapePaint(fill: palette.compositeTitleBackground, stroke: palette.compositeBorder,
                                           text: palette.stateText).applying(style), style: style)
            // Nesting alternates the body color so levels stay distinct.
            let bodyFill = style.fill ?? (depth.isMultiple(of: 2) ? palette.compositeBackground : palette.altBackground)
            let band = title.isEmpty ? 0 : title.height + 8
            items.append(StateShapes.composite(frame: frame, title: title, titleBand: band, paint: paint,
                                               bodyFill: bodyFill, id: state.id))
            let body = Rect(x: frame.minX, y: frame.minY + band, width: frame.width, height: frame.height - band)
            let dash = Stroke(paint.stroke, width: 1, dash: [6, 4])
            items += regionDividers(of: state.id, body: body, layout: layout).map { .shape(ShapeItem($0, stroke: dash)) }
        }
        return items
    }

    /// Dashed lines between the concurrency regions of a composite, across
    /// its whole body, in the gaps between side-by-side (or stacked) regions.
    func regionDividers(of composite: String, body: Rect, layout: LayeredLayout) -> [Path] {
        let frames = diagram.regions.filter { $0.composite == composite }.compactMap { layout.clusters[$0.id] }
        guard frames.count > 1 else { return [] }
        let byX = frames.sorted { $0.midX < $1.midX }
        if zip(byX, byX.dropFirst()).allSatisfy({ $0.maxX <= $1.minX + 0.5 }) {
            return zip(byX, byX.dropFirst()).map { a, b in
                let x = (a.maxX + b.minX) / 2
                return .polyline([Point(x, body.minY), Point(x, body.maxY)])
            }
        }
        let byY = frames.sorted { $0.midY < $1.midY }
        if zip(byY, byY.dropFirst()).allSatisfy({ $0.maxY <= $1.minY + 0.5 }) {
            return zip(byY, byY.dropFirst()).map { a, b in
                let y = (a.maxY + b.minY) / 2
                return .polyline([Point(body.minX, y), Point(body.maxX, y)])
            }
        }
        return []
    }

    /// Leniency beyond mermaid.js: when a style sets a fill but no text
    /// color, and the theme's text would be hard to read on that fill
    /// (light text on a light fill under the dark theme, say), the text
    /// switches to whichever of a dark or light shade contrasts more.
    func legible(_ paint: ShapePaint, style: ElementStyle) -> ShapePaint {
        guard let fill = style.fill, style.textColor == nil, !fill.isClear else { return paint }
        func contrast(_ a: Color, _ b: Color) -> Double {
            (max(a.luminance, b.luminance) + 0.05) / (min(a.luminance, b.luminance) + 0.05)
        }
        guard contrast(paint.text, fill) < 3 else { return paint }
        let dark = Color(hex: 0x222222), light = Color(hex: 0xF5F5F5)
        var paint = paint
        paint.text = contrast(dark, fill) >= contrast(light, fill) ? dark : light
        return paint
    }

    // MARK: - Transitions

    func transitions(_ m: Measured, layout: LayeredLayout) -> [SceneItem] {
        let curve = config["curve"]?.stringValue.flatMap(Curve.init(name:)) ?? .basis
        var items: [SceneItem] = []
        for (i, transition) in diagram.transitions.enumerated() where i < layout.edges.count {
            let route = layout.edges[i]
            items += Connector(route: route.points, sourceOutline: outline(transition.from, m, layout),
                               targetOutline: outline(transition.to, m, layout), curve: curve,
                               color: palette.transition, width: 1, endMarker: .arrow,
                               label: m.transitionLabels[i], labelCenter: route.labelCenter,
                               labelColor: palette.transitionText, labelBackground: palette.labelBackground,
                               background: palette.background, id: "transition-\(i)").items()
        }
        // Links between composite states and their notes follow the transitions.
        for (k, edge) in noteEdges(m).enumerated() {
            let e = diagram.transitions.count + k
            guard e < layout.edges.count else { continue }
            items += Connector(route: layout.edges[e].points, sourceOutline: outline(edge.from, m, layout),
                               targetOutline: outline(edge.to, m, layout), curve: curve, color: palette.transition,
                               width: 1, dash: [5, 5], labelColor: palette.transitionText,
                               background: palette.background, id: "note-link-\(edge.note)").items()
        }
        return items
    }

    // MARK: - States

    func states(_ m: Measured, layout: LayeredLayout) -> [SceneItem] {
        var items: [SceneItem] = []
        for state in diagram.states where !state.isComposite {
            guard let frame = stateFrame(state.id, m, layout), let box = m.boxes[state.id] else { continue }
            let style = m.styles[state.id] ?? ElementStyle()
            let paint = legible(ShapePaint(fill: palette.stateFill, stroke: palette.stateBorder, text: palette.stateText)
                .applying(style), style: style)
            switch state.kind {
            case .start:
                items.append(StateShapes.start(frame: frame, color: style.fill ?? palette.special, id: state.id))
            case .end:
                items.append(StateShapes.end(frame: frame, color: style.fill ?? palette.special,
                                             background: palette.background, id: state.id))
            case .fork, .join:
                items.append(StateShapes.bar(frame: frame, color: style.fill ?? palette.special, id: state.id))
            case .choice:
                items.append(ShapeRenderer.items(.diamond, frame: frame, label: nil, paint: paint, id: state.id, role: "state-choice"))
            case .state:
                items.append(StateShapes.stateBox(frame: frame, title: box.title, body: box.body, paint: paint,
                                                  padding: padding.vertical, id: state.id))
            }
        }
        return items
    }

    // MARK: - Notes

    var notePaint: ShapePaint { ShapePaint(fill: palette.noteFill, stroke: palette.noteBorder, text: palette.noteText) }

    /// Notes beside simple states, stacked in columns to the state's left and
    /// right, with the dashed links that tie them to the state.
    func attachedNotes(_ m: Measured, layout: LayeredLayout) -> (links: [SceneItem], boxes: [SceneItem]) {
        var links: [SceneItem] = [], boxes: [SceneItem] = []
        let dash = Stroke(palette.transition, width: 1, dash: [5, 5])
        for state in diagram.states {
            guard let sides = m.attached[state.id], let frame = stateFrame(state.id, m, layout) else { continue }
            for (notes, right) in [(sides.right, true), (sides.left, false)] where !notes.isEmpty {
                var y = frame.midY - column(notes, sizes: m.noteSizes).height / 2
                for i in notes {
                    let size = m.noteSizes[i]
                    let x = right ? frame.maxX + noteGap : frame.minX - noteGap - size.width
                    let rect = Rect(x: x, y: y, width: size.width, height: size.height)
                    y += size.height + 8
                    boxes.append(StateShapes.note(frame: rect, text: m.noteTexts[i], paint: notePaint,
                                                  id: diagram.notes[i].id))
                    // A level link where the note and state overlap vertically.
                    let level = min(max(rect.midY, frame.minY + 4), frame.maxY - 4)
                    let from = Point(right ? frame.maxX : frame.minX, rect.minY <= level && level <= rect.maxY ? level : frame.midY)
                    let to = Point(right ? rect.minX : rect.maxX, rect.minY <= level && level <= rect.maxY ? level : rect.midY)
                    links.append(.shape(ShapeItem(.polyline([from, to]), stroke: dash)))
                }
            }
        }
        return (links, boxes)
    }

    func standaloneNotes(_ m: Measured, layout: LayeredLayout) -> [SceneItem] {
        m.standalone.compactMap { i in
            layout.nodes[Self.noteNodeID(i)].map {
                StateShapes.note(frame: $0, text: m.noteTexts[i], paint: notePaint, id: diagram.notes[i].id)
            }
        }
    }
}
