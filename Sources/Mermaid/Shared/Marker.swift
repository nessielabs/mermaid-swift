/// A decoration drawn at the end of a connector.
public enum Marker: String, Hashable, Sendable {
    case none
    /// A filled triangle (`-->`).
    case arrow
    /// Two strokes forming an open chevron (async messages, `-)`).
    case openArrow
    /// A filled circle (`--o`).
    case circle
    /// A cross (`--x`).
    case cross
    /// A hollow triangle (class inheritance).
    case hollowTriangle
    /// A filled diamond (composition).
    case filledDiamond
    /// A hollow diamond (aggregation).
    case hollowDiamond

    /// How far the connector's stroke must stop short of the tip.
    public func inset(lineWidth: Double) -> Double {
        switch self {
        case .none: return 0
        case .arrow, .hollowTriangle: return size * 0.9
        case .openArrow, .cross: return lineWidth / 2
        case .circle: return size * 0.8
        case .filledDiamond, .hollowDiamond: return size * 1.6
        }
    }

    var size: Double { 10 }

    /// The marker's shapes for a connector ending at `tip` while travelling
    /// in `direction`. Hollow markers fill with `background` so the line
    /// underneath does not show through.
    func items(tip: Point, direction: Point, color: Color, lineWidth: Double, background: Color) -> [SceneItem] {
        let d = direction.normalized
        let n = Point(-d.y, d.x)
        let s = size
        func at(_ back: Double, _ side: Double) -> Point { tip - d * back + n * side }
        let stroke = Stroke(color, width: lineWidth, join: .miter)
        switch self {
        case .none:
            return []
        case .arrow:
            return [.shape(ShapeItem(.polygon([tip, at(s, s / 2), at(s, -s / 2)]), fill: color, stroke: Stroke(color, width: 1)))]
        case .openArrow:
            return [.shape(ShapeItem(.polyline([at(s, s / 2), tip, at(s, -s / 2)]), stroke: Stroke(color, width: lineWidth, cap: .round, join: .round)))]
        case .circle:
            return [.shape(ShapeItem(.circle(center: at(s * 0.4, 0), radius: s * 0.4), fill: color, stroke: Stroke(color, width: 1)))]
        case .cross:
            let c = at(s * 0.4, 0), r = s * 0.4
            var path = Path.polyline([c - d * r - n * r, c + d * r + n * r])
            path.append(.polyline([c - d * r + n * r, c + d * r - n * r]))
            return [.shape(ShapeItem(path, stroke: Stroke(color, width: max(lineWidth, 1.5), cap: .round)))]
        case .hollowTriangle:
            return [.shape(ShapeItem(.polygon([tip, at(s * 1.4, s * 0.7), at(s * 1.4, -s * 0.7)]), fill: background, stroke: stroke))]
        case .filledDiamond, .hollowDiamond:
            let diamond = Path.polygon([tip, at(s * 0.8, s * 0.5), at(s * 1.6, 0), at(s * 0.8, -s * 0.5)])
            return [.shape(ShapeItem(diamond, fill: self == .filledDiamond ? color : background, stroke: stroke))]
        }
    }
}
