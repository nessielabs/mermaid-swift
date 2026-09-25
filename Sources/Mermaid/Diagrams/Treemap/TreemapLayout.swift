import Foundation

/// A squarified treemap layout, a port of d3-hierarchy's `treemap()` with
/// `treemapSquarify` (golden-ratio aspect target) and per-node padding, so
/// cells land where mermaid.js puts them.
struct TreemapLayout {
    /// A node of the laid-out hierarchy, in pre-order.
    struct Cell: Hashable, Sendable {
        var node: TreemapDiagram.Node
        /// Depth below the virtual root; top-level nodes have depth 1.
        var depth: Int
        /// Pre-order index of the parent cell; nil for the virtual root.
        var parent: Int?
        var value: Double
        var frame: Rect
        var isSection: Bool
        /// Pre-order indices of the child cells, largest first.
        var children: [Int] = []
    }

    /// Space reserved above a section's children for its header.
    var headerHeight = 25.0
    /// Padding inside a section around its children.
    var sectionPadding = 10.0
    /// Gap between sibling cells (`treemap.padding`).
    var innerPadding = 10.0
    /// Round edges to whole points, like d3's `round(true)`.
    var rounds = true

    static let ratio = (1 + 5.0.squareRoot()) / 2

    /// Lays `roots` out in `bounds`. The first cell is a virtual root holding
    /// the top-level nodes; zero-valued nodes are omitted.
    func layout(_ roots: [TreemapDiagram.Node], in bounds: Rect) -> [Cell] {
        var cells: [Cell] = []
        let root = TreemapDiagram.Node(name: "", children: roots)
        build(root, depth: 0, parent: nil, into: &cells)
        cells[0].frame = bounds
        position(0, cells: &cells, outer: 0)
        return cells
    }

    /// Flattens the hierarchy in pre-order, children sorted by descending
    /// value as mermaid.js sorts them.
    private func build(_ node: TreemapDiagram.Node, depth: Int, parent: Int?, into cells: inout [Cell]) {
        let index = cells.count
        let value = node.total
        cells.append(Cell(node: node, depth: depth, parent: parent, value: value, frame: .init(x: 0, y: 0, width: 0, height: 0),
                          isSection: node.isSection && depth > 0))
        let children = node.children.enumerated().filter { $0.element.total > 0 }
            .sorted { $0.element.total != $1.element.total ? $0.element.total > $1.element.total : $0.offset < $1.offset }
        for child in children {
            cells[index].children.append(cells.count)
            build(child.element, depth: depth + 1, parent: index, into: &cells)
        }
    }

    /// d3's `positionNode`: shrink by the padding inherited from the parent,
    /// then tile the children inside this node's own padding.
    private func position(_ index: Int, cells: inout [Cell], outer p: Double) {
        var r = cells[index].frame
        var x0 = r.minX + p, y0 = r.minY + p, x1 = r.maxX - p, y1 = r.maxY - p
        if x1 < x0 { x0 = (x0 + x1) / 2; x1 = x0 }
        if y1 < y0 { y0 = (y0 + y1) / 2; y1 = y0 }
        r = Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        cells[index].frame = rounds ? Self.rounded(r) : r
        let kids = cells[index].children
        guard !kids.isEmpty else { return }
        let inner = innerPadding / 2
        let isRoot = index == 0
        let top = isRoot ? 0 : headerHeight + sectionPadding, side = isRoot ? 0 : sectionPadding
        x0 += side - inner; y0 += top - inner; x1 -= side - inner; y1 -= side - inner
        if x1 < x0 { x0 = (x0 + x1) / 2; x1 = x0 }
        if y1 < y0 { y0 = (y0 + y1) / 2; y1 = y0 }
        squarify(kids, value: cells[index].value, x0: x0, y0: y0, x1: x1, y1: y1, cells: &cells)
        for kid in kids { position(kid, cells: &cells, outer: inner) }
    }

    /// d3's `squarifyRatio`: fills rows of cells while the worst aspect ratio
    /// keeps improving, alternating between horizontal and vertical rows.
    private func squarify(_ nodes: [Int], value total: Double, x0: Double, y0: Double, x1: Double, y1: Double,
                          cells: inout [Cell]) {
        var x0 = x0, y0 = y0
        var value = total
        var i0 = 0, i1 = 0
        let n = nodes.count
        while i0 < n {
            let dx = x1 - x0, dy = y1 - y0
            var sum = cells[nodes[i1]].value
            i1 += 1
            var minValue = sum, maxValue = sum
            let alpha = max(dy / max(dx, 1e-9), dx / max(dy, 1e-9)) / (value * Self.ratio)
            var beta = sum * sum * alpha
            var minRatio = max(maxValue / beta, beta / minValue)
            while i1 < n {
                let v = cells[nodes[i1]].value
                sum += v
                minValue = min(minValue, v)
                maxValue = max(maxValue, v)
                beta = sum * sum * alpha
                let newRatio = max(maxValue / beta, beta / minValue)
                if newRatio > minRatio { sum -= v; break }
                minRatio = newRatio
                i1 += 1
            }
            let row = Array(nodes[i0..<i1])
            if dx < dy {
                let y = value > 0 ? y0 + dy * sum / value : y1
                dice(row, sum: sum, x0: x0, y0: y0, x1: x1, y1: y, cells: &cells)
                y0 = y
            } else {
                let x = value > 0 ? x0 + dx * sum / value : x1
                slice(row, sum: sum, x0: x0, y0: y0, x1: x, y1: y1, cells: &cells)
                x0 = x
            }
            value -= sum
            i0 = i1
        }
    }

    /// Lays a row out left to right.
    private func dice(_ row: [Int], sum: Double, x0: Double, y0: Double, x1: Double, y1: Double, cells: inout [Cell]) {
        let k = sum > 0 ? (x1 - x0) / sum : 0
        var x = x0
        for i in row {
            let w = cells[i].value * k
            cells[i].frame = Rect(x: x, y: y0, width: w, height: y1 - y0)
            x += w
        }
    }

    /// Lays a row out top to bottom.
    private func slice(_ row: [Int], sum: Double, x0: Double, y0: Double, x1: Double, y1: Double, cells: inout [Cell]) {
        let k = sum > 0 ? (y1 - y0) / sum : 0
        var y = y0
        for i in row {
            let h = cells[i].value * k
            cells[i].frame = Rect(x: x0, y: y, width: x1 - x0, height: h)
            y += h
        }
    }

    private static func rounded(_ r: Rect) -> Rect {
        let x0 = r.minX.rounded(), y0 = r.minY.rounded(), x1 = r.maxX.rounded(), y1 = r.maxY.rounded()
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
