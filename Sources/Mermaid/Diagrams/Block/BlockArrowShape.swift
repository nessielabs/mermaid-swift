/// The outline of a block arrow, ported from mermaid.js's `getArrowPoints`
/// so each direction combination gets the same polygon.
enum BlockArrowShape {
    typealias Direction = BlockDiagram.ArrowDirection

    /// The natural size of an arrow around a label. Arrows with a sideways
    /// component use mermaid.js's `block_arrow` proportions (heads as deep
    /// as half the height); purely vertical arrows are drawn taller than
    /// mermaid.js's, whose up and down heads are only a few points deep.
    static func size(_ directions: [Direction], label: Size, padding: Double) -> Size {
        let height = label.height + 2 * padding
        if isVertical(directions) {
            let heads = expanded(directions).count
            return Size(label.width + 2 * padding + 2 * shaftInset, height + Double(heads) * height * 0.6)
        }
        return Size(label.width + height + padding, height)
    }

    static let shaftInset = 8.0

    /// Whether the arrow points only up and/or down.
    static func isVertical(_ directions: [Direction]) -> Bool {
        let set = expanded(directions)
        return !set.isEmpty && set.isSubset(of: [.up, .down])
    }

    /// Where the label goes: the middle of the shaft.
    static func labelCenter(_ directions: [Direction], in frame: Rect) -> Point {
        guard isVertical(directions) else { return frame.center }
        let set = expanded(directions), head = verticalHead(frame)
        let top = set.contains(.up) ? frame.minY + head : frame.minY
        let bottom = set.contains(.down) ? frame.maxY - head : frame.maxY
        return Point(frame.midX, (top + bottom) / 2)
    }

    private static func verticalHead(_ frame: Rect) -> Double {
        min(frame.height * 0.4, frame.width * 0.5)
    }

    /// Normalizes directions: `x` is left and right, `y` is up and down.
    static func expanded(_ directions: [Direction]) -> Set<Direction> {
        var result: Set<Direction> = []
        for d in directions {
            switch d {
            case .x: result.formUnion([.left, .right])
            case .y: result.formUnion([.up, .down])
            default: result.insert(d)
            }
        }
        return result
    }

    /// The polygon for `directions` filling `frame`.
    static func outline(_ directions: [Direction], in frame: Rect, padding nodePadding: Double) -> [Point] {
        let set = expanded(directions)
        let key = [Direction.right, .left, .up, .down].filter(set.contains)
        let p = nodePadding / 2, h = frame.height, w = frame.width, m = h / 2
        // mermaid.js's coordinates run from y = 0 at the bottom up to y = -h.
        let raw: [(Double, Double)]
        switch key {
        case [.right, .left, .up, .down]:
            raw = [(0, 0), (m, 0), (w / 2, 2 * p), (w - m, 0), (w, 0), (w, -h / 3), (w + 2 * p, -h / 2), (w, -2 * h / 3),
                   (w, -h), (w - m, -h), (w / 2, -h - 2 * p), (m, -h), (0, -h), (0, -2 * h / 3), (-2 * p, -h / 2), (0, -h / 3)]
        case [.right, .left, .up]: raw = [(m, 0), (w - m, 0), (w, -h / 2), (w - m, -h), (m, -h), (0, -h / 2)]
        case [.right, .left, .down]: raw = [(0, 0), (m, -h), (w - m, -h), (w, 0)]
        case [.right, .up, .down]: raw = [(0, 0), (w, -m), (w, -h + m), (0, -h)]
        case [.left, .up, .down]: raw = [(w, 0), (0, -m), (0, -h + m), (w, -h)]
        case [.right, .left]:
            raw = [(m, 0), (m, -p), (w - m, -p), (w - m, 0), (w, -h / 2), (w - m, -h), (w - m, -h + p), (m, -h + p),
                   (m, -h), (0, -h / 2)]
        case [.up, .down], [.up], [.down]:
            let d = verticalHead(frame), i = min(shaftInset, w / 4)
            let x0 = frame.minX, x1 = frame.maxX, y0 = frame.minY, y1 = frame.maxY, cx = frame.midX
            let up = set.contains(.up), down = set.contains(.down)
            var points: [Point] = up
                ? [Point(cx, y0), Point(x1, y0 + d), Point(x1 - i, y0 + d)]
                : [Point(x1 - i, y0)]
            points += down
                ? [Point(x1 - i, y1 - d), Point(x1, y1 - d), Point(cx, y1), Point(x0, y1 - d), Point(x0 + i, y1 - d)]
                : [Point(x1 - i, y1), Point(x0 + i, y1)]
            points += up ? [Point(x0 + i, y0 + d), Point(x0, y0 + d)] : [Point(x0 + i, y0)]
            return points
        case [.right, .up]: raw = [(0, 0), (w, -m), (0, -h)]
        case [.right, .down]: raw = [(0, 0), (w, 0), (0, -h)]
        case [.left, .up]: raw = [(w, 0), (0, -m), (w, -h)]
        case [.left, .down]: raw = [(w, 0), (0, 0), (w, -h)]
        case [.right]:
            raw = [(m, -p), (w - m, -p), (w - m, 0), (w, -h / 2), (w - m, -h), (w - m, -h + p), (m, -h + p)]
        case [.left]:
            raw = [(m, 0), (m, -p), (w - m, -p), (w - m, -h + p), (m, -h + p), (m, -h), (0, -h / 2)]
        default:
            return EdgeGeometry.rectOutline(frame)
        }
        return raw.map { Point(frame.minX + $0.0, frame.maxY + $0.1) }
    }
}
