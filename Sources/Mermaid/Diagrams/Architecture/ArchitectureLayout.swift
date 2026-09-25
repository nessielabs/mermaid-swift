/// A grid layout for architecture diagrams that honors edge sides.
///
/// mermaid.js turns each edge's sides into relative-placement constraints
/// (`a:R -- L:b` puts `b` to the right of `a` on the same row) and hands
/// them to a force-directed solver. This layout applies the same
/// constraints on an integer grid, which keeps straight edges straight:
///
/// 1. Groups are laid out bottom-up. Inside a group (and at the top
///    level) the items are its services, junctions, and child groups;
///    an edge between two nested nodes constrains the items containing
///    them at the level where they diverge.
/// 2. `align row|column` directives and then edges, in order, give each
///    item a grid offset from its neighbor. A breadth-first walk assigns
///    cells; a cell that is taken sends the newcomer to the nearest free
///    cell beside it. Disconnected parts sit side by side.
/// 3. Columns and rows are sized to their widest and tallest items and
///    aligned on each item's anchor (a service's icon center), with gaps
///    widened to fit edge labels.
///
/// Groups therefore never overlap, always contain their members, and an
/// edge `a:R -- L:b` always has `b` in a column right of `a`.
struct ArchitectureLayout {
    struct Input {
        /// Frame sizes of services and junctions.
        var nodeSizes: [String: Size]
        /// Where each node's edges meet, relative to its frame's top left.
        var nodeAnchors: [String: Point]
        /// Size of each group's title band.
        var groupHeaders: [String: Size]
        /// Label sizes by edge index.
        var edgeLabels: [Int: Size]
        /// Minimum space between neighboring cells.
        var gap: Double
        /// Space between a group's border and its contents.
        var groupPadding: Double
    }

    struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    var nodes: [String: Rect] = [:]
    var groups: [String: Rect] = [:]
    /// Grid cells per level, keyed by item id, for tests and diagnostics.
    var cells: [String: Cell] = [:]
    var size = Size.zero

    static func compute(_ diagram: ArchitectureDiagram, _ input: Input) -> ArchitectureLayout {
        var layout = ArchitectureLayout()
        layout.size = layout.place(level: nil, diagram: diagram, input: input)
        return layout
    }

    // MARK: - Levels

    /// Lays out the items directly inside `level` with the content's top
    /// left at the origin, returning the content size.
    private mutating func place(level: String?, diagram: ArchitectureDiagram, input: Input) -> Size {
        let items = diagram.declarationOrder.filter { diagram.parent(of: $0) == level }
        guard !items.isEmpty else { return .zero }

        // Child groups first, so their sizes are known.
        var sizes: [String: Size] = [:], anchors: [String: Point] = [:]
        var childContent: [String: (offset: Point, size: Size)] = [:]
        for id in items {
            if diagram.group(id) != nil {
                let content = place(level: id, diagram: diagram, input: input)
                let header = input.groupHeaders[id] ?? .zero
                let pad = input.groupPadding
                let top = header.height > 0 ? header.height + 24 : pad
                let width = max(content.width + 2 * pad, header.width + 24)
                let size = Size(width, content.height + top + pad)
                sizes[id] = size
                anchors[id] = Point(size.width / 2, size.height / 2)
                childContent[id] = (Point((width - content.width) / 2, top), size)
            } else {
                sizes[id] = input.nodeSizes[id] ?? .zero
                anchors[id] = input.nodeAnchors[id] ?? Point((sizes[id]?.width ?? 0) / 2, (sizes[id]?.height ?? 0) / 2)
            }
        }

        let grid = Self.assignCells(items, constraints: constraints(at: level, diagram: diagram))
        for (id, cell) in grid { cells[id] = cell }
        let columns = Array(Set(grid.values.map(\.x))).sorted(), rows = Array(Set(grid.values.map(\.y))).sorted()
        let columnIndex = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($1, $0) })
        let rowIndex = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1, $0) })

        var left = [Double](repeating: 0, count: columns.count), right = left
        var above = [Double](repeating: 0, count: rows.count), below = above
        for id in items {
            guard let cell = grid[id], let c = columnIndex[cell.x], let r = rowIndex[cell.y],
                  let size = sizes[id], let anchor = anchors[id] else { continue }
            left[c] = max(left[c], anchor.x); right[c] = max(right[c], size.width - anchor.x)
            above[r] = max(above[r], anchor.y); below[r] = max(below[r], size.height - anchor.y)
        }
        var columnGaps = [Double](repeating: input.gap, count: max(columns.count - 1, 0))
        var rowGaps = [Double](repeating: input.gap, count: max(rows.count - 1, 0))
        widenGaps(for: level, diagram: diagram, input: input, grid: grid, columnIndex: columnIndex, rowIndex: rowIndex,
                  columnGaps: &columnGaps, rowGaps: &rowGaps)

        let xs = Self.centerlines(before: left, after: right, gaps: columnGaps)
        let ys = Self.centerlines(before: above, after: below, gaps: rowGaps)
        for id in items {
            guard let cell = grid[id], let c = columnIndex[cell.x], let r = rowIndex[cell.y],
                  let size = sizes[id], let anchor = anchors[id] else { continue }
            let frame = Rect(x: xs[c] - anchor.x, y: ys[r] - anchor.y, width: size.width, height: size.height)
            if let content = childContent[id] {
                groups[id] = frame
                translateContents(of: id, by: Point(frame.minX + content.offset.x, frame.minY + content.offset.y),
                                  diagram: diagram)
            } else {
                nodes[id] = frame
            }
        }
        let width = (zip(left, right).map(+).reduce(0, +)) + columnGaps.reduce(0, +)
        let height = (zip(above, below).map(+).reduce(0, +)) + rowGaps.reduce(0, +)
        return Size(width, height)
    }

    /// Moves everything laid out inside `group` (in its local space) to
    /// absolute coordinates.
    private mutating func translateContents(of group: String, by offset: Point, diagram: ArchitectureDiagram) {
        for id in diagram.declarationOrder where diagram.parent(of: id) == group {
            if let frame = nodes[id] { nodes[id] = frame.offsetBy(dx: offset.x, dy: offset.y) }
            if let frame = groups[id] {
                groups[id] = frame.offsetBy(dx: offset.x, dy: offset.y)
                translateContents(of: id, by: offset, diagram: diagram)
            }
        }
    }

    static func centerlines(before: [Double], after: [Double], gaps: [Double]) -> [Double] {
        var result: [Double] = [], position = 0.0
        for i in before.indices {
            position += before[i]
            result.append(position)
            position += after[i] + (i < gaps.count ? gaps[i] : 0)
        }
        return result
    }

    // MARK: - Constraints

    /// A required offset of `to`'s cell from `from`'s cell.
    struct Constraint {
        var from: String
        var to: String
        var dx: Int
        var dy: Int
    }

    /// The grid offset from the source's cell to the target's implied by
    /// the sides an edge uses: leaving through R puts the target to the
    /// right, entering through T puts it below, and so on.
    static func offset(from: ArchitectureDiagram.Side, to: ArchitectureDiagram.Side) -> (dx: Int, dy: Int) {
        func step(_ side: ArchitectureDiagram.Side) -> Int {
            side == .right || side == .bottom ? 1 : -1
        }
        if from.isHorizontal {
            return (step(from), to.isHorizontal ? 0 : -step(to))
        }
        return (to.isHorizontal ? -step(to) : 0, step(from))
    }

    /// The item directly inside `level` that contains `id`, if any.
    static func representative(of id: String, at level: String?, diagram: ArchitectureDiagram) -> String? {
        var current = id
        while true {
            let parent = diagram.parent(of: current)
            if parent == level { return current }
            guard let parent else { return nil }
            current = parent
        }
    }

    private func constraints(at level: String?, diagram: ArchitectureDiagram) -> [Constraint] {
        var result: [Constraint] = []
        func add(_ a: String, _ b: String, _ dx: Int, _ dy: Int) {
            guard let ra = Self.representative(of: a, at: level, diagram: diagram),
                  let rb = Self.representative(of: b, at: level, diagram: diagram), ra != rb else { return }
            result.append(Constraint(from: ra, to: rb, dx: dx, dy: dy))
        }
        for alignment in diagram.alignments {
            for (a, b) in zip(alignment.members, alignment.members.dropFirst()) {
                if alignment.axis == .row { add(a, b, 1, 0) } else { add(a, b, 0, 1) }
            }
        }
        for edge in diagram.edges {
            let (dx, dy) = Self.offset(from: edge.fromSide, to: edge.toSide)
            add(edge.from, edge.to, dx, dy)
        }
        return result
    }

    // MARK: - Grid assignment

    /// Assigns integer cells by walking the constraint graph breadth-first
    /// from each unplaced item in declaration order.
    static func assignCells(_ items: [String], constraints: [Constraint]) -> [String: Cell] {
        var neighbors: [String: [(String, Int, Int)]] = [:]
        for c in constraints {
            neighbors[c.from, default: []].append((c.to, c.dx, c.dy))
            neighbors[c.to, default: []].append((c.from, -c.dx, -c.dy))
        }
        var cells: [String: Cell] = [:]
        var taken: Set<Cell> = []
        for start in items where cells[start] == nil {
            // Each disconnected part starts to the right of everything so far.
            let origin = Cell(x: (cells.values.map(\.x).max() ?? -1) + 1, y: cells.values.map(\.y).min() ?? 0)
            var component: [String: Cell] = [start: origin]
            var componentTaken: Set<Cell> = [origin]
            var queue = [start]
            while !queue.isEmpty {
                let id = queue.removeFirst()
                guard let cell = component[id] else { continue }
                for (next, dx, dy) in neighbors[id] ?? [] where component[next] == nil && cells[next] == nil {
                    let target = nearestFree(to: Cell(x: cell.x + dx, y: cell.y + dy), dx: dx, dy: dy,
                                             taken: componentTaken)
                    component[next] = target
                    componentTaken.insert(target)
                    queue.append(next)
                }
            }
            // Shift the part right until it clears every earlier part.
            let minX = component.values.map(\.x).min() ?? 0
            var shift = origin.x - minX
            while component.values.contains(where: { taken.contains(Cell(x: $0.x + shift, y: $0.y)) }) { shift += 1 }
            for (id, cell) in component {
                let moved = Cell(x: cell.x + shift, y: cell.y)
                cells[id] = moved
                taken.insert(moved)
            }
        }
        return cells
    }

    /// The free cell closest to `cell`, searching across the direction of
    /// travel first, so a second node to the right of `a` lands beside
    /// the first one rather than behind it.
    static func nearestFree(to cell: Cell, dx: Int, dy: Int, taken: Set<Cell>) -> Cell {
        guard taken.contains(cell) else { return cell }
        let across = dy == 0 ? Cell(x: 0, y: 1) : dx == 0 ? Cell(x: 1, y: 0) : Cell(x: dx, y: 0)
        for k in 1... {
            for sign in [1, -1] {
                let candidate = Cell(x: cell.x + across.x * k * sign, y: cell.y + across.y * k * sign)
                if !taken.contains(candidate) { return candidate }
            }
        }
        return cell
    }

    // MARK: - Label room

    /// Widens the gaps an edge label must sit in: horizontal edges need the
    /// label's width between their columns, vertical edges (whose labels
    /// run along the line) need it between their rows.
    private func widenGaps(for level: String?, diagram: ArchitectureDiagram, input: Input, grid: [String: Cell],
                           columnIndex: [Int: Int], rowIndex: [Int: Int],
                           columnGaps: inout [Double], rowGaps: inout [Double]) {
        for (i, edge) in diagram.edges.enumerated() {
            guard let label = input.edgeLabels[i],
                  let ra = Self.representative(of: edge.from, at: level, diagram: diagram),
                  let rb = Self.representative(of: edge.to, at: level, diagram: diagram), ra != rb,
                  let a = grid[ra], let b = grid[rb],
                  let ca = columnIndex[a.x], let cb = columnIndex[b.x], let rowA = rowIndex[a.y], let rowB = rowIndex[b.y]
            else { continue }
            let needed = label.width + 24
            if rowA == rowB, ca != cb {
                let span = min(ca, cb)..<max(ca, cb)
                for g in span { columnGaps[g] = max(columnGaps[g], needed / Double(span.count)) }
            } else if ca == cb, rowA != rowB {
                let span = min(rowA, rowB)..<max(rowA, rowB)
                for g in span { rowGaps[g] = max(rowGaps[g], needed / Double(span.count)) }
            }
        }
    }
}
