extension LayeredEngine {
    /// Orders vertices within ranks to reduce crossings while keeping each
    /// cluster contiguous. Returns the vertices of each rank in order.
    mutating func orderVertices(segments: [Segment], iterations: Int = 24) -> [[Int]] {
        let rankCount = (vertices.map(\.rank).max() ?? -1) + 1
        var up = [[(Int, Double)]](repeating: [], count: vertices.count)
        var down = [[(Int, Double)]](repeating: [], count: vertices.count)
        for s in segments {
            up[s.lower].append((s.upper, s.weight))
            down[s.upper].append((s.lower, s.weight))
        }
        var layers = [[Int]](repeating: [], count: rankCount)
        for v in initialOrder(down: down) { layers[vertices[v].rank].append(v) }
        for r in layers.indices { layers[r] = sortLayer(layers[r], keys: positionKeys(layers[r]), layers: layers) }
        setOrders(layers)

        var best = layers
        var bestCrossings = crossings(layers, down: down)
        for iteration in 0..<iterations where bestCrossings > 0 {
            let downward = iteration % 2 == 0
            let ranks = downward ? Array(layers.indices.dropFirst()) : Array(layers.indices.dropLast().reversed())
            for r in ranks {
                var keys: [Int: Double] = [:]
                for v in layers[r] {
                    let neighbors = downward ? up[v] : down[v]
                    let total = neighbors.reduce(0) { $0 + $1.1 }
                    keys[v] = total > 0
                        ? neighbors.reduce(0) { $0 + Double(vertices[$1.0].order) * $1.1 } / total
                        : Double(vertices[v].order)
                }
                layers[r] = sortLayer(layers[r], keys: keys, layers: layers)
                setOrders(layers)
            }
            let count = crossings(layers, down: down)
            if count < bestCrossings {
                bestCrossings = count
                best = layers
            }
        }
        layers = best
        setOrders(layers)
        if !clusterParent.isEmpty {
            // Give each long edge one key for all its ranks, so its order
            // relative to cluster blocks agrees in every rank.
            var chainKeys: [Int: (sum: Double, count: Double)] = [:]
            for v in vertices.indices {
                guard let edge = chainEdge(v) else { continue }
                let size = Double(max(1, layers[vertices[v].rank].count))
                chainKeys[edge, default: (0, 0)].sum += Double(vertices[v].order) / size
                chainKeys[edge, default: (0, 0)].count += 1
            }
            for r in layers.indices {
                var keys = positionKeys(layers[r])
                for v in layers[r] {
                    if let edge = chainEdge(v), let k = chainKeys[edge] { keys[v] = k.sum / k.count * 1000 }
                }
                layers[r] = sortLayer(layers[r], keys: keys, layers: layers)
            }
            setOrders(layers)
        }
        return layers
    }

    private func chainEdge(_ v: Int) -> Int? {
        switch vertices[v].kind {
        case .dummy(let edge), .label(let edge): return edge
        default: return nil
        }
    }

    /// Depth-first visit order from sources, which gives sweeps a good start.
    private func initialOrder(down: [[(Int, Double)]]) -> [Int] {
        var visited = [Bool](repeating: false, count: vertices.count)
        var result: [Int] = []
        let roots = vertices.indices.sorted { (vertices[$0].rank, $0) < (vertices[$1].rank, $1) }
        for root in roots where !visited[root] {
            var stack = [root]
            while let v = stack.popLast() {
                guard !visited[v] else { continue }
                visited[v] = true
                result.append(v)
                stack += down[v].map(\.0).reversed().filter { !visited[$0] }
            }
        }
        return result
    }

    private func positionKeys(_ layer: [Int]) -> [Int: Double] {
        Dictionary(uniqueKeysWithValues: layer.enumerated().map { ($1, Double($0)) })
    }

    private mutating func setOrders(_ layers: [[Int]]) {
        for layer in layers { for (i, v) in layer.enumerated() { vertices[v].order = i } }
    }

    /// Sorts a layer by `keys`, grouping each cluster's vertices into one
    /// contiguous block (recursively), pinning cluster borders to the block
    /// ends, and ordering sibling clusters by a key shared across ranks.
    private func sortLayer(_ layer: [Int], keys: [Int: Double], layers: [[Int]]) -> [Int] {
        guard !clusterParent.isEmpty else {
            return layer.sorted { (keys[$0] ?? 0, vertices[$0].order) < (keys[$1] ?? 0, vertices[$1].order) }
        }
        let clusterKeys = globalClusterKeys(layers)
        func block(_ members: [Int], level: Int?) -> [Int] {
            var groups: [(key: Double, tie: Int, items: [Int])] = []
            var childMembers: [Int: [Int]] = [:]
            var left: [Int] = [], right: [Int] = []
            for v in members {
                if case .border(let c, let isLeft) = vertices[v].kind, c == level {
                    if isLeft { left.append(v) } else { right.append(v) }
                    continue
                }
                let chain = ancestry(vertices[v].cluster)
                if let index = chain.firstIndex(where: { clusterParent[$0] == level }), chain[index] != level {
                    childMembers[chain[index], default: []].append(v)
                } else {
                    groups.append((keys[v] ?? 0, vertices[v].order, [v]))
                }
            }
            for (child, items) in childMembers {
                groups.append((clusterKeys[child] ?? 0, -1, block(items, level: child)))
            }
            groups.sort { ($0.key, $0.tie) < ($1.key, $1.tie) }
            return left + groups.flatMap(\.items) + right
        }
        return block(layer, level: nil)
    }

    /// Each cluster's mean normalized position over every rank it spans.
    private func globalClusterKeys(_ layers: [[Int]]) -> [Int: Double] {
        var sums: [Int: (Double, Double)] = [:]
        for layer in layers {
            let size = Double(max(1, layer.count))
            for v in layer {
                for c in ancestry(vertices[v].cluster) {
                    sums[c, default: (0, 0)].0 += Double(vertices[v].order) / size * 1000
                    sums[c, default: (0, 0)].1 += 1
                }
            }
        }
        return sums.mapValues { $0.0 / $0.1 }
    }

    private func crossings(_ layers: [[Int]], down: [[(Int, Double)]]) -> Double {
        var total = 0.0
        for layer in layers {
            var pairs: [(Int, Int, Double)] = []
            for v in layer { for (w, weight) in down[v] { pairs.append((vertices[v].order, vertices[w].order, weight)) } }
            for i in pairs.indices {
                for j in (i + 1)..<pairs.count {
                    let a = pairs[i], b = pairs[j]
                    if (a.0 < b.0 && a.1 > b.1) || (a.0 > b.0 && a.1 < b.1) { total += a.2 * b.2 }
                }
            }
        }
        return total
    }
}
