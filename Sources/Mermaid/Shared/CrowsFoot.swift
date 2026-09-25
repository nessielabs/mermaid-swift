/// Crow's foot (information engineering) notation drawn where a
/// relationship line meets an entity: bars for "one", a ring for "zero",
/// and three prongs for "many".
///
/// Dimensions follow mermaid.js' ER markers: symbols sit within 36 units
/// of the entity and spread 9 units either side of the line.
public enum CrowsFoot: String, Hashable, Sendable, CaseIterable {
    /// `|o` / `o|`: a bar near the entity and a ring beyond it.
    case zeroOrOne
    /// `||`: two bars.
    case exactlyOne
    /// `}o` / `o{`: prongs at the entity and a ring beyond them.
    case zeroOrMore
    /// `}|` / `|{`: prongs at the entity and a bar beyond them.
    case oneOrMore
    /// `u`: a filled diamond marking the parent of a multi-dimensional
    /// relationship.
    case parent

    /// Half the width of bars and prongs across the line.
    static let spread = 9.0
    static let ringRadius = 6.0
    static let prongLength = 18.0

    /// How far back from the entity the notation reaches, so callers can
    /// keep the line straight over that distance.
    public var reach: Double {
        switch self {
        case .zeroOrOne: return 27
        case .exactlyOne: return 15
        case .zeroOrMore: return 36
        case .oneOrMore: return 24
        case .parent: return 18
        }
    }

    /// The notation for a line that ends at `tip` (on the entity's
    /// outline) while travelling in `direction`. Rings are filled with
    /// `background` so the line does not show through them.
    public func items(tip: Point, direction: Point, color: Color, lineWidth: Double = 1,
                      background: Color) -> [SceneItem] {
        let d = direction.normalized
        let n = Point(-d.y, d.x)
        /// A point `back` units from the tip along the line, `side` across it.
        func at(_ back: Double, _ side: Double = 0) -> Point { tip - d * back + n * side }
        let stroke = Stroke(color, width: lineWidth, cap: .butt)
        func bar(_ back: Double) -> SceneItem {
            .shape(ShapeItem(.polyline([at(back, -Self.spread), at(back, Self.spread)]), stroke: stroke))
        }
        func ring(_ back: Double) -> SceneItem {
            .shape(ShapeItem(.circle(center: at(back), radius: Self.ringRadius), fill: background, stroke: stroke))
        }
        func prongs() -> SceneItem {
            var path = Path.polyline([at(Self.prongLength), at(0, -Self.spread)])
            path.append(.polyline([at(Self.prongLength), at(0, Self.spread)]))
            return .shape(ShapeItem(path, stroke: Stroke(color, width: lineWidth, cap: .round, join: .round)))
        }
        switch self {
        case .zeroOrOne: return [bar(9), ring(21)]
        case .exactlyOne: return [bar(9), bar(15)]
        case .zeroOrMore: return [prongs(), ring(30)]
        case .oneOrMore: return [prongs(), bar(24)]
        case .parent:
            let diamond = Path.polygon([at(1), at(9.5, 6), at(18), at(9.5, -6)])
            return [.shape(ShapeItem(diamond, fill: color, stroke: stroke))]
        }
    }
}
