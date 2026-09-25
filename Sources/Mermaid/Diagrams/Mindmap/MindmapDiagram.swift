/// A parsed mindmap (`mindmap`): a single tree of ideas, built from an
/// indented outline.
public struct MindmapDiagram: Sendable {
    public static let type = DiagramType.mindmap

    /// Node shapes, named after mermaid.js's mindmap node types.
    public enum Shape: String, Hashable, Sendable {
        /// Plain text on a tinted, underlined plate (no brackets).
        case `default`
        /// `[square]`
        case rect
        /// `(rounded)`
        case rounded
        /// `((circle))`
        case circle
        /// `)cloud(`
        case cloud
        /// `))bang((`
        case bang
        /// `{{hexagon}}`
        case hexagon
    }

    public struct Node: Hashable, Sendable {
        public var id: String
        /// Raw label source; markdown strings keep their backticks.
        public var label: String
        public var shape: Shape
        /// Classes from a `:::` line, separated by spaces.
        public var classes: [String] = []
        /// Icon classes from `::icon(...)`, such as `fa fa-book`.
        public var icon: String?
        public var children: [Node] = []

        public init(id: String, label: String, shape: Shape = .default, children: [Node] = []) {
            self.id = id
            self.label = label
            self.shape = shape
            self.children = children
        }

        /// The number of nodes in this subtree.
        public var count: Int { 1 + children.reduce(0) { $0 + $1.count } }
    }

    public var root: Node?
    public var accessibility = Accessibility()

    public init() {}
}
