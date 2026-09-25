extension LayeredLayout {
    /// Lays out the first cluster that has its own direction and no edges
    /// crossing its boundary as a separate graph in that direction, places
    /// it in the parent layout as a single node of its size, and merges the
    /// two results. Returns nil when no cluster qualifies. This is how
    /// Mermaid honors `direction` inside subgraphs and composite states.
    static func layoutCollapsingDirectedClusters(_ graph: LayeredGraph) -> LayeredLayout? {
        let parent = Dictionary(graph.clusters.map { ($0.id, $0.parent) }, uniquingKeysWith: { a, _ in a })
        func isWithin(_ cluster: String?, _ ancestor: String) -> Bool {
            var current = cluster
            while let c = current {
                if c == ancestor { return true }
                current = parent[c] ?? nil
            }
            return false
        }
        for cluster in graph.clusters where cluster.direction != nil {
            let subclusters = Set(graph.clusters.filter { $0.id != cluster.id && isWithin($0.id, cluster.id) }.map(\.id))
            let members = Set(graph.nodes.filter { isWithin($0.cluster, cluster.id) }.map(\.id))
            let inside = { (id: String) in members.contains(id) || subclusters.contains(id) }
            guard !members.isEmpty, graph.edges.allSatisfy({ inside($0.from) == inside($0.to) }) else { continue }
            return collapse(graph, cluster: cluster, members: members, subclusters: subclusters, inside: inside)
        }
        return nil
    }

    private static func collapse(_ graph: LayeredGraph, cluster: LayeredGraph.Cluster, members: Set<String>,
                                 subclusters: Set<String>, inside: (String) -> Bool) -> LayeredLayout {
        var inner = graph
        inner.direction = cluster.direction!
        inner.nodes = graph.nodes.filter { members.contains($0.id) }.map { node in
            var node = node
            if node.cluster == cluster.id { node.cluster = nil }
            return node
        }
        inner.clusters = graph.clusters.filter { subclusters.contains($0.id) }.map { sub in
            var sub = sub
            if sub.parent == cluster.id { sub.parent = nil }
            return sub
        }
        let innerIndices = graph.edges.indices.filter { inside(graph.edges[$0].from) }
        inner.edges = innerIndices.map { graph.edges[$0] }
        let innerLayout = compute(inner)

        let padding = graph.clusterPadding
        let title = cluster.labelSize.height > 0 ? cluster.labelSize.height + 4 : 0
        let size = Size(max(innerLayout.size.width, cluster.labelSize.width) + 2 * padding,
                        innerLayout.size.height + 2 * padding + title)
        let placeholder = "\u{0}cluster:" + cluster.id
        var outer = graph
        outer.nodes = graph.nodes.filter { !members.contains($0.id) }
        outer.nodes.append(.init(id: placeholder, size: size, cluster: cluster.parent))
        outer.clusters = graph.clusters.filter { $0.id != cluster.id && !subclusters.contains($0.id) }
        let outerIndices = graph.edges.indices.filter { !inside(graph.edges[$0].from) }
        outer.edges = outerIndices.map { index in
            var edge = graph.edges[index]
            if edge.from == cluster.id { edge.from = placeholder }
            if edge.to == cluster.id { edge.to = placeholder }
            return edge
        }
        let outerLayout = compute(outer)

        let frame = outerLayout.nodes[placeholder]!
        let dx = frame.minX + (frame.width - innerLayout.size.width) / 2, dy = frame.minY + padding + title
        let shift = { (p: Point) in Point(p.x + dx, p.y + dy) }
        var nodes = outerLayout.nodes
        nodes[placeholder] = nil
        for (id, rect) in innerLayout.nodes { nodes[id] = rect.offsetBy(dx: dx, dy: dy) }
        var clusters = outerLayout.clusters
        clusters[cluster.id] = frame
        for (id, rect) in innerLayout.clusters { clusters[id] = rect.offsetBy(dx: dx, dy: dy) }
        var edges = [Route](repeating: Route(points: [], labelCenter: nil), count: graph.edges.count)
        for (k, index) in innerIndices.enumerated() {
            let route = innerLayout.edges[k]
            edges[index] = Route(points: route.points.map(shift), labelCenter: route.labelCenter.map(shift))
        }
        for (k, index) in outerIndices.enumerated() { edges[index] = outerLayout.edges[k] }
        return LayeredLayout(nodes: nodes, edges: edges, clusters: clusters, size: outerLayout.size)
    }
}
