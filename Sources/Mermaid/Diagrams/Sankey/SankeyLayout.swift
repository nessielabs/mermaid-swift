import Foundation

/// The d3-sankey layout algorithm, which mermaid.js uses: nodes are
/// assigned to columns by depth (then aligned), stacked in each column
/// proportionally to their value, relaxed toward the weighted centers of
/// their neighbours over several iterations with collisions resolved, and
/// finally each node's links are stacked in the order of the nodes they
/// connect to.
struct SankeyLayout: Sendable {
    enum Alignment: String, Sendable {
        /// Nodes at their depth; sinks pushed to the last column.
        case justify
        /// Nodes at their depth from the sources.
        case left
        /// Nodes at their height from the sinks.
        case right
        /// Nodes at their depth; sources moved next to their first target.
        case center
    }

    struct Node: Sendable {
        var x0 = 0.0, x1 = 0.0, y0 = 0.0, y1 = 0.0
        /// The larger of the node's inflow and outflow.
        var value = 0.0
        var depth = 0, height = 0, layer = 0
        /// Outgoing and incoming link indices, in their stacking order.
        var sourceLinks: [Int] = []
        var targetLinks: [Int] = []

        var frame: Rect { Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) }
    }

    struct Link: Sendable {
        var source: Int, target: Int, value: Double
        /// Vertical centers of the link where it leaves its source and
        /// enters its target, and its thickness.
        var y0 = 0.0, y1 = 0.0, width = 0.0
    }

    var nodes: [Node]
    var links: [Link]
    var extent: Rect
    var nodeWidth: Double
    var nodePadding: Double
    var alignment: Alignment
    var iterations = 6
    /// The padding actually used, reduced when the tallest column would
    /// not otherwise fit.
    private(set) var usedPadding = 0.0

    init(nodeCount: Int, links: [(source: Int, target: Int, value: Double)], extent: Rect,
         nodeWidth: Double = 24, nodePadding: Double = 8, alignment: Alignment = .justify) {
        nodes = Array(repeating: Node(), count: nodeCount)
        self.links = links.map { Link(source: $0.source, target: $0.target, value: $0.value) }
        self.extent = extent
        self.nodeWidth = nodeWidth
        self.nodePadding = nodePadding
        self.alignment = alignment
    }

    /// Runs the whole layout. The links must not contain a cycle.
    mutating func compute() {
        for (i, link) in links.enumerated() {
            nodes[link.source].sourceLinks.append(i)
            nodes[link.target].targetLinks.append(i)
        }
        for i in nodes.indices {
            let outflow = nodes[i].sourceLinks.reduce(0) { $0 + links[$1].value }
            let inflow = nodes[i].targetLinks.reduce(0) { $0 + links[$1].value }
            nodes[i].value = max(outflow, inflow)
        }
        computeDepths()
        let columns = computeLayers()
        computeBreadths(columns)
        computeLinkBreadths()
    }

    // MARK: - Columns

    /// Breadth-first depth from the sources and height from the sinks.
    private mutating func computeDepths() {
        func sweep(_ next: (Node) -> [Int], _ assign: (inout Node, Int) -> Void) {
            var current = Set(nodes.indices), level = 0
            while !current.isEmpty, level <= nodes.count {
                var following = Set<Int>()
                for i in current.sorted() {
                    assign(&nodes[i], level)
                    following.formUnion(next(nodes[i]))
                }
                current = following
                level += 1
            }
        }
        sweep({ $0.sourceLinks.map { links[$0].target } }, { $0.depth = $1 })
        sweep({ $0.targetLinks.map { links[$0].source } }, { $0.height = $1 })
    }

    private func column(of node: Node, count: Int) -> Int {
        switch alignment {
        case .left: return node.depth
        case .right: return count - 1 - node.height
        case .justify: return node.sourceLinks.isEmpty ? count - 1 : node.depth
        case .center:
            if !node.targetLinks.isEmpty { return node.depth }
            guard let first = node.sourceLinks.map({ nodes[links[$0].target].depth }).min() else { return 0 }
            return first - 1
        }
    }

    private mutating func computeLayers() -> [[Int]] {
        let count = (nodes.map(\.depth).max() ?? 0) + 1
        let kx = count > 1 ? (extent.width - nodeWidth) / Double(count - 1) : 0
        var columns = [[Int]](repeating: [], count: count)
        for i in nodes.indices {
            let layer = min(max(column(of: nodes[i], count: count), 0), count - 1)
            nodes[i].layer = layer
            nodes[i].x0 = extent.minX + Double(layer) * kx
            nodes[i].x1 = nodes[i].x0 + nodeWidth
            columns[layer].append(i)
        }
        return columns.filter { !$0.isEmpty }
    }

    // MARK: - Vertical placement

    private mutating func computeBreadths(_ columns: [[Int]]) {
        let tallest = columns.map(\.count).max() ?? 1
        usedPadding = tallest > 1 ? min(nodePadding, extent.height / Double(tallest - 1)) : nodePadding
        initializeBreadths(columns)
        var columns = columns
        for i in 0..<iterations {
            let alpha = pow(0.99, Double(i))
            let beta = max(1 - alpha, Double(i + 1) / Double(iterations))
            relaxRightToLeft(&columns, alpha: alpha, beta: beta)
            relaxLeftToRight(&columns, alpha: alpha, beta: beta)
        }
    }

    /// Stacks each column top-down with a shared value-to-height scale,
    /// then spreads the leftover space evenly between the nodes.
    private mutating func initializeBreadths(_ columns: [[Int]]) {
        let py = usedPadding
        let ky = columns.compactMap { column -> Double? in
            let total = column.reduce(0) { $0 + nodes[$1].value }
            return total > 0 ? (extent.height - Double(column.count - 1) * py) / total : nil
        }.min() ?? 0
        for column in columns {
            var y = extent.minY
            for i in column {
                nodes[i].y0 = y
                nodes[i].y1 = y + nodes[i].value * ky
                y = nodes[i].y1 + py
                for l in nodes[i].sourceLinks { links[l].width = links[l].value * ky }
            }
            let spare = (extent.maxY - y + py) / Double(column.count + 1)
            for (k, i) in column.enumerated() {
                nodes[i].y0 += spare * Double(k + 1)
                nodes[i].y1 += spare * Double(k + 1)
            }
            reorderLinks(column)
        }
    }

    /// Moves each node toward the weighted center of its sources.
    private mutating func relaxLeftToRight(_ columns: inout [[Int]], alpha: Double, beta: Double) {
        guard columns.count > 1 else { return }
        for c in 1..<columns.count {
            for target in columns[c] {
                var y = 0.0, w = 0.0
                for l in nodes[target].targetLinks {
                    let source = links[l].source
                    let v = links[l].value * Double(nodes[target].layer - nodes[source].layer)
                    y += targetTop(source, target) * v
                    w += v
                }
                guard w > 0 else { continue }
                let dy = (y / w - nodes[target].y0) * alpha
                nodes[target].y0 += dy
                nodes[target].y1 += dy
                reorderNodeLinks(target)
            }
            columns[c].sort { nodes[$0].y0 < nodes[$1].y0 }
            resolveCollisions(columns[c], alpha: beta)
        }
    }

    /// Moves each node toward the weighted center of its targets.
    private mutating func relaxRightToLeft(_ columns: inout [[Int]], alpha: Double, beta: Double) {
        guard columns.count > 1 else { return }
        for c in stride(from: columns.count - 2, through: 0, by: -1) {
            for source in columns[c] {
                var y = 0.0, w = 0.0
                for l in nodes[source].sourceLinks {
                    let target = links[l].target
                    let v = links[l].value * Double(nodes[target].layer - nodes[source].layer)
                    y += sourceTop(source, target) * v
                    w += v
                }
                guard w > 0 else { continue }
                let dy = (y / w - nodes[source].y0) * alpha
                nodes[source].y0 += dy
                nodes[source].y1 += dy
                reorderNodeLinks(source)
            }
            columns[c].sort { nodes[$0].y0 < nodes[$1].y0 }
            resolveCollisions(columns[c], alpha: beta)
        }
    }

    /// Pushes overlapping nodes apart outward from the middle node, then
    /// back inside the extent.
    private mutating func resolveCollisions(_ column: [Int], alpha: Double) {
        guard !column.isEmpty else { return }
        let middle = column.count >> 1
        let subject = nodes[column[middle]]
        pushUp(column, from: subject.y0 - usedPadding, index: middle - 1, alpha: alpha)
        pushDown(column, from: subject.y1 + usedPadding, index: middle + 1, alpha: alpha)
        pushUp(column, from: extent.maxY, index: column.count - 1, alpha: alpha)
        pushDown(column, from: extent.minY, index: 0, alpha: alpha)
    }

    private mutating func pushDown(_ column: [Int], from start: Double, index: Int, alpha: Double) {
        var y = start
        var k = index
        while k < column.count {
            let i = column[k]
            let dy = (y - nodes[i].y0) * alpha
            if dy > 1e-6 { nodes[i].y0 += dy; nodes[i].y1 += dy }
            y = nodes[i].y1 + usedPadding
            k += 1
        }
    }

    private mutating func pushUp(_ column: [Int], from start: Double, index: Int, alpha: Double) {
        var y = start
        var k = index
        while k >= 0 {
            let i = column[k]
            let dy = (nodes[i].y1 - y) * alpha
            if dy > 1e-6 { nodes[i].y0 -= dy; nodes[i].y1 -= dy }
            y = nodes[i].y0 - usedPadding
            k -= 1
        }
    }

    // MARK: - Link order

    private func byTarget(_ a: Int, _ b: Int) -> Bool {
        let ya = nodes[links[a].target].y0, yb = nodes[links[b].target].y0
        return ya != yb ? ya < yb : a < b
    }

    private func bySource(_ a: Int, _ b: Int) -> Bool {
        let ya = nodes[links[a].source].y0, yb = nodes[links[b].source].y0
        return ya != yb ? ya < yb : a < b
    }

    private mutating func reorderLinks(_ column: [Int]) {
        for i in column {
            nodes[i].sourceLinks.sort(by: byTarget)
            nodes[i].targetLinks.sort(by: bySource)
        }
    }

    /// After a node moves, its neighbours re-stack their links to it.
    private mutating func reorderNodeLinks(_ node: Int) {
        for l in nodes[node].targetLinks {
            let source = links[l].source
            nodes[source].sourceLinks.sort(by: byTarget)
        }
        for l in nodes[node].sourceLinks {
            let target = links[l].target
            nodes[target].targetLinks.sort(by: bySource)
        }
    }

    /// The target.y0 that would make the link from `source` straight.
    private func targetTop(_ source: Int, _ target: Int) -> Double {
        var y = nodes[source].y0 - Double(nodes[source].sourceLinks.count - 1) * usedPadding / 2
        for l in nodes[source].sourceLinks {
            if links[l].target == target { break }
            y += links[l].width + usedPadding
        }
        for l in nodes[target].targetLinks {
            if links[l].source == source { break }
            y -= links[l].width
        }
        return y
    }

    /// The source.y0 that would make the link to `target` straight.
    private func sourceTop(_ source: Int, _ target: Int) -> Double {
        var y = nodes[target].y0 - Double(nodes[target].targetLinks.count - 1) * usedPadding / 2
        for l in nodes[target].targetLinks {
            if links[l].source == source { break }
            y += links[l].width + usedPadding
        }
        for l in nodes[source].sourceLinks {
            if links[l].target == target { break }
            y -= links[l].width
        }
        return y
    }

    private mutating func computeLinkBreadths() {
        for i in nodes.indices {
            var y0 = nodes[i].y0, y1 = nodes[i].y0
            for l in nodes[i].sourceLinks {
                links[l].y0 = y0 + links[l].width / 2
                y0 += links[l].width
            }
            for l in nodes[i].targetLinks {
                links[l].y1 = y1 + links[l].width / 2
                y1 += links[l].width
            }
        }
    }
}
