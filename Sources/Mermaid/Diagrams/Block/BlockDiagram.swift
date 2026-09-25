/// A parsed block diagram (`block` / `block-beta`): blocks placed by the
/// author on a column grid, nestable in composite blocks, and joined by
/// edges drawn straight between them.
public struct BlockDiagram: Sendable {
    public static let type = DiagramType.block

    /// A direction a block arrow points in.
    public enum ArrowDirection: String, Hashable, Sendable, CaseIterable {
        case right, left, up, down
        /// Both `left` and `right`.
        case x
        /// Both `up` and `down`.
        case y
    }

    public enum Kind: Hashable, Sendable {
        /// A shaped block with a label.
        case node(NodeShape)
        /// A block arrow, `id<["label"]>(right)`.
        case arrow([ArrowDirection])
        /// An empty grid cell (`space`, `space:3` makes three).
        case space
        /// A block containing its own grid (`block ... end`).
        case composite
    }

    public struct Block: Hashable, Sendable {
        public var id: String
        /// Raw label source; nodes default to their id, composites to "".
        public var label: String
        public var kind: Kind
        /// Columns the block spans.
        public var span: Int = 1
        /// The `columns` setting of a composite; nil means one row.
        public var columns: Int?
        /// Child block ids in grid order (composites only).
        public var children: [String] = []
        public var classes: [String] = []
        public var style = ElementStyle()

        public init(id: String, label: String, kind: Kind, span: Int = 1) {
            self.id = id
            self.label = label
            self.kind = kind
            self.span = span
        }

        public var isComposite: Bool { kind == .composite }
        public var isSpace: Bool { kind == .space }
    }

    public struct Edge: Hashable, Sendable {
        public var from: String
        public var to: String
        public var label: String?
        public var stroke: FlowchartDiagram.Link.Stroke
        public var startMarker: Marker
        public var endMarker: Marker
    }

    /// Every block by id, the root composite (`"root"`) included.
    public var blocks: [String: Block] = ["root": Block(id: "root", label: "", kind: .composite)]
    public var edges: [Edge] = []
    public var classDefinitions: [String: ElementStyle] = [:]
    public var accessibility = Accessibility()

    public init() {}

    public var root: Block { blocks["root"] ?? Block(id: "root", label: "", kind: .composite) }

    public func block(_ id: String) -> Block? { blocks[id] }
}
