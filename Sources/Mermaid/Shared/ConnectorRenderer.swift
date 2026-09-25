/// Draws a routed connector with markers and an optional label.
struct Connector {
    var route: [Point]
    var sourceOutline: [Point]?
    var targetOutline: [Point]?
    var curve: Curve = .basis
    var color: Color
    var width: Double = 1
    var dash: [Double] = []
    var startMarker: Marker = .none
    var endMarker: Marker = .none
    var label: TextBlock?
    var labelCenter: Point?
    var labelColor: Color
    var labelBackground: Color?
    var background: Color
    var id: String?

    func items() -> [SceneItem] {
        var points = EdgeGeometry.clip(route, source: sourceOutline, target: targetOutline)
        guard points.count >= 2 else { return [] }
        let tip = points[points.count - 1], tail = points[0]
        let endDirection = tip - points[points.count - 2]
        let startDirection = tail - points[1]
        points = EdgeGeometry.shortenEnd(points, by: endMarker.inset(lineWidth: width))
        points = EdgeGeometry.shortenStart(points, by: startMarker.inset(lineWidth: width))
        var items: [SceneItem] = [
            .shape(ShapeItem(pathThroughLabel(points), stroke: Stroke(color, width: width, dash: dash, join: .round))),
        ]
        items += endMarker.items(tip: tip, direction: endDirection, color: color, lineWidth: width, background: background)
        items += startMarker.items(tip: tail, direction: startDirection, color: color, lineWidth: width, background: background)
        if let label, !label.isEmpty {
            let center = labelCenter ?? Self.midpoint(of: points)
            if let labelBackground {
                let plate = Rect(center: center, size: Size(label.width + 4, label.height + 2))
                items.append(.shape(ShapeItem(.rect(plate), fill: labelBackground)))
            }
            items.append(.text(TextItem(label, centeredAt: center, color: labelColor)))
        }
        return [.group(GroupItem(id: id, role: "edge", items: items))]
    }

    /// Smooths the route with the curve but pins it to the label anchor, so
    /// a label always sits on its line: B-splines only approximate their
    /// control points, which would let labels drift away from the stroke.
    private func pathThroughLabel(_ points: [Point]) -> Path {
        guard let anchor = labelCenter, let k = points.firstIndex(of: anchor), k > 0, k < points.count - 1 else {
            return curve.path(through: points)
        }
        var path = curve.path(through: Array(points[...k]))
        var tail = curve.path(through: Array(points[k...]))
        if case .move = tail.elements.first { tail = Path.fromElements(Array(tail.elements.dropFirst())) }
        path.append(tail)
        return path
    }

    /// The point halfway along a polyline's length.
    static func midpoint(of points: [Point]) -> Point {
        let lengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
        var remaining = lengths.reduce(0, +) / 2
        for (i, length) in lengths.enumerated() {
            if remaining <= length, length > 0 { return points[i].interpolated(to: points[i + 1], remaining / length) }
            remaining -= length
        }
        return points.last ?? .zero
    }
}
