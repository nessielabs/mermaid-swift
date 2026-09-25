/// A quadrant chart: a unit square split into four labeled quadrants with
/// named points plotted inside it.
public struct QuadrantChartDiagram: Sendable {
    /// Per-point overrides from inline styles or a `classDef`.
    public struct PointStyle: Hashable, Sendable {
        public var radius: Double?
        public var color: Color?
        public var strokeColor: Color?
        public var strokeWidth: Double?

        public init(radius: Double? = nil, color: Color? = nil, strokeColor: Color? = nil, strokeWidth: Double? = nil) {
            self.radius = radius
            self.color = color
            self.strokeColor = strokeColor
            self.strokeWidth = strokeWidth
        }

        /// Properties set in `other` win.
        public func overlaid(with other: PointStyle) -> PointStyle {
            PointStyle(radius: other.radius ?? radius, color: other.color ?? color,
                       strokeColor: other.strokeColor ?? strokeColor, strokeWidth: other.strokeWidth ?? strokeWidth)
        }
    }

    public struct Point: Hashable, Sendable {
        /// The label drawn under the point; may be a markdown string.
        public var label: String
        /// Position in the unit square: x grows right, y grows up.
        public var x: Double
        public var y: Double
        public var className: String?
        /// Inline styles, which take precedence over the class styles.
        public var style: PointStyle

        public init(label: String, x: Double, y: Double, className: String? = nil, style: PointStyle = PointStyle()) {
            self.label = label
            self.x = x
            self.y = y
            self.className = className
            self.style = style
        }
    }

    public static let type = DiagramType.quadrantChart

    public var title: String?
    public var xAxisLeft: String?
    public var xAxisRight: String?
    public var yAxisBottom: String?
    public var yAxisTop: String?
    /// Labels of quadrants 1 (top right), 2 (top left), 3 (bottom left)
    /// and 4 (bottom right).
    public var quadrantLabels: [String?] = [nil, nil, nil, nil]
    /// Points in source order.
    public var points: [Point] = []
    public var classes: [String: PointStyle] = [:]
    public var accessibility = Accessibility()

    public init() {}

    /// The point's effective style: inline over class.
    public func resolvedStyle(of point: Point) -> PointStyle {
        let base = point.className.flatMap { classes[$0] } ?? PointStyle()
        return base.overlaid(with: point.style)
    }
}
