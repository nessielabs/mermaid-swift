extension ClassDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        ClassSceneBuilder(diagram: self, context: context).build()
    }
}

/// Lays a class diagram out with the layered layout and draws it: class
/// boxes, notes, lollipop interfaces, namespaces as clusters, and
/// relations with their end markers, labels and cardinalities.
struct ClassSceneBuilder {
    let diagram: ClassDiagram
    let context: RenderContext
    let config: ConfigValue
    var theme: Theme { context.theme }

    init(diagram: ClassDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("class")
    }

    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }

    /// Diameter of a lollipop interface's circle.
    static let lollipopDiameter = 14.0

    /// Everything measured before layout.
    struct Measured {
        var boxes: [String: ClassBox] = [:]
        var styles: [String: ElementStyle] = [:]
        var notes: [String: TextBlock] = [:]
        var interfaces: [String: TextBlock] = [:]
        var namespaceTitles: [String: TextBlock] = [:]
        var relationLabels: [TextBlock?] = []
        /// Cardinality text at the `from` and `to` end of each relation.
        var cardinalities: [(from: TextBlock?, to: TextBlock?)] = []
    }

    /// Class definitions (with `default` first) overlaid by inline style.
    func resolvedStyle(_ item: ClassDiagram.Class) -> ElementStyle {
        var style = diagram.classDefinitions["default"] ?? ElementStyle()
        for name in item.cssClasses { if let def = diagram.classDefinitions[name] { style = style.overlaid(with: def) } }
        return style.overlaid(with: item.style)
    }

    func font(_ style: ElementStyle) -> Font {
        Font(family: style.fontFamily ?? theme.fontFamily, size: style.fontSize ?? theme.fontSize,
             bold: style.bold ?? false, italic: style.italic ?? false)
    }

    /// The namespace each class or note is drawn in. In compact mode
    /// (`hierarchicalNamespaces: false`) only declared namespaces are drawn,
    /// so members of implicit ancestors move to the nearest declared one.
    func drawnNamespace(_ id: String?) -> String? {
        guard !hierarchical else { return id }
        var current = id
        while let name = current, let namespace = diagram.namespaces.first(where: { $0.id == name }) {
            if namespace.isExplicit { return name }
            current = namespace.parent
        }
        return nil
    }

    var hierarchical: Bool { config["hierarchicalNamespaces"]?.boolValue ?? true }

    /// The namespaces drawn as clusters, with their drawn parent.
    var drawnNamespaces: [(namespace: ClassDiagram.Namespace, parent: String?)] {
        diagram.namespaces.compactMap { namespace in
            if hierarchical { return (namespace, namespace.parent) }
            return namespace.isExplicit ? (namespace, nil) : nil
        }
    }

    func build() -> Scene {
        let measured = measure()
        let graph = makeGraph(measured)
        let layout = LayeredLayout.compute(graph)
        var items = clusterItems(layout, measured)
        items += relationItems(layout, measured)
        items += nodeItems(layout, measured)
        return DiagramCanvas(context: context, margin: setting("diagramPadding", 8))
            .scene(content: items, size: layout.size)
    }

    func measure() -> Measured {
        var measured = Measured()
        let padding = setting("padding", 12)
        let margin = setting("dividerMargin", 10) / 2 + 3
        let hideEmpty = config["hideEmptyMembersBox"]?.boolValue ?? false
        for item in diagram.classes {
            let style = resolvedStyle(item)
            measured.styles[item.id] = style
            measured.boxes[item.id] = ClassBox(item, font: font(style), measurer: context.measurer,
                                               padding: padding, margin: margin, hideEmptyMembers: hideEmpty)
        }
        for note in diagram.notes {
            measured.notes[note.id] = context.label(note.text.replacingOccurrences(of: "\\n", with: "<br>"))
        }
        for interface in diagram.interfaces {
            measured.interfaces[interface.id] = context.text(RichText(plain: interface.label))
        }
        for (namespace, _) in drawnNamespaces {
            let title = hierarchical ? namespace.label : namespace.id
            measured.namespaceTitles[namespace.id] = context.text(RichText(plain: title), bold: true)
        }
        measured.relationLabels = diagram.relations.map { relation in
            guard let label = relation.label else { return nil }
            let block = context.label(label)
            return block.isEmpty ? nil : block
        }
        func cardinality(_ text: String?) -> TextBlock? {
            guard let text, !text.isEmpty else { return nil }
            return context.label(text)
        }
        measured.cardinalities = diagram.relations.map { (cardinality($0.fromCardinality), cardinality($0.toCardinality)) }
        return measured
    }
}
