/// A pie chart: labeled, non-negative values drawn as slices of a circle.
public struct PieDiagram: Sendable {
    public struct Slice: Hashable, Sendable {
        public var label: String
        public var value: Double

        public init(label: String, value: Double) {
            self.label = label
            self.value = value
        }
    }

    public static let type = DiagramType.pie

    /// The title from a `title` statement; the front matter title is used
    /// when this is nil.
    public var title: String?
    /// Whether the legend shows each slice's value (`pie showData`).
    public var showData = false
    /// Slices in source order, which is also their clockwise drawing order.
    /// A label that repeats keeps its first value, as in mermaid.js.
    public var slices: [Slice] = []
    public var accessibility = Accessibility()

    public init(title: String? = nil, showData: Bool = false, slices: [Slice] = []) {
        self.title = title
        self.showData = showData
        self.slices = slices
    }

    /// The sum of every slice's value.
    public var total: Double { slices.reduce(0) { $0 + $1.value } }
}
