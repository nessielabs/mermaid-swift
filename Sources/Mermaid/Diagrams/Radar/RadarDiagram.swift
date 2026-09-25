/// A radar (spider) chart: curves of values plotted on axes that radiate
/// from a common center.
public struct RadarDiagram: Sendable {
    public struct Axis: Hashable, Sendable {
        public var id: String
        /// The drawn label; defaults to the id.
        public var label: String

        public init(id: String, label: String? = nil) {
            self.id = id
            self.label = label ?? id
        }
    }

    public struct Curve: Hashable, Sendable {
        public var id: String
        public var label: String
        /// One value per axis, in axis order.
        public var values: [Double]

        public init(id: String, label: String? = nil, values: [Double]) {
            self.id = id
            self.label = label ?? id
            self.values = values
        }
    }

    public enum Graticule: String, Hashable, Sendable {
        /// Concentric circles, with curves drawn as smooth closed splines.
        case circle
        /// Concentric polygons, with curves drawn as polygons.
        case polygon
    }

    public static let type = DiagramType.radar

    public var title: String?
    public var axes: [Axis] = []
    public var curves: [Curve] = []
    public var showLegend = true
    /// The number of graticule rings (at most 32).
    public var ticks = 5
    /// The value at the rim; the largest curve value when nil.
    public var max: Double?
    /// The value at the center.
    public var min = 0.0
    public var graticule = Graticule.circle
    public var accessibility = Accessibility()

    public init() {}

    /// Mermaid caps the ring count; more rings only blur the chart.
    public static let maximumTicks = 32

    /// The value at the rim: `max`, or the largest value of any curve.
    public var resolvedMax: Double {
        max ?? curves.flatMap(\.values).max() ?? 1
    }
}
