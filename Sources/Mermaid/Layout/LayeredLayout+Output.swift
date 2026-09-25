extension LayeredComputation {
    /// Places ranks along the flow, leaving room for cluster padding and
    /// titles where clusters begin and end.
    mutating func assignY(layers: [[Int]], spans: [ClosedRange<Int>?], spacing: LayeredEngine.Spacing) {
        let titleAtStart = graph.direction == .topToBottom
        let titleAtEnd = graph.direction == .bottomToTop
        var startInset = [Double](repeating: 0, count: spans.count)
        var endInset = [Double](repeating: 0, count: spans.count)
        for c in clustersInnermostFirst() {
            guard let span = spans[c] else { continue }
            let children = spans.indices.filter { engine.clusterParent[$0] == c }
            startInset[c] = spacing.cluster + (titleAtStart ? titleInsets[c] : 0)
                + (children.filter { spans[$0]?.lowerBound == span.lowerBound }.map { startInset[$0] }.max() ?? 0)
            endInset[c] = spacing.cluster + (titleAtEnd ? titleInsets[c] : 0)
                + (children.filter { spans[$0]?.upperBound == span.upperBound }.map { endInset[$0] }.max() ?? 0)
        }
        var before = [Double](repeating: 0, count: layers.count)
        var after = [Double](repeating: 0, count: layers.count)
        for (c, span) in spans.enumerated() {
            guard let span else { continue }
            let parentSpan = engine.clusterParent[c].flatMap { spans[$0] }
            if parentSpan?.lowerBound != span.lowerBound { before[span.lowerBound] = max(before[span.lowerBound], startInset[c]) }
            if parentSpan?.upperBound != span.upperBound { after[span.upperBound] = max(after[span.upperBound], endInset[c]) }
        }
        var y = 0.0
        for (r, layer) in layers.enumerated() {
            let height = layer.map { engine.vertices[$0].height }.max() ?? 0
            y += before[r] + height / 2
            for v in layer { engine.vertices[v].y = y }
            y += height / 2 + after[r] + spacing.rank
        }
    }

    func clustersInnermostFirst() -> [Int] {
        engine.clusterParent.indices.sorted { engine.ancestry($0).count > engine.ancestry($1).count }
    }

    /// Converts engine coordinates to screen coordinates for the direction.
    func output(chains: [[Int]], loops: [Int], spans: [ClosedRange<Int>?]) -> LayeredLayout {
        let vertices = engine.vertices
        var clusterRects = [Int: (minX: Double, maxX: Double, minY: Double, maxY: Double)]()
        let titleAtStart = graph.direction == .topToBottom, titleAtEnd = graph.direction == .bottomToTop
        for c in clustersInnermostFirst() where spans[c] != nil {
            var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
            for v in vertices where v.cluster == c {
                if case .border(_, let left) = v.kind {
                    if left { minX = min(minX, v.x) } else { maxX = max(maxX, v.x) }
                    continue
                }
                minY = min(minY, v.y - v.height / 2)
                maxY = max(maxY, v.y + v.height / 2)
            }
            for child in engine.clusterParent.indices where engine.clusterParent[child] == c {
                if let r = clusterRects[child] { minY = min(minY, r.minY); maxY = max(maxY, r.maxY) }
            }
            minY -= graph.clusterPadding + (titleAtStart ? titleInsets[c] : 0)
            maxY += graph.clusterPadding + (titleAtEnd ? titleInsets[c] : 0)
            clusterRects[c] = (minX, maxX, minY, maxY)
        }

        // Bounds of everything, in engine space.
        var points: [Point] = []
        for v in vertices {
            if case .border = v.kind { continue }
            points.append(Point(v.x - v.width / 2, v.y - v.height / 2))
            points.append(Point(v.x + v.width / 2, v.y + v.height / 2))
        }
        for r in clusterRects.values { points += [Point(r.minX, r.minY), Point(r.maxX, r.maxY)] }
        let bounds = Rect.bounding(points) ?? Rect(x: 0, y: 0, width: 0, height: 0)
        let direction = graph.direction
        func screen(_ p: Point) -> Point {
            let x = p.x - bounds.minX, y = p.y - bounds.minY
            switch direction {
            case .topToBottom: return Point(x, y)
            case .bottomToTop: return Point(x, bounds.height - y)
            case .leftToRight: return Point(y, x)
            case .rightToLeft: return Point(bounds.height - y, x)
            }
        }
        func screenRect(_ a: Point, _ b: Point) -> Rect { Rect.bounding([screen(a), screen(b)])! }

        var nodes: [String: Rect] = [:]
        for v in vertices {
            guard case .real(let n) = v.kind, n >= 0 else { continue }
            nodes[graph.nodes[n].id] = Rect(center: screen(Point(v.x, v.y)), size: graph.nodes[n].size)
        }
        var clusters: [String: Rect] = [:]
        for (c, r) in clusterRects { clusters[graph.clusters[c].id] = screenRect(Point(r.minX, r.minY), Point(r.maxX, r.maxY)) }

        // Bends run vertically through their rank's whole band: separation
        // constraints keep bends clear of nodes within a rank, so routes
        // then only move sideways in the gaps between ranks and never cut
        // through a tall neighbor.
        var bandHeight: [Int: Double] = [:]
        for v in vertices { bandHeight[v.rank] = max(bandHeight[v.rank] ?? 0, v.height) }
        var routes = chains.map { chain -> LayeredLayout.Route in
            var points: [Point] = []
            var labelCenter: Point?
            for (i, v) in chain.enumerated() {
                let vertex = vertices[v]
                let center = Point(vertex.x, vertex.y)
                let half = (bandHeight[vertex.rank] ?? 0) / 2
                guard i > 0, i < chain.count - 1, half > 1 else {
                    points.append(screen(center))
                    continue
                }
                let ascending = vertices[chain[0]].rank < vertices[chain[chain.count - 1]].rank
                let entry = Point(vertex.x, vertex.y + (ascending ? -half : half))
                let exit = Point(vertex.x, vertex.y + (ascending ? half : -half))
                points.append(screen(entry))
                if case .label = vertex.kind {
                    labelCenter = screen(center)
                    points.append(screen(center))
                }
                points.append(screen(exit))
            }
            return .init(points: points, labelCenter: labelCenter)
        }
        for e in loops {
            guard let frame = nodes[graph.edges[e].from] ?? clusters[graph.edges[e].from] else { continue }
            let c = frame.center, reach = frame.width / 2 + 22
            routes[e] = .init(points: [c, Point(c.x + reach, c.y - frame.height * 0.3),
                                       Point(c.x + reach, c.y + frame.height * 0.3), c],
                              labelCenter: graph.edges[e].labelSize.map { Point(c.x + reach + $0.width / 2 + 4, c.y) })
        }
        let size = horizontal ? Size(bounds.height, bounds.width) : Size(bounds.width, bounds.height)
        return LayeredLayout(nodes: nodes, edges: routes, clusters: clusters, size: size)
    }
}
