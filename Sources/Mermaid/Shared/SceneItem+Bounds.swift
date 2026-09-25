import Foundation

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
            guard text.rotation != 0 else { return text.frame }
            let angle = text.rotation * .pi / 180
            let w = abs(text.frame.width * cos(angle)) + abs(text.frame.height * sin(angle))
            let h = abs(text.frame.width * sin(angle)) + abs(text.frame.height * cos(angle))
            return Rect(center: text.frame.center, size: Size(w, h))
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
