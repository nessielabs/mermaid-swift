/// Input to the layered (Sugiyama-style) graph layout: sized nodes,
/// directed edges with optional label boxes, and nested clusters.
public struct LayeredGraph: Sendable {
    public enum Direction: String, Sendable, CaseIterable {
        case topToBottom = "TB", bottomToTop = "BT", leftToRight = "LR", rightToLeft = "RL"

        /// Parses Mermaid direction keywords (`TB`, `TD`, `BT`, `LR`, `RL`,
        /// and the arrow forms `v`, `^`, `>`, `<`).
        public init?(keyword: String) {
            switch keyword.uppercased() {
            case "TB", "TD", "V": self = .topToBottom
            case "BT", "^": self = .bottomToTop
            case "LR", ">": self = .leftToRight
            case "RL", "<": self = .rightToLeft
            default: return nil
            }
        }

        var isHorizontal: Bool { self == .leftToRight || self == .rightToLeft }
    }

    public struct Node: Sendable {
        public var id: String
        public var size: Size
        /// The innermost cluster containing the node.
        public var cluster: String?

        public init(id: String, size: Size, cluster: String? = nil) {
            self.id = id
            self.size = size
            self.cluster = cluster
        }
    }

    public struct Edge: Sendable {
        /// Node or cluster ids. An edge that ends at a cluster attaches to the
        /// cluster's box.
        public var from: String
        public var to: String
        /// The size of the edge's label, which gets its own slot in the layout.
        public var labelSize: Size?
        /// The minimum number of ranks the edge spans.
        public var minLength: Int
        /// How strongly the layout keeps the edge short and straight.
        public var weight: Double

        public init(from: String, to: String, labelSize: Size? = nil, minLength: Int = 1, weight: Double = 1) {
            self.from = from
            self.to = to
            self.labelSize = labelSize
            self.minLength = minLength
            self.weight = weight
        }
    }

    public struct Cluster: Sendable {
        public var id: String
        public var parent: String?
        /// The size of the cluster's title, drawn inside its top edge.
        public var labelSize: Size
        /// Lays the cluster out in its own direction when no edge crosses its
        /// boundary, as Mermaid does for subgraphs with a `direction`.
        public var direction: Direction?

        public init(id: String, parent: String? = nil, labelSize: Size = .zero, direction: Direction? = nil) {
            self.id = id
            self.parent = parent
            self.labelSize = labelSize
            self.direction = direction
        }
    }

    public var nodes: [Node] = []
    public var edges: [Edge] = []
    public var clusters: [Cluster] = []
    public var direction: Direction = .topToBottom
    /// Space between adjacent nodes in the same rank.
    public var nodeSpacing: Double = 50
    /// Space between ranks.
    public var rankSpacing: Double = 50
    /// Space between a cluster's border and its contents.
    public var clusterPadding: Double = 15

    public init() {}
}

/// The result of a layered layout, in a coordinate space whose origin is
/// the top left of the laid-out content.
public struct LayeredLayout: Sendable {
    public struct Route: Sendable {
        /// Points from the source's center, through bends, to the target's
        /// center. Callers clip the ends to the endpoint shapes.
        public var points: [Point]
        /// Where the label's center goes, if the edge has one.
        public var labelCenter: Point?
    }

    /// Node frames by id.
    public var nodes: [String: Rect]
    /// Routes in the same order as the input edges.
    public var edges: [Route]
    /// Cluster frames by id, including padding and the title area.
    public var clusters: [String: Rect]
    public var size: Size
}
