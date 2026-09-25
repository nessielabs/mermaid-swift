/// An entity drawn as a table: a header with its name over one row per
/// attribute, in aligned columns (type | name | keys | comment).
///
/// Metrics follow mermaid.js' `erBox`: every column is its widest cell
/// plus `columnPadding`, every row its tallest cell plus `rowPadding`,
/// and the keys and comment columns appear only when some row uses them.
/// An entity without attributes is a plain box with its name centered.
struct EntityBox {
    /// Colors for the table, already resolved from theme and styles.
    struct Paint {
        var header: Color
        var oddRow: Color
        var evenRow: Color
        var stroke: Color
        var strokeWidth: Double
        var dash: [Double]
        var text: Color
        var opacity: Double
    }

    let name: TextBlock
    /// Cells per attribute row: type, name, keys, comment.
    let cells: [[TextBlock]]
    /// Widths of the four columns; zero for an omitted column.
    let columnWidths: [Double]
    let headerHeight: Double
    let rowHeights: [Double]
    let columnPadding: Double
    let size: Size

    init(name: TextBlock, rows: [[TextBlock]], columnPadding: Double, rowPadding: Double,
         minimumSize: Size) {
        self.name = name
        self.columnPadding = columnPadding
        cells = rows
        guard !rows.isEmpty else {
            columnWidths = [0, 0, 0, 0]
            rowHeights = []
            headerHeight = max(name.height + 3 * columnPadding, minimumSize.height)
            size = Size(max(name.width + 2 * columnPadding, minimumSize.width), headerHeight)
            return
        }
        var widths = (0..<4).map { column in
            let widest = rows.map { $0[column].width }.max() ?? 0
            return widest > 0 || column < 2 ? widest + columnPadding : 0
        }
        // A long name widens every present column equally.
        let shortfall = name.width + 2 * columnPadding - widths.reduce(0, +)
        if shortfall > 0 {
            let present = widths.indices.filter { widths[$0] > 0 }
            for i in present { widths[i] += shortfall / Double(present.count) }
        }
        columnWidths = widths
        headerHeight = name.height + rowPadding
        rowHeights = rows.map { row in (row.map(\.height).max() ?? 0) + rowPadding }
        size = Size(widths.reduce(0, +), headerHeight + rowHeights.reduce(0, +))
    }

    /// The table's shapes and text placed in `frame`.
    func items(in frame: Rect, paint: Paint, id: String) -> SceneItem {
        let stroke = paint.strokeWidth > 0 ? Stroke(paint.stroke, width: paint.strokeWidth, dash: paint.dash) : nil
        var items: [SceneItem] = [.shape(ShapeItem(.rect(frame), fill: paint.header, stroke: stroke, opacity: paint.opacity))]
        guard !cells.isEmpty else {
            items.append(.text(TextItem(name, centeredAt: frame.center, color: paint.text)))
            return .group(GroupItem(id: id, role: "entity", items: items))
        }
        let header = Rect(x: frame.minX, y: frame.minY, width: frame.width, height: headerHeight)
        items.append(.text(TextItem(name, centeredAt: header.center, color: paint.text)))
        var y = header.maxY
        var texts: [SceneItem] = []
        for (i, row) in cells.enumerated() {
            let rect = Rect(x: frame.minX, y: y, width: frame.width, height: rowHeights[i])
            // mermaid.js counts the header as row 0, so the first attribute row is odd.
            let fill = i % 2 == 0 ? paint.oddRow : paint.evenRow
            items.append(.shape(ShapeItem(.rect(rect), fill: fill, stroke: stroke, opacity: paint.opacity)))
            var x = frame.minX
            for (column, cell) in row.enumerated() where columnWidths[column] > 0 {
                let cellFrame = Rect(x: x + columnPadding / 2, y: y, width: columnWidths[column] - columnPadding,
                                     height: rect.height)
                texts.append(.text(TextItem(cell, frame: cellFrame, alignment: .leading, color: paint.text)))
                x += columnWidths[column]
            }
            y += rowHeights[i]
        }
        var x = frame.minX
        for width in columnWidths.dropLast() where width > 0 {
            x += width
            if x < frame.maxX - 0.5, let stroke {
                items.append(.shape(ShapeItem(.polyline([Point(x, header.maxY), Point(x, frame.maxY)]), stroke: stroke,
                                              opacity: paint.opacity)))
            }
        }
        if let stroke {
            items.append(.shape(ShapeItem(.rect(frame), stroke: stroke, opacity: paint.opacity)))
        }
        return .group(GroupItem(id: id, role: "entity", items: items + texts))
    }
}
