import Foundation

/// Places mindmap nodes around the root.
///
/// mermaid.js runs a force-directed layout (cose-bilkent) by default, which
/// spreads branches radially around the root. `radial` reproduces that look
/// deterministically: each top-level branch owns an angular wedge sized by
/// its leaf count, every depth lives on a ring, and ring radii grow until
/// no two nodes touch. `tidyTree` (mermaid.js's `layout: tidy-tree`) grows
/// balanced trees to the right and left of the root instead.
struct MindmapLayout {
    struct Item {
        var parent: Int?
        var children: [Int] = []
        var depth: Int
        /// The node's extent around its center (including shape bulges).
        var size: Size
        var center = Point.zero
    }

    enum Algorithm { case radial, tidyTree }

    var items: [Item]
    /// Space between a node and its neighbours.
    var gap = 16.0
    /// Extra distance between rings (radial) or columns (tidy tree), so edges show.
    var levelGap = 36.0

    /// Frames of every node, index-aligned with `items`.
    var frames: [Rect] { items.map { Rect(center: $0.center, size: $0.size) } }

    mutating func run(_ algorithm: Algorithm) {
        guard !items.isEmpty else { return }
        switch algorithm {
        case .radial: radial()
        case .tidyTree: tidyTree()
        }
    }

    /// Leaves below each node; the weight a subtree claims in a tidy tree.
    private func leafCounts() -> [Double] {
        var counts = Array(repeating: 1.0, count: items.count)
        for i in items.indices.reversed() where !items[i].children.isEmpty {
            counts[i] = items[i].children.reduce(0) { $0 + counts[$1] }
        }
        return counts
    }

    // MARK: - Radial

    private mutating func radial() {
        let maxDepth = items.map(\.depth).max() ?? 0
        guard maxDepth > 0 else { return }
        // Each top-level branch keeps its own rings, so one long label or deep
        // branch does not push every other branch outward.
        var branch = Array(repeating: 0, count: items.count)
        for i in items.indices where i > 0 {
            branch[i] = items[i].depth == 1 ? i : branch[items[i].parent ?? 0]
        }
        var angle = Array(repeating: -Double.pi / 2, count: items.count)
        var radius = Array(repeating: 0.0, count: items.count)
        func radialHalf(_ i: Int) -> Double {
            abs(items[i].size.width / 2 * cos(angle[i])) + abs(items[i].size.height / 2 * sin(angle[i]))
        }
        func tangential(_ i: Int) -> Double {
            abs(items[i].size.width * sin(angle[i])) + abs(items[i].size.height * cos(angle[i]))
        }
        let rootHalf = (items[0].size.width * items[0].size.width + items[0].size.height * items[0].size.height).squareRoot() / 2
        func computeRadii() {
            var rings: [Int: [Double]] = [:]
            for b in items[0].children {
                var ring = [0.0]
                for depth in 1...maxDepth {
                    let level = items.indices.filter { branch[$0] == b && items[$0].depth == depth }
                    guard !level.isEmpty else { break }
                    let inner = depth == 1 ? rootHalf
                        : items.indices.filter { branch[$0] == b && items[$0].depth == depth - 1 }.map(radialHalf).max() ?? 0
                    ring.append(ring[depth - 1] + inner + (level.map(radialHalf).max() ?? 0) + levelGap)
                }
                rings[b] = ring
            }
            for i in items.indices where i > 0 { radius[i] = rings[branch[i]]?[items[i].depth] ?? 0 }
        }
        // Angles and ring radii depend on each other; a few rounds settle them.
        for _ in 0..<4 {
            computeRadii()
            angle = angles(radius: radius, tangential: tangential)
        }
        func place(scale: Double) {
            for i in items.indices where i > 0 {
                let r = radius[i] * scale
                items[i].center = Point(r * cos(angle[i]), r * sin(angle[i]))
            }
        }
        // The angular budgets keep branches apart; growing every ring together
        // settles anything the estimates missed.
        var scale = 1.0
        place(scale: scale)
        for _ in 0..<60 where hasOverlap() {
            scale *= 1.06
            angle = angles(radius: radius.map { $0 * scale }, tangential: tangential)
            place(scale: scale)
        }
    }

    /// Angles for every node given ring radii. Each subtree needs the angle
    /// its widest level occupies; top-level branches share the full circle
    /// in proportion to their needs, and deeper children cluster compactly
    /// around their parent's direction within the parent's share.
    private func angles(radius: [Double], tangential: (Int) -> Double) -> [Double] {
        var need = Array(repeating: 0.0, count: items.count)
        for i in items.indices.reversed() where i > 0 {
            let r = max(radius[i], 1)
            let own = min(2 * Double.pi, (tangential(i) + gap) / r)
            need[i] = max(own, items[i].children.reduce(0) { $0 + need[$1] })
        }
        var angle = Array(repeating: -Double.pi / 2, count: items.count)
        var wedgeStart = Array(repeating: -Double.pi / 2, count: items.count)
        var wedge = Array(repeating: 2 * Double.pi, count: items.count)
        for i in items.indices {
            let kids = items[i].children
            guard !kids.isEmpty else { continue }
            let total = kids.reduce(0) { $0 + need[$1] }
            var start: Double
            let factor: Double
            if i == 0 {
                // Spread the top-level branches around the whole circle, the first
                // at the top, sharing spare angle equally so they fan out evenly.
                let slack = max(0, wedge[0] - total) / Double(kids.count)
                var begin = kids.count == 1 ? -Double.pi / 2 - (need[kids[0]] + slack) / 2 : -Double.pi / 2
                let shrink = min(1, wedge[0] / max(total, 1e-9))
                for c in kids {
                    wedge[c] = need[c] * shrink + slack
                    wedgeStart[c] = begin
                    angle[c] = begin + wedge[c] / 2
                    begin += wedge[c]
                }
                continue
            } else {
                factor = min(wedge[i] / max(total, 1e-9), 1.25)
                let span = total * factor
                start = angle[i] - span / 2
                start = min(max(start, wedgeStart[i]), wedgeStart[i] + wedge[i] - span)
            }
            for c in kids {
                wedge[c] = need[c] * factor
                wedgeStart[c] = start
                angle[c] = start + wedge[c] / 2
                start += wedge[c]
            }
        }
        return angle
    }

    func hasOverlap() -> Bool {
        let rects = frames.map { $0.insetBy(dx: -gap / 4, dy: -gap / 4) }
        for i in rects.indices {
            for j in rects.indices where j > i && rects[i].intersects(rects[j]) { return true }
        }
        return false
    }

    // MARK: - Tidy tree

    private mutating func tidyTree() {
        let leaves = leafCounts()
        let children = items[0].children
        // Split top-level branches into right and left halves of similar weight,
        // keeping declaration order (right side first, then left).
        let total = children.reduce(0) { $0 + leaves[$1] }
        var right: [Int] = [], left: [Int] = [], acc = 0.0
        for c in children {
            if acc < total / 2 || right.isEmpty { right.append(c); acc += leaves[c] } else { left.append(c) }
        }
        items[0].center = .zero
        layoutSide(right, direction: 1)
        layoutSide(left, direction: -1)
    }

    /// Stacks subtrees vertically and spaces depths horizontally, columns
    /// sized by the widest node at each depth on this side.
    private mutating func layoutSide(_ roots: [Int], direction: Double) {
        guard !roots.isEmpty else { return }
        var columnWidth: [Int: Double] = [:]
        var stack = roots
        while let i = stack.popLast() {
            columnWidth[items[i].depth] = max(columnWidth[items[i].depth] ?? 0, items[i].size.width)
            stack += items[i].children
        }
        var columnX: [Int: Double] = [:]
        var x = items[0].size.width / 2 + levelGap * 1.5
        for depth in 1...(columnWidth.keys.max() ?? 1) {
            columnX[depth] = x + (columnWidth[depth] ?? 0) / 2
            x += (columnWidth[depth] ?? 0) + levelGap * 1.5
        }
        func extent(_ i: Int) -> Double {
            let own = items[i].size.height + gap
            let kids = items[i].children.reduce(0) { $0 + extent($1) }
            return max(own, kids)
        }
        func place(_ i: Int, top: Double) {
            let e = extent(i)
            items[i].center = Point(direction * (columnX[items[i].depth] ?? 0), top + e / 2)
            let kidsExtent = items[i].children.reduce(0) { $0 + extent($1) }
            var y = top + (e - kidsExtent) / 2
            for c in items[i].children {
                place(c, top: y)
                y += extent(c)
            }
        }
        let height = roots.reduce(0) { $0 + extent($1) }
        var y = -height / 2
        for r in roots {
            place(r, top: y)
            y += extent(r)
        }
    }
}
