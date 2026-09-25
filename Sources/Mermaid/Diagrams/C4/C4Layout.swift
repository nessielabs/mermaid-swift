/// Mermaid's C4 grid layout.
///
/// C4 diagrams are not laid out by a graph algorithm: statement order
/// decides placement. Inside every boundary (and at the top level), the
/// boundary's own elements fill rows of `shapesPerRow`, and its child
/// boundaries follow below in rows of `boundariesPerRow`, each laid out
/// the same way recursively. Boundaries grow to contain their members and
/// header, so boundaries never overlap and always enclose their contents.
struct C4Layout {
    struct Input {
        var elementSizes: [String: Size]
        /// The size of each boundary's title block.
        var headerSizes: [String: Size]
        var shapesPerRow: Int
        var boundariesPerRow: Int
        /// Space between neighboring elements, horizontally and vertically.
        var shapeGap: Size
        /// Space between neighboring boundaries.
        var boundaryGap: Double
        /// Space between a boundary's border and its contents.
        var inset: Double
    }

    var elements: [String: Rect] = [:]
    var boundaries: [String: Rect] = [:]
    var size = Size.zero

    static func compute(_ diagram: C4Diagram, _ input: Input) -> C4Layout {
        var layout = C4Layout()
        layout.size = layout.place(nil, at: .zero, diagram: diagram, input: input)
        return layout
    }

    /// Lays out the contents of `boundary` (nil for the top level) with the
    /// top left at `origin`, returning the space used.
    private mutating func place(_ boundary: String?, at origin: Point, diagram: C4Diagram, input: Input) -> Size {
        let inset = boundary == nil ? 0 : input.inset
        let header = boundary.flatMap { input.headerSizes[$0] } ?? .zero
        var y = origin.y + (boundary == nil ? 0 : inset * 0.6 + header.height + inset)
        var right = origin.x + header.width + 2 * inset
        var placedAny = false

        let members = diagram.elements.filter { $0.boundary == boundary }
        for row in members.chunked(into: input.shapesPerRow) {
            var x = origin.x + inset
            var rowHeight = 0.0
            for element in row {
                let size = input.elementSizes[element.alias] ?? .zero
                elements[element.alias] = Rect(x: x, y: y, width: size.width, height: size.height)
                x += size.width + input.shapeGap.width
                rowHeight = max(rowHeight, size.height)
            }
            right = max(right, x - input.shapeGap.width + inset)
            y += rowHeight + input.shapeGap.height
            placedAny = true
        }

        let children = diagram.boundaries.filter { $0.parent == boundary }
        // Boundaries sit closer to the elements above them than elements
        // sit to each other: their titles already separate them.
        if placedAny, !children.isEmpty { y -= input.shapeGap.height - input.boundaryGap }
        for row in children.chunked(into: input.boundariesPerRow) {
            var x = origin.x + inset
            var rowHeight = 0.0
            for child in row {
                let size = place(child.alias, at: Point(x, y), diagram: diagram, input: input)
                x += size.width + input.boundaryGap
                rowHeight = max(rowHeight, size.height)
            }
            right = max(right, x - input.boundaryGap + inset)
            y += rowHeight + input.shapeGap.height
            placedAny = true
        }
        if placedAny { y -= input.shapeGap.height }
        y += inset
        if boundary != nil, !placedAny { y += inset }
        let size = Size(right - origin.x, y - origin.y)
        if let boundary { boundaries[boundary] = Rect(x: origin.x, y: origin.y, width: size.width, height: size.height) }
        return size
    }
}

private extension Array {
    /// Consecutive slices of at most `size` elements.
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: Swift.max(size, 1)).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
