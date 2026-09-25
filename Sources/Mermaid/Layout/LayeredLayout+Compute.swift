extension LayeredLayout {
    /// Lays out a graph in layers along its direction.
    public static func compute(_ graph: LayeredGraph) -> LayeredLayout {
        if let collapsed = layoutCollapsingDirectedClusters(graph) { return collapsed }
        var computation = LayeredComputation(graph)
        return computation.run()
    }
}

/// Runs the layout phases and maps results back to the graph's direction.
struct LayeredComputation {
    let graph: LayeredGraph
    let horizontal: Bool
    var engine = LayeredEngine()
    var nodeVertex: [String: Int] = [:]
    var clusterIndex: [String: Int] = [:]
    /// Screen-top title inset per cluster, applied on the rank or order axis
    /// depending on direction.
    var titleInsets: [Double] = []

    init(_ graph: LayeredGraph) {
        self.graph = graph
        horizontal = graph.direction.isHorizontal
    }

    /// Converts a screen-space size to the engine's (across, along) extents.
    func canonical(_ size: Size) -> (across: Double, along: Double) {
        horizontal ? (size.height, size.width) : (size.width, size.height)
    }

    mutating func run() -> LayeredLayout {
        for (i, cluster) in graph.clusters.enumerated() { clusterIndex[cluster.id] = i }
        engine.clusterParent = graph.clusters.map { $0.parent.flatMap { clusterIndex[$0] } }
        engine.clusterLabels = graph.clusters.map { cluster in
            let extents = canonical(cluster.labelSize)
            return horizontal ? Size(0, 0) : Size(extents.across, 0)
        }
        titleInsets = graph.clusters.map { $0.labelSize.height > 0 ? $0.labelSize.height + 4 : 0 }

        for (i, node) in graph.nodes.enumerated() {
            let extents = canonical(node.size)
            nodeVertex[node.id] = engine.vertices.count
            engine.vertices.append(.init(kind: .real(i), width: extents.across, height: extents.along,
                                         cluster: node.cluster.flatMap { clusterIndex[$0] }))
        }
        // An empty cluster still needs a box: give it an invisible member.
        var placeholders: [Int: Int] = [:]
        for (i, cluster) in graph.clusters.enumerated() where representative(cluster.id) == nil {
            placeholders[i] = engine.vertices.count
            let extents = canonical(Size(max(cluster.labelSize.width, 40), 20))
            engine.vertices.append(.init(kind: .real(-1), width: extents.across, height: extents.along, cluster: i))
        }

        let hasLabels = graph.edges.contains { $0.labelSize != nil }
        let scale = hasLabels ? 2 : 1
        var labelSizes: [Int: Size] = [:]
        var loops: [Int] = []
        for (e, edge) in graph.edges.enumerated() {
            guard let from = endpoint(edge.from, placeholders), let to = endpoint(edge.to, placeholders) else { continue }
            if from == to { loops.append(e); continue }
            if let label = edge.labelSize {
                let extents = canonical(label)
                labelSizes[e] = Size(extents.across, extents.along)
            }
            engine.arcs.append(.init(from: from, to: to, minLength: max(1, edge.minLength) * scale,
                                     weight: edge.weight, edge: e))
        }
        widenForLoops(loops)

        engine.removeCycles()
        engine.assignRanks()
        let (segments, chains) = engine.normalize(labelSizes: labelSizes, edgeCount: graph.edges.count)
        let spans = engine.addClusterBorders()
        let layers = engine.orderVertices(segments: segments)
        var spacing = LayeredEngine.Spacing(node: graph.nodeSpacing, rank: graph.rankSpacing / Double(scale),
                                            cluster: graph.clusterPadding)
        spacing.node = horizontal ? graph.nodeSpacing * 0.6 + 10 : graph.nodeSpacing
        if horizontal { engine.leadInsets = titleInsets }
        if !engine.assignX(layers: layers, segments: segments, spacing: spacing, useClusters: true) {
            _ = engine.assignX(layers: layers, segments: segments, spacing: spacing, useClusters: false)
        }
        assignY(layers: layers, spans: spans, spacing: spacing, segments: segments)
        return output(chains: chains, loops: loops, spans: spans)
    }

    func representative(_ clusterID: String) -> Int? {
        guard let c = clusterIndex[clusterID] else { return nil }
        return engine.vertices.indices.first { v in
            guard case .real(let n) = engine.vertices[v].kind, n >= 0 else { return false }
            return engine.ancestry(engine.vertices[v].cluster).contains(c)
        }
    }

    func endpoint(_ id: String, _ placeholders: [Int: Int]) -> Int? {
        if let v = nodeVertex[id] { return v }
        if let rep = representative(id) { return rep }
        return clusterIndex[id].flatMap { placeholders[$0] }
    }

    /// Self-loops are drawn beside their node; reserve room for them.
    mutating func widenForLoops(_ loops: [Int]) {
        for e in loops {
            guard let v = nodeVertex[graph.edges[e].from] else { continue }
            let label = graph.edges[e].labelSize.map { canonical($0).across } ?? 0
            engine.vertices[v].width += 2 * (24 + label)
        }
    }
}
