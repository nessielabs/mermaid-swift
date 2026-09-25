/// A sankey diagram: weighted flows between named nodes.
public struct SankeyDiagram: Sendable {
    public struct Link: Hashable, Sendable {
        /// Index into `nodes`.
        public var source: Int
        public var target: Int
        public var value: Double
        /// Where the link's row starts, for error reporting.
        public var location: SourceLocation?

        public init(source: Int, target: Int, value: Double, location: SourceLocation? = nil) {
            self.source = source
            self.target = target
            self.value = value
            self.location = location
        }
    }

    public static let type = DiagramType.sankey

    /// Node names in order of first appearance.
    public var nodes: [String] = []
    /// Links in source order.
    public var links: [Link] = []
    public var accessibility = Accessibility()

    public init() {}

    /// The index of `name`, adding the node on first use.
    mutating func node(named name: String) -> Int {
        if let index = nodes.firstIndex(of: name) { return index }
        nodes.append(name)
        return nodes.count - 1
    }
}
