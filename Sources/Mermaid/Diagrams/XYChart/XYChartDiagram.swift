/// An XY chart: bar and line series over a categorical or numeric x-axis
/// and a numeric y-axis.
public struct XYChartDiagram: Sendable {
    public enum Orientation: String, Hashable, Sendable {
        /// Categories run left to right and values grow upward.
        case vertical
        /// Categories run top to bottom and values grow rightward.
        case horizontal
    }

    /// A numeric axis range as written; `start` may exceed `end`.
    public struct Range: Hashable, Sendable {
        public var start: Double
        public var end: Double

        public init(_ start: Double, _ end: Double) {
            self.start = start
            self.end = end
        }
    }

    /// The data declared for the x-axis.
    public enum XAxisData: Hashable, Sendable {
        /// `x-axis [jan, feb, mar]`
        case categories([String])
        /// `x-axis 1 --> 12`
        case range(Range)
    }

    public struct Series: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable { case bar, line }

        public var kind: Kind
        /// The legend title; untitled series are left out of the legend.
        public var title: String?
        public var values: [Double]
        /// Per-point labels (`line [540 "PaLM", 65]`), drawn on lines only.
        public var pointLabels: [String?]

        public init(kind: Kind, title: String? = nil, values: [Double], pointLabels: [String?] = []) {
            self.kind = kind
            self.title = title
            self.values = values
            self.pointLabels = pointLabels
        }
    }

    public static let type = DiagramType.xyChart

    public var orientation = Orientation.vertical
    public var title: String?
    public var xAxisTitle: String?
    public var xAxis: XAxisData?
    public var yAxisTitle: String?
    /// An explicit y range (`y-axis 0 --> 100`); inferred from the data
    /// when nil.
    public var yAxisRange: Range?
    /// Series in source order, which also assigns their palette colors.
    public var series: [Series] = []
    public var accessibility = Accessibility()

    public init() {}
}
