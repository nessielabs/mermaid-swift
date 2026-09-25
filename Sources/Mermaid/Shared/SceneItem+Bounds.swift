extension SceneItem {
    /// The box covering the item's paths (including half their stroke
    /// width) and text frames. Curve control points count, so the box may be
    /// slightly larger than the ink, which is the safe direction for sizing
    /// a canvas. Nil for an empty group.
    public var bounds: Rect? {
        switch self {
        case .shape(let shape):
            guard let box = shape.path.bounds else { return nil }
            let half = (shape.stroke?.width ?? 0) / 2
            return box.insetBy(dx: -half, dy: -half)
        case .text(let text):
            return text.frame
        case .group(let group):
            return Self.bounds(of: group.items)
        }
    }

    /// The union of the items' bounds, or nil when nothing is drawn.
    public static func bounds(of items: [SceneItem]) -> Rect? {
        let boxes = items.compactMap(\.bounds)
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}
