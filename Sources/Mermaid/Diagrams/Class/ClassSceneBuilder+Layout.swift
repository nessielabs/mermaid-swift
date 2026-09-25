extension ClassSceneBuilder {
    /// Padding around note text.
    static let notePadding = Size(10, 8)

    /// The layered graph for the diagram: classes, notes and interfaces as
    /// nodes, namespaces as clusters, then relation edges followed by one
    /// edge per attached note.
    func makeGraph(_ measured: Measured) -> LayeredGraph {
        var graph = LayeredGraph()
        graph.direction = diagram.direction
        graph.nodeSpacing = setting("nodeSpacing", 50)
        graph.rankSpacing = setting("rankSpacing", 50)
        for (namespace, parent) in drawnNamespaces {
            let title = measured.namespaceTitles[namespace.id].map { Size($0.width, $0.height) } ?? .zero
            graph.clusters.append(.init(id: namespace.id, parent: parent, labelSize: title))
        }
        for item in diagram.classes {
            let size = measured.boxes[item.id]?.size ?? .zero
            graph.nodes.append(.init(id: item.id, size: size, cluster: drawnNamespace(item.namespace)))
        }
        for note in diagram.notes {
            let text = measured.notes[note.id] ?? .empty
            let size = Size(text.width + 2 * Self.notePadding.width, text.height + 2 * Self.notePadding.height)
            graph.nodes.append(.init(id: note.id, size: size, cluster: drawnNamespace(note.namespace)))
        }
        for interface in diagram.interfaces {
            let owner = diagram.class(interface.classID)?.namespace
            graph.nodes.append(.init(id: interface.id, size: interfaceNodeSize(measured.interfaces[interface.id]),
                                     cluster: drawnNamespace(owner)))
        }
        for (i, relation) in diagram.relations.enumerated() {
            graph.edges.append(.init(from: relation.from, to: relation.to,
                                     labelSize: labelSlot(relation, measured.relationLabels[i], measured.cardinalities[i],
                                                          rankSpacing: graph.rankSpacing)))
        }
        for (note, target) in attachedNotes {
            graph.edges.append(.init(from: note.id, to: target))
        }
        return graph
    }

    /// The layout slot for a relation's label. Cardinalities sit beside the
    /// line near each end, so an edge that has them gets a slot stretched
    /// along the flow until both ends leave room for the end decoration and
    /// the cardinality text before the label begins.
    func labelSlot(_ relation: ClassDiagram.Relation, _ label: TextBlock?,
                   _ cardinalities: (from: TextBlock?, to: TextBlock?), rankSpacing: Double) -> Size? {
        let horizontal = diagram.direction.isHorizontal
        var slot = label.map { Size($0.width + 4, $0.height + 2) }
        func reach(_ block: TextBlock?, _ end: ClassDiagram.RelationEnd) -> Double {
            guard let block else { return 0 }
            return Self.decorationLength(end) + 3 + (horizontal ? block.width : block.height) + 6
        }
        let needed = max(reach(cardinalities.from, relation.fromEnd), reach(cardinalities.to, relation.toEnd))
        // Labeled graphs split each rank gap in two around the label slot.
        let extra = max(0, needed - rankSpacing / 2)
        guard extra > 0 else { return slot }
        var size = slot ?? Size(1, 1)
        if horizontal { size.width += 2 * extra } else { size.height += 2 * extra }
        slot = size
        return slot
    }

    /// Notes attached to a class that exists, with that class's id.
    var attachedNotes: [(note: ClassDiagram.Note, target: String)] {
        diagram.notes.compactMap { note in
            guard let target = note.target, diagram.class(target) != nil else { return nil }
            return (note, target)
        }
    }

    /// An interface node holds its circle at the center and reserves room
    /// for the name on both sides along the flow; the name is drawn on the
    /// side facing away from the class.
    func interfaceNodeSize(_ label: TextBlock?) -> Size {
        let d = Self.lollipopDiameter
        let label = label ?? .empty
        if diagram.direction.isHorizontal {
            return Size(d + 2 * (label.width + 4), max(d, label.height))
        }
        return Size(max(d, label.width), d + 2 * (label.height + 2))
    }

    /// The outline edges clip against: class and note boxes, or an
    /// interface's circle.
    func outline(_ id: String, _ layout: LayeredLayout) -> [Point]? {
        guard let frame = layout.nodes[id] else { return nil }
        if diagram.interfaces.contains(where: { $0.id == id }) {
            let d = Self.lollipopDiameter
            return EdgeGeometry.ellipseOutline(Rect(center: frame.center, size: Size(d, d)))
        }
        return EdgeGeometry.rectOutline(frame)
    }

    static func marker(_ end: ClassDiagram.RelationEnd) -> Marker {
        switch end {
        case .none, .lollipop: return .none
        case .inheritance: return .hollowTriangle
        case .composition: return .filledDiamond
        case .aggregation: return .hollowDiamond
        case .association: return .arrow
        }
    }

    /// How far a decoration reaches back from the end of its edge, so
    /// cardinality labels clear it.
    static func decorationLength(_ end: ClassDiagram.RelationEnd) -> Double {
        switch end {
        case .none: return 0
        case .association: return 10
        case .inheritance: return 14
        case .composition, .aggregation: return 16
        case .lollipop: return lollipopDiameter
        }
    }
}
