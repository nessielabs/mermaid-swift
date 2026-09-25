/// A parsed flowchart (`flowchart` / `graph`).
public struct FlowchartDiagram: Sendable {
    public static let type = DiagramType.flowchart

    public struct Node: Hashable, Sendable {
        public var id: String
        /// Raw label source; defaults to the id.
        public var label: String
        public var shape: NodeShape
        public var classes: [String] = []
        public var style = ElementStyle()
        public var link: String?
        public var tooltip: String?

        public init(id: String, label: String? = nil, shape: NodeShape = .rect) {
            self.id = id
            self.label = label ?? id
            self.shape = shape
        }
    }

    public struct Link: Hashable, Sendable {
        public enum Stroke: String, Hashable, Sendable { case normal, thick, dotted, invisible }

        public var from: String
        public var to: String
        public var label: String?
        public var stroke: Stroke
        public var startMarker: Marker
        public var endMarker: Marker
        /// Extra ranks requested by longer arrows (`--->` is 2).
        public var length: Int
        public var id: String?
        public var style = ElementStyle()
        public var curve: Curve?

        public init(from: String, to: String, label: String? = nil, stroke: Stroke = .normal,
                    startMarker: Marker = .none, endMarker: Marker = .arrow, length: Int = 1) {
            self.from = from
            self.to = to
            self.label = label
            self.stroke = stroke
            self.startMarker = startMarker
            self.endMarker = endMarker
            self.length = length
        }
    }

    public struct Subgraph: Hashable, Sendable {
        public var id: String
        public var title: String
        public var parent: String?
        /// Node ids placed directly in this subgraph.
        public var nodes: [String] = []
        public var direction: LayeredGraph.Direction?
        public var classes: [String] = []
        public var style = ElementStyle()
    }

    public var direction: LayeredGraph.Direction = .topToBottom
    /// Nodes in order of first appearance.
    public var nodes: [Node] = []
    public var links: [Link] = []
    /// Subgraphs in declaration order; parents precede children.
    public var subgraphs: [Subgraph] = []
    public var classDefinitions: [String: ElementStyle] = [:]
    /// `linkStyle` overrides by link index; `default` applies to all links.
    public var linkStyles: [Int: ElementStyle] = [:]
    public var defaultLinkStyle = ElementStyle()
    public var defaultLinkCurve: Curve?
    public var linkCurves: [Int: Curve] = [:]
    public var accessibility = Accessibility()

    public init() {}

    public func node(_ id: String) -> Node? { nodes.first { $0.id == id } }
}
