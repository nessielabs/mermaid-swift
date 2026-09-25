/// Places blocks on their composites' column grids, following mermaid.js's
/// block layout.
///
/// Within a composite every column has the same width: the widest child's
/// width per column it spans. Blocks fill the grid left to right, wrapping
/// after `columns` columns (a composite without `columns` is one row), and
/// a block wider than the rest of its row overflows it without pushing the
/// next row, as in mermaid.js. Unlike mermaid.js, which gives every block
/// in a composite the height of its tallest child, each row takes the
/// height of its own tallest member, and leaves only grow to the tallest
/// leaf of their row: a big circle or composite no longer stretches every
/// rectangle in the grid.
struct BlockLayout {
    struct Cell {
        var row: Int
        var column: Int
        var span: Int
    }

    let diagram: BlockDiagram
    /// Gap between cells and around a composite's grid (`block.padding`).
    let padding: Double
    /// The natural size of a leaf block.
    let leafSize: (BlockDiagram.Block) -> Size
    /// The height of a composite's title band (0 when it has no label).
    let headerHeight: (BlockDiagram.Block) -> Double

    /// Frames of every block but the root, keyed by id.
    private(set) var frames: [String: Rect] = [:]
    private var intrinsic: [String: Size] = [:]
    private var grids: [String: (cells: [Cell], columns: Int, rows: Int)] = [:]

    init(diagram: BlockDiagram, padding: Double, leafSize: @escaping (BlockDiagram.Block) -> Size,
         headerHeight: @escaping (BlockDiagram.Block) -> Double) {
        self.diagram = diagram
        self.padding = padding
        self.leafSize = leafSize
        self.headerHeight = headerHeight
    }

    /// Lays everything out and returns the root's size.
    mutating func run() -> Size {
        var visiting: Set<String> = []
        let size = measure("root", visiting: &visiting)
        assign("root", frame: Rect(x: 0, y: 0, width: size.width, height: size.height))
        frames["root"] = nil
        // Blocks wider than the rest of their row overflow the grid.
        let extent = frames.values.reduce(Rect(x: 0, y: 0, width: size.width, height: size.height)) { $0.union($1) }
        return Size(extent.maxX + (extent.maxX > size.width ? padding : 0), extent.maxY)
    }

    /// Grid positions of a composite's children, as mermaid.js's
    /// `calculateBlockPosition` walks them.
    func grid(for block: BlockDiagram.Block) -> (cells: [Cell], columns: Int, rows: Int) {
        let spans = block.children.map { diagram.blocks[$0]?.span ?? 1 }
        let items = max(1, spans.reduce(0, +))
        let columns = block.columns.map { max(1, min($0, items)) } ?? items
        var cells: [Cell] = []
        var position = 0
        for span in spans {
            let column = position % columns
            cells.append(Cell(row: position / columns, column: column, span: span))
            position += block.columns == nil ? span : min(span, columns - column)
        }
        return (cells, columns, (cells.map(\.row).max() ?? 0) + 1)
    }

    private func isLeaf(_ block: BlockDiagram.Block) -> Bool { !block.isComposite && !block.isSpace }

    private mutating func measure(_ id: String, visiting: inout Set<String>) -> Size {
        guard let block = diagram.blocks[id] else { return .zero }
        guard block.isComposite else {
            let size = block.isSpace ? .zero : leafSize(block)
            intrinsic[id] = size
            return size
        }
        // A composite that (through a malformed source) contains itself is drawn empty.
        guard visiting.insert(id).inserted else { return .zero }
        defer { visiting.remove(id) }
        let children = block.children.compactMap { diagram.blocks[$0] }
        let sizes = children.map { measure($0.id, visiting: &visiting) }
        let g = grid(for: block)
        grids[id] = g
        var cellWidth = 0.0
        for (child, size) in zip(children, sizes) where !child.isSpace {
            let span = Double(max(1, child.span))
            cellWidth = max(cellWidth, (size.width - padding * (span - 1)) / span)
        }
        let heights = rowHeights(children: children, sizes: sizes, cells: g.cells, rows: g.rows).all
        let width = Double(g.columns) * cellWidth + Double(g.columns + 1) * padding
        let height = heights.reduce(0, +) + Double(g.rows + 1) * padding + headerHeight(block)
        let size = Size(children.isEmpty ? 2 * padding : width, children.isEmpty ? 2 * padding + headerHeight(block) : height)
        intrinsic[id] = size
        return size
    }

    /// Each row's height, and the height of its tallest leaf. A row of only
    /// spaces keeps the height of the tallest leaf anywhere in the grid.
    private func rowHeights(children: [BlockDiagram.Block], sizes: [Size], cells: [Cell],
                            rows: Int) -> (all: [Double], leaves: [Double]) {
        var all = Array(repeating: 0.0, count: rows), leaves = Array(repeating: 0.0, count: rows)
        for (i, child) in children.enumerated() where i < cells.count && !child.isSpace {
            let row = cells[i].row
            all[row] = max(all[row], sizes[i].height)
            if isLeaf(child) { leaves[row] = max(leaves[row], sizes[i].height) }
        }
        let fallback = leaves.max() ?? 0
        return (all.map { $0 == 0 ? fallback : $0 }, leaves)
    }

    private mutating func assign(_ id: String, frame: Rect) {
        frames[id] = frame
        guard let block = diagram.blocks[id], block.isComposite, let g = grids[id] else { return }
        let children = block.children.compactMap { diagram.blocks[$0] }
        let sizes = children.map { intrinsic[$0.id] ?? .zero }
        let rows = rowHeights(children: children, sizes: sizes, cells: g.cells, rows: g.rows)
        var heights = rows.all
        let header = headerHeight(block)
        let extra = max(0, frame.height - header - heights.reduce(0, +) - Double(g.rows + 1) * padding) / Double(g.rows)
        heights = heights.map { $0 + extra }
        let cellWidth = max(0, (frame.width - Double(g.columns + 1) * padding) / Double(g.columns))
        var rowTop = [frame.minY + header + padding]
        for h in heights { rowTop.append(rowTop[rowTop.count - 1] + h + padding) }
        for (i, child) in children.enumerated() where i < g.cells.count {
            let cell = g.cells[i]
            let span = Double(max(1, cell.span))
            let x = frame.minX + padding + Double(cell.column) * (cellWidth + padding)
            let width = span * cellWidth + (span - 1) * padding
            let rowHeight = heights[cell.row]
            let height = child.isComposite ? rowHeight : min(rowHeight, rows.leaves[cell.row] + extra)
            let y = rowTop[cell.row] + (rowHeight - height) / 2
            assign(child.id, frame: Rect(x: x, y: y, width: width, height: height))
        }
    }
}
