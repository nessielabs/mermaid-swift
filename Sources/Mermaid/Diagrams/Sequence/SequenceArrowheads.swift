extension SequenceDiagram.ArrowHead {
    /// The shared marker drawing this head, if it is not a half arrow.
    var marker: Marker? {
        switch self {
        case .none: return Marker.none
        case .arrow: return .arrow
        case .async: return .openArrow
        case .cross: return .cross
        case .halfTop, .halfBottom, .stickTop, .stickBottom: return nil
        }
    }

    /// How far the line stops short of the tip.
    func inset(lineWidth: Double) -> Double {
        if let marker { return marker.inset(lineWidth: lineWidth) }
        return lineWidth / 2
    }

    /// The head's shapes for a line ending at `tip` while travelling in
    /// `direction`. Half arrows put their barb on the upper or lower side
    /// of the line whichever way it travels.
    func items(tip: Point, direction: Point, color: Color, lineWidth: Double, background: Color) -> [SceneItem] {
        if let marker {
            return marker.items(tip: tip, direction: direction, color: color, lineWidth: lineWidth, background: background)
        }
        let d = direction.normalized
        var up = Point(-d.y, d.x)
        if up.y > 0 || (up.y == 0 && up.x < 0) { up = up * -1 }
        let size = 10.0
        let side = (self == .halfTop || self == .stickTop) ? up : up * -1
        let base = tip - d * size
        let barb = base + side * (size * 0.6)
        switch self {
        case .halfTop, .halfBottom:
            return [.shape(ShapeItem(.polygon([tip, barb, base]), fill: color, stroke: Stroke(color, width: 1, join: .miter)))]
        default:
            return [.shape(ShapeItem(.polyline([barb, tip]), stroke: Stroke(color, width: lineWidth, cap: .round)))]
        }
    }
}
