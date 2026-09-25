/// A parsed architecture diagram (`architecture-beta`): services and
/// junctions, optionally nested in groups, joined by edges that leave and
/// enter specific sides.
public struct ArchitectureDiagram: Sendable {
    public static let type = DiagramType.architecture

    /// The side of a node an edge attaches to.
    public enum Side: String, Hashable, Sendable, CaseIterable {
        case left = "L", right = "R", top = "T", bottom = "B"

        public var isHorizontal: Bool { self == .left || self == .right }

        /// The unit vector pointing out of the node through this side
        /// (y grows downward).
        public var outward: Point {
            switch self {
            case .left: return Point(-1, 0)
            case .right: return Point(1, 0)
            case .top: return Point(0, -1)
            case .bottom: return Point(0, 1)
            }
        }
    }

    public struct Group: Hashable, Sendable {
        public var id: String
        public var icon: String?
        public var title: String?
        public var parent: String?
    }

    /// A service (an icon with a title) or a junction (an invisible
    /// point where edges meet).
    public struct Node: Hashable, Sendable {
        public enum Kind: Hashable, Sendable { case service, junction }

        public var id: String
        public var kind: Kind
        /// An icon name such as `database` or `logos:aws-s3`.
        public var icon: String?
        /// Text drawn inside the icon box instead of an icon (`service a "Text"`).
        public var iconText: String?
        public var title: String?
        public var parent: String?
    }

    public struct Edge: Hashable, Sendable {
        public var from: String
        public var fromSide: Side
        /// `{group}`: the edge leaves the source's group rather than the source.
        public var fromGroup = false
        public var to: String
        public var toSide: Side
        public var toGroup = false
        /// `<`: an arrowhead points into the source.
        public var arrowAtSource = false
        /// `>`: an arrowhead points into the target.
        public var arrowAtTarget = false
        public var label: String?
    }

    /// An `align row|column` directive.
    public struct Alignment: Hashable, Sendable {
        public enum Axis: String, Hashable, Sendable { case row, column }
        public var axis: Axis
        public var members: [String]
    }

    public var title: String?
    public var groups: [Group] = []
    /// Services and junctions in declaration order.
    public var nodes: [Node] = []
    public var edges: [Edge] = []
    public var alignments: [Alignment] = []
    /// Declaration order of groups and nodes together, which seeds layout.
    public var declarationOrder: [String] = []
    public var accessibility = Accessibility()

    public init() {}

    public func node(_ id: String) -> Node? { nodes.first { $0.id == id } }
    public func group(_ id: String) -> Group? { groups.first { $0.id == id } }

    /// The parent group of a node or group.
    public func parent(of id: String) -> String? { node(id)?.parent ?? group(id)?.parent }
}
