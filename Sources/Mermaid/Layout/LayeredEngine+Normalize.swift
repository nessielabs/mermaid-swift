extension LayeredEngine {
    /// Adjacent-rank connection used by ordering and positioning.
    struct Segment {
        var upper: Int
        var lower: Int
        var weight: Double
    }

    /// Splits every arc into unit-length segments, inserting bend vertices
    /// (and a label vertex in the middle rank of labeled edges). Returns
    /// each input edge's vertex chain in arc direction.
    mutating func normalize(labelSizes: [Int: Size], edgeCount: Int) -> (segments: [Segment], chains: [[Int]]) {
        var segments: [Segment] = []
        var chains = [[Int]](repeating: [], count: edgeCount)
        for arc in arcs {
            let top = vertices[arc.from].rank, bottom = vertices[arc.to].rank
            let cluster = commonCluster(vertices[arc.from].cluster, vertices[arc.to].cluster)
            let labelRank = labelSizes[arc.edge] != nil ? top + (bottom - top) / 2 : nil
            var chain = [arc.from]
            if bottom - top > 1 {
                for rank in (top + 1)..<bottom {
                    let isLabel = rank == labelRank
                    let size = isLabel ? labelSizes[arc.edge]! : .zero
                    var vertex = Vertex(kind: isLabel ? .label(edge: arc.edge) : .dummy(edge: arc.edge),
                                        width: size.width, height: size.height, cluster: cluster)
                    vertex.rank = rank
                    vertices.append(vertex)
                    chain.append(vertices.count - 1)
                }
            }
            chain.append(arc.to)
            // Long edges get heavier inner segments so they stay straight.
            for (a, b) in zip(chain, chain.dropFirst()) {
                let inner = !isReal(a) && !isReal(b)
                segments.append(Segment(upper: a, lower: b, weight: arc.weight * (inner ? 8 : isReal(a) && isReal(b) ? 1 : 2)))
            }
            chains[arc.edge] = arc.reversed ? chain.reversed() : chain
        }
        return (segments, chains)
    }

    func isReal(_ v: Int) -> Bool {
        if case .real = vertices[v].kind { return true }
        return false
    }

    /// The chain of clusters from `cluster` up to the root, innermost first.
    func ancestry(_ cluster: Int?) -> [Int] {
        var result: [Int] = []
        var current = cluster
        while let c = current {
            result.append(c)
            current = clusterParent[c]
        }
        return result
    }

    /// The innermost cluster containing both clusters, or nil for the root.
    func commonCluster(_ a: Int?, _ b: Int?) -> Int? {
        let chainA = ancestry(a)
        let setB = Set(ancestry(b))
        return chainA.first { setB.contains($0) }
    }

    /// Adds left and right border vertices to every rank each cluster spans,
    /// so that positioning can keep cluster boxes free of outsiders.
    /// Returns each cluster's rank span.
    mutating func addClusterBorders() -> [ClosedRange<Int>?] {
        var spans = [ClosedRange<Int>?](repeating: nil, count: clusterParent.count)
        for vertex in vertices {
            for c in ancestry(vertex.cluster) {
                spans[c] = spans[c].map { min($0.lowerBound, vertex.rank)...max($0.upperBound, vertex.rank) }
                    ?? vertex.rank...vertex.rank
            }
        }
        for (c, span) in spans.enumerated() {
            guard let span else { continue }
            for rank in span {
                for left in [true, false] {
                    var vertex = Vertex(kind: .border(cluster: c, left: left), width: 0, height: 0, cluster: c)
                    vertex.rank = rank
                    vertices.append(vertex)
                }
            }
        }
        return spans
    }
}
