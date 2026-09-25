/// A parsed treemap (`treemap` / `treemap-beta`): a hierarchy of sections
/// whose leaves carry values drawn as proportional areas.
public struct TreemapDiagram: Sendable {
    public static let type = DiagramType.treemap

    public struct Node: Hashable, Sendable {
        public var name: String
        /// The leaf value; nil for sections.
        public var value: Double?
        /// The `:::class` selector, if any.
        public var className: String?
        /// Children of a section; empty for leaves.
        public var children: [Node] = []

        public init(name: String, value: Double? = nil, className: String? = nil, children: [Node] = []) {
            self.name = name
            self.value = value
            self.className = className
            self.children = children
        }

        /// Sections are declared without a value, even when they have no children.
        public var isSection: Bool { value == nil }

        /// The node's size: its own value for a leaf, or the sum of its
        /// descendants for a section. Negative values count as zero.
        public var total: Double {
            if let value { return max(0, value) }
            return children.reduce(0) { $0 + $1.total }
        }
    }

    /// Top-level nodes in declaration order.
    public var roots: [Node] = []
    public var classDefinitions: [String: ElementStyle] = [:]
    public var title: String?
    public var accessibility = Accessibility()

    public init() {}
}
