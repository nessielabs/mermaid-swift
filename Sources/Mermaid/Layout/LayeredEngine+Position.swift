extension LayeredEngine {
    struct Spacing {
        var node: Double
        var rank: Double
        var cluster: Double
    }

    /// The x variable a vertex's position is bound to. All left (or right)
    /// borders of a cluster share one variable, so a cluster's box is the
    /// same width in every rank and no outside vertex can enter it.
    private func variable(_ v: Int) -> Int {
        if case .border(let c, let left) = vertices[v].kind { return vertices.count + c * 2 + (left ? 0 : 1) }
        return v
    }

    /// Assigns x coordinates within ranks. Returns false if the ordering
    /// produced contradictory cluster constraints (the caller then retries
    /// without cluster separation).
    mutating func assignX(layers: [[Int]], segments: [Segment], spacing: Spacing, useClusters: Bool) -> Bool {
        let count = vertices.count + clusterParent.count * 2
        var constraints: [Int: [Int: Double]] = [:]
        func require(_ a: Int, before b: Int, by gap: Double) {
            guard a != b else { return }
            constraints[a, default: [:]][b] = max(constraints[a]?[b] ?? -.infinity, gap)
        }
        for layer in layers {
            let items = useClusters ? layer : layer.filter { if case .border = vertices[$0].kind { false } else { true } }
            for (a, b) in zip(items, items.dropFirst()) {
                require(variable(a), before: variable(b), by: gap(a, b, spacing))
            }
        }
        if useClusters {
            for c in clusterParent.indices {
                require(vertices.count + c * 2, before: vertices.count + c * 2 + 1,
                        by: clusterLabels[c].width + spacing.cluster * 2)
            }
        }
        var reverse: [Int: [Int: Double]] = [:]
        for (a, targets) in constraints { for (b, g) in targets { reverse[b, default: [:]][a] = g } }
        guard let topo = Self.topologicalOrder(count: count, edges: constraints) else { return false }

        // Left-packed and right-packed solutions; their average is feasible
        // (difference constraints form a convex set) and balanced.
        var left = [Double](repeating: 0, count: count)
        for v in topo { for (w, g) in constraints[v] ?? [:] { left[w] = max(left[w], left[v] + g) } }
        var right = [Double](repeating: 0, count: count)
        for v in topo.reversed() { for (u, g) in reverse[v] ?? [:] { right[u] = min(right[u], right[v] - g) } }
        let shift = (left.max() ?? 0) - (right.max() ?? 0)
        var x = zip(left, right).map { ($0 + $1 + shift) / 2 }

        // Relax each vertex toward the weighted mean of its neighbors while
        // respecting every constraint, which straightens edges.
        var neighbors = [[(Int, Double)]](repeating: [], count: count)
        for s in segments {
            neighbors[s.upper].append((s.lower, s.weight))
            neighbors[s.lower].append((s.upper, s.weight))
        }
        for pass in 0..<40 {
            let order = pass % 2 == 0 ? topo : topo.reversed()
            for v in order {
                let lo = (reverse[v] ?? [:]).map { x[$0.key] + $0.value }.max() ?? -.infinity
                let hi = (constraints[v] ?? [:]).map { x[$0.key] - $0.value }.min() ?? .infinity
                var target = x[v]
                if v >= vertices.count {
                    // Cluster sides hug their contents.
                    target = (v - vertices.count) % 2 == 0 ? hi : lo
                } else if !neighbors[v].isEmpty {
                    let total = neighbors[v].reduce(0) { $0 + $1.1 }
                    target = neighbors[v].reduce(0) { $0 + x[$1.0] * $1.1 } / total
                }
                if target.isFinite { x[v] = min(max(target, lo), hi) }
            }
        }
        for v in vertices.indices { vertices[v].x = x[variable(v)] }
        return true
    }

    private func gap(_ a: Int, _ b: Int, _ spacing: Spacing) -> Double {
        let half = { (v: Int) in self.vertices[v].width / 2 }
        switch (vertices[a].kind, vertices[b].kind) {
        case (.border(let ca, true), .border(let cb, true)) where ca != cb: return spacing.cluster
        case (.border(let ca, false), .border(let cb, false)) where ca != cb: return spacing.cluster
        case (.border(let ca, true), .border(let cb, false)) where ca == cb: return 0
        case (.border(_, false), .border(_, true)): return spacing.node
        case (.border(_, true), _): return half(b) + spacing.cluster
        case (_, .border(_, false)): return half(a) + spacing.cluster
        case (.border, _): return half(b) + spacing.node
        case (_, .border): return half(a) + spacing.node
        default:
            let bothBends = !isReal(a) && !isReal(b)
            return half(a) + half(b) + (bothBends ? spacing.node / 2 : spacing.node)
        }
    }

    static func topologicalOrder(count: Int, edges: [Int: [Int: Double]]) -> [Int]? {
        var indegree = [Int](repeating: 0, count: count)
        for targets in edges.values { for b in targets.keys { indegree[b] += 1 } }
        var queue = (0..<count).filter { indegree[$0] == 0 }
        var order: [Int] = []
        order.reserveCapacity(count)
        var head = 0
        while head < queue.count {
            let v = queue[head]
            head += 1
            order.append(v)
            for b in (edges[v] ?? [:]).keys {
                indegree[b] -= 1
                if indegree[b] == 0 { queue.append(b) }
            }
        }
        return order.count == count ? order : nil
    }
}
