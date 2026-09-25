extension Array where Element == SceneItem {
    /// Moves the items so their bounds start at the origin, returning the
    /// moved items and their size, ready for `DiagramCanvas`. Diagrams whose
    /// drawing extends in every direction from its anchors (branch badges
    /// left of a git graph, a radial mindmap) lay out freely and then call
    /// this.
    func normalizedToOrigin() -> (items: [SceneItem], size: Size) {
        guard let b = SceneItem.bounds(of: self) else { return (self, .zero) }
        return (map { $0.offsetBy(dx: -b.minX, dy: -b.minY) }, Size(b.width, b.height))
    }
}
