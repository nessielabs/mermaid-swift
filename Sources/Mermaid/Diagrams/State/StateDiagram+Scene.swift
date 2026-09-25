extension StateDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        StateSceneBuilder(diagram: self, context: context).build()
    }
}

/// The colors of a state diagram, from mermaid.js' state theme variables
/// and their defaults.
struct StatePalette {
    var stateFill, stateBorder, stateText: Color
    var transition, transitionText, labelBackground: Color
    var compositeBackground, compositeTitleBackground, altBackground, compositeBorder: Color
    var special, background: Color
    var noteFill, noteBorder, noteText: Color

    init(theme: Theme) {
        stateFill = theme.color("stateBkg", default: theme.mainBkg)
        stateBorder = theme.color("stateBorder", default: theme.nodeBorder)
        stateText = theme.color("stateLabelColor", default: theme.primaryTextColor)
        transition = theme.color("transitionColor", default: theme.lineColor)
        transitionText = theme.color("transitionLabelColor", default: theme.textColor)
        labelBackground = theme.edgeLabelBackground
        background = theme.background
        compositeBackground = theme.color("compositeBackground", default: theme.background)
        compositeTitleBackground = theme.color("compositeTitleBackground", default: theme.mainBkg)
        altBackground = theme.color("altBackground",
                                    default: theme.background.isDark ? theme.background.lightened(8) : Color(hex: 0xF0F0F0))
        compositeBorder = theme.color("compositeBorder", default: stateBorder)
        special = theme.color("specialStateColor", default: theme.lineColor)
        noteFill = theme.noteBkgColor
        noteBorder = theme.noteBorderColor
        noteText = theme.noteTextColor
    }
}

/// Lays out a state diagram with the layered layout and draws it.
///
/// Composite states and concurrency regions become layout clusters. Notes
/// attached to a simple state travel with it: the state's layout node is
/// widened symmetrically to hold its note columns, so the state stays at
/// the node's center where transitions attach. Notes on composite states
/// and floating notes are nodes of their own.
struct StateSceneBuilder {
    let diagram: StateDiagram
    let context: RenderContext
    let config: ConfigValue
    let palette: StatePalette
    var theme: Theme { context.theme }

    /// Space between a state's text and its border, across and along.
    let padding: (horizontal: Double, vertical: Double)
    /// Space between a state and its notes.
    let noteGap = 24.0
    let notePadding = Size(12, 10)

    init(diagram: StateDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("state")
        palette = StatePalette(theme: context.theme)
        let base = config["padding"]?.numberValue ?? 8
        padding = (base * 2, base + 2)
    }

    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }

    /// A measured state: its own size (without notes) and its text.
    struct Box {
        var size: Size
        var title: TextBlock
        var body: TextBlock?
    }

    /// Everything measured before layout.
    struct Measured {
        var boxes: [String: Box] = [:]
        var styles: [String: ElementStyle] = [:]
        var compositeTitles: [String: TextBlock] = [:]
        var noteTexts: [TextBlock] = []
        var noteSizes: [Size] = []
        /// Notes beside simple states, by state id.
        var attached: [String: (left: [Int], right: [Int])] = [:]
        /// Notes that are layout nodes of their own.
        var standalone: [Int] = []
        var transitionLabels: [TextBlock?] = []
    }

    func build() -> Scene {
        let measured = measure()
        let layout = LayeredLayout.compute(graph(measured))
        var items = draw(measured, layout: layout)
        // Fit the canvas to what was drawn: the room reserved for notes on
        // the far side of their state is empty, and self-loop labels may
        // reach past the layout's box.
        var size = layout.size
        if let bounds = SceneItem.bounds(of: items) {
            items = items.map { $0.offsetBy(dx: -bounds.minX, dy: -bounds.minY) }
            size = bounds.size
        }
        return DiagramCanvas(context: context, margin: setting("diagramPadding", 8)).scene(content: items, size: size)
    }

    // MARK: - Styles and text

    /// Class definitions (with `default` first) overlaid by inline style.
    func resolvedStyle(_ state: StateDiagram.State) -> ElementStyle {
        var style = diagram.classDefinitions["default"] ?? ElementStyle()
        for name in state.classes { if let def = diagram.classDefinitions[name] { style = style.overlaid(with: def) } }
        return style.overlaid(with: state.style)
    }

    func text(_ raw: String, style: ElementStyle = ElementStyle()) -> TextBlock {
        let font = Font(family: style.fontFamily ?? theme.fontFamily, size: style.fontSize ?? theme.fontSize,
                        bold: style.bold ?? false, italic: style.italic ?? false)
        return TextBlock(LabelParser.parse(raw), font: font, measurer: context.measurer,
                         maxWidth: setting("wrappingWidth", 200))
    }

    /// The direction a container (composite state or region) lays out its
    /// contents in: its declared direction, else its container's, else the
    /// diagram's; nil stands for the top level.
    ///
    /// mermaid.js lays undirected composites out top to bottom whatever the
    /// diagram's direction; inheriting instead keeps `direction LR` at the
    /// top meaning left to right throughout, which is what authors expect.
    func direction(ofContainer id: String?) -> LayeredGraph.Direction {
        var current = id
        var seen: Set<String> = []
        while let container = current, seen.insert(container).inserted {
            if let region = diagram.region(container) {
                if let direction = region.direction { return direction }
                current = region.composite
            } else {
                if let direction = diagram.state(container)?.direction { return direction }
                current = diagram.state(container)?.parent
            }
        }
        return diagram.direction
    }

    // MARK: - Measuring

    func measure() -> Measured {
        var m = Measured()
        for state in diagram.states {
            let style = resolvedStyle(state)
            m.styles[state.id] = style
            if state.isComposite {
                // Every description of a composite is part of its title.
                let title = state.descriptions.isEmpty ? state.id : state.descriptions.joined(separator: "\n")
                m.compositeTitles[state.id] = text(title, style: style)
            } else {
                m.boxes[state.id] = box(for: state, title: text(state.title, style: style), style: style)
            }
        }
        for (i, note) in diagram.notes.enumerated() {
            let block = text(note.text)
            m.noteTexts.append(block)
            m.noteSizes.append(Size(block.width + 2 * notePadding.width, block.height + 2 * notePadding.height))
            if let target = note.target, m.boxes[target] != nil, note.position != .floating {
                if note.position == .left { m.attached[target, default: ([], [])].left.append(i) }
                else { m.attached[target, default: ([], [])].right.append(i) }
            } else {
                m.standalone.append(i)
            }
        }
        m.transitionLabels = diagram.transitions.map { transition in
            guard let label = transition.label else { return nil }
            let block = text(label)
            return block.isEmpty ? nil : block
        }
        return m
    }

    func box(for state: StateDiagram.State, title: TextBlock, style: ElementStyle) -> Box {
        switch state.kind {
        case .start, .end:
            return Box(size: Size(14, 14), title: .empty)
        case .choice:
            return Box(size: Size(28, 28), title: .empty)
        case .fork, .join:
            let long = setting("forkWidth", 70), short = setting("forkHeight", 7)
            let size = direction(ofContainer: state.parent).isHorizontal ? Size(short, long) : Size(long, short)
            return Box(size: size, title: .empty)
        case .state:
            let body = state.body.isEmpty ? nil : text(state.body.joined(separator: "\n"), style: style)
            let width = max(title.width, body?.width ?? 0) + 2 * padding.horizontal
            var height = title.height + 2 * padding.vertical
            if let body { height += body.height + padding.vertical }
            return Box(size: Size(max(width, 50), height), title: title, body: body)
        }
    }

    /// The width of a column of stacked notes and its height.
    func column(_ notes: [Int], sizes: [Size]) -> Size {
        guard !notes.isEmpty else { return .zero }
        let width = notes.map { sizes[$0].width }.max() ?? 0
        let height = notes.map { sizes[$0].height }.reduce(0, +) + Double(notes.count - 1) * 8
        return Size(width, height)
    }

    /// Whether a state's notes go above (`left of`) and below (`right of`)
    /// it rather than beside it. In horizontal flows transitions enter and
    /// leave through a state's sides, so notes turn with the flow, like
    /// fork bars do.
    func notesTurn(_ id: String) -> Bool {
        direction(ofContainer: diagram.state(id)?.parent).isHorizontal
    }

    /// Swaps width and height when `turned`, mapping between screen space
    /// and the frame in which notes always sit left and right.
    static func turn(_ size: Size, _ turned: Bool) -> Size { turned ? Size(size.height, size.width) : size }

    /// The layout size of a simple state with its attached notes.
    func nodeSize(_ id: String, _ m: Measured) -> Size {
        guard let box = m.boxes[id] else { return .zero }
        guard let notes = m.attached[id] else { return box.size }
        let turned = notesTurn(id)
        let sizes = m.noteSizes.map { Self.turn($0, turned) }
        let state = Self.turn(box.size, turned)
        let left = column(notes.left, sizes: sizes), right = column(notes.right, sizes: sizes)
        let side = max(left.width, right.width) + noteGap
        return Self.turn(Size(state.width + 2 * side, max(state.height, left.height, right.height)), turned)
    }

    static func noteNodeID(_ index: Int) -> String { "note:\(index)" }

    // MARK: - Graph

    func graph(_ m: Measured) -> LayeredGraph {
        var graph = LayeredGraph()
        graph.direction = diagram.direction
        graph.nodeSpacing = setting("nodeSpacing", 50)
        graph.rankSpacing = setting("rankSpacing", 50)
        for state in diagram.states where !state.isComposite {
            graph.nodes.append(.init(id: state.id, size: nodeSize(state.id, m), cluster: state.parent))
        }
        for i in m.standalone {
            let note = diagram.notes[i]
            let container = note.target.flatMap { diagram.state($0)?.parent } ?? note.parent
            graph.nodes.append(.init(id: Self.noteNodeID(i), size: m.noteSizes[i], cluster: container))
        }
        for state in diagram.states where state.isComposite {
            let title = m.compositeTitles[state.id] ?? .empty
            // Every container gets a direction, so the layout can lay out
            // composites no transition crosses on their own, as boxes that
            // transitions attach to.
            graph.clusters.append(.init(id: state.id, parent: state.parent, labelSize: Size(title.width, title.height),
                                        direction: direction(ofContainer: state.id)))
        }
        for region in diagram.regions {
            graph.clusters.append(.init(id: region.id, parent: region.composite, direction: direction(ofContainer: region.id)))
        }
        for (i, transition) in diagram.transitions.enumerated() {
            let label = m.transitionLabels[i].map { Size($0.width + 4, $0.height + 2) }
            graph.edges.append(.init(from: transition.from, to: transition.to, labelSize: label))
        }
        for edge in noteEdges(m) { graph.edges.append(.init(from: edge.from, to: edge.to, weight: 0.5)) }
        return graph
    }

    /// Connections between composite states and their standalone notes, in
    /// reading order (a left note precedes its state).
    func noteEdges(_ m: Measured) -> [(note: Int, from: String, to: String)] {
        m.standalone.compactMap { i in
            let note = diagram.notes[i]
            guard let target = note.target else { return nil }
            let node = Self.noteNodeID(i)
            return note.position == .left ? (i, node, target) : (i, target, node)
        }
    }
}
