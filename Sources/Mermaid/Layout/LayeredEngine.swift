/// Working state for one run of the layered layout.
///
/// The engine works in a canonical top-to-bottom frame: `rank` grows along
/// y and `order` along x. `width` is a vertex's extent across its rank and
/// `height` its extent along the flow. Horizontal directions swap these on
/// the way in and out.
struct LayeredEngine {
    enum Kind: Equatable {
        case real(Int)
        /// A bend point of a long edge.
        case dummy(edge: Int)
        /// The slot holding an edge's label.
        case label(edge: Int)
        /// A cluster side in one rank.
        case border(cluster: Int, left: Bool)
    }

    struct Vertex {
        var kind: Kind
        var width: Double
        var height: Double
        var cluster: Int?
        var rank = 0
        var order = 0
        var x = 0.0
        var y = 0.0
    }

    /// A directed edge between vertices. After cycle removal all arcs point
    /// from lower to higher rank.
    struct Arc {
        var from: Int
        var to: Int
        var minLength: Int
        var weight: Double
        var edge: Int
        var reversed = false
    }

    var vertices: [Vertex] = []
    var arcs: [Arc] = []
    /// Cluster index → parent cluster index.
    var clusterParent: [Int?] = []
    var clusterLabels: [Size] = []

    // MARK: - Ranking

    /// Reverses a minimal-effort set of arcs (DFS back edges) so the graph
    /// becomes acyclic. Reversed arcs are restored when routes are built.
    mutating func removeCycles() {
        var outgoing = [[Int]](repeating: [], count: vertices.count)
        for (i, arc) in arcs.enumerated() { outgoing[arc.from].append(i) }
        var state = [UInt8](repeating: 0, count: vertices.count) // 0 new, 1 on stack, 2 done
        for root in vertices.indices where state[root] == 0 {
            var stack: [(vertex: Int, next: Int)] = [(root, 0)]
            state[root] = 1
            while let top = stack.last {
                if top.next < outgoing[top.vertex].count {
                    stack[stack.count - 1].next += 1
                    let arcIndex = outgoing[top.vertex][top.next]
                    let target = arcs[arcIndex].to
                    if state[target] == 1 {
                        arcs[arcIndex].reversed = true
                        swap(&arcs[arcIndex].from, &arcs[arcIndex].to)
                    } else if state[target] == 0 {
                        state[target] = 1
                        stack.append((target, 0))
                    }
                } else {
                    state[top.vertex] = 2
                    stack.removeLast()
                }
            }
        }
    }

    /// Longest-path ranking followed by iterative tightening that moves each
    /// vertex to the weighted median of its neighbors' preferred ranks.
    mutating func assignRanks() {
        var incoming = [[Int]](repeating: [], count: vertices.count)
        var outgoing = [[Int]](repeating: [], count: vertices.count)
        for (i, arc) in arcs.enumerated() {
            incoming[arc.to].append(i)
            outgoing[arc.from].append(i)
        }
        // Topological order (Kahn), then longest path from sources.
        var indegree = incoming.map(\.count)
        var queue = vertices.indices.filter { indegree[$0] == 0 }
        var order: [Int] = []
        while let v = queue.popLast() {
            order.append(v)
            for a in outgoing[v] {
                indegree[arcs[a].to] -= 1
                if indegree[arcs[a].to] == 0 { queue.append(arcs[a].to) }
            }
        }
        for v in order {
            vertices[v].rank = incoming[v].map { vertices[arcs[$0].from].rank + arcs[$0].minLength }.max() ?? 0
        }
        for _ in 0..<(vertices.count + 8) {
            var changed = false
            for v in order.reversed() {
                let lo = incoming[v].map { vertices[arcs[$0].from].rank + arcs[$0].minLength }.max()
                let hi = outgoing[v].map { vertices[arcs[$0].to].rank - arcs[$0].minLength }.min()
                let target: Int
                switch (lo, hi) {
                case (nil, nil): continue
                case (nil, let hi?): target = hi
                case (let lo?, nil): target = lo
                case (let lo?, let hi?):
                    var wishes: [(rank: Int, weight: Double)] = incoming[v].map { (lo, arcs[$0].weight) }
                    wishes += outgoing[v].map { (hi, arcs[$0].weight) }
                    target = Self.weightedMedian(wishes).clamped(to: lo...max(lo, hi))
                }
                if target != vertices[v].rank {
                    vertices[v].rank = target
                    changed = true
                }
            }
            if !changed { break }
        }
        let minRank = vertices.map(\.rank).min() ?? 0
        for v in vertices.indices { vertices[v].rank -= minRank }
    }

    static func weightedMedian(_ values: [(rank: Int, weight: Double)]) -> Int {
        let sorted = values.sorted { $0.rank < $1.rank }
        let half = sorted.reduce(0) { $0 + $1.weight } / 2
        var total = 0.0
        for value in sorted {
            total += value.weight
            if total >= half { return value.rank }
        }
        return sorted.last?.rank ?? 0
    }
}
