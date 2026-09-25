/// A parsed C4 diagram (`C4Context`, `C4Container`, `C4Component`,
/// `C4Dynamic`, or `C4Deployment`), following the C4-PlantUML macro syntax
/// that mermaid.js implements.
public struct C4Diagram: Sendable {
    public static let type = DiagramType.c4

    /// The header keyword the diagram was declared with.
    public enum Kind: String, Sendable, CaseIterable {
        case context = "C4Context"
        case container = "C4Container"
        case component = "C4Component"
        case dynamic = "C4Dynamic"
        case deployment = "C4Deployment"
    }

    /// Visual overrides from `UpdateElementStyle` or an `AddElementTag` tag.
    public struct ElementStyle: Hashable, Sendable {
        public var background: Color?
        public var font: Color?
        public var border: Color?
        /// A shape keyword such as `RoundedBoxShape`, `EightSidedShape`,
        /// `cylinder`, or `queue`.
        public var shape: String?
        public var shadowing: String?
        public var legendText: String?

        public init() {}

        /// This style with `other`'s set values on top.
        public func overlaid(with other: ElementStyle) -> ElementStyle {
            var result = self
            result.background = other.background ?? background
            result.font = other.font ?? font
            result.border = other.border ?? border
            result.shape = other.shape ?? shape
            result.shadowing = other.shadowing ?? shadowing
            result.legendText = other.legendText ?? legendText
            return result
        }
    }

    /// A person, system, container, or component.
    public struct Element: Hashable, Sendable {
        public enum Category: String, Hashable, Sendable { case person, system, container, component }
        /// The drawn form: a box, a database cylinder, or a queue pipe.
        public enum Form: String, Hashable, Sendable { case box, database, queue }

        public var alias: String
        public var label: String
        public var category: Category
        public var form: Form
        public var isExternal: Bool
        public var technology = ""
        public var description = ""
        public var sprite: String?
        public var tags: [String] = []
        public var link: String?
        /// The alias of the enclosing boundary, or nil at the top level.
        public var boundary: String?
        public var style = ElementStyle()

        public init(alias: String, label: String, category: Category, form: Form = .box, isExternal: Bool = false) {
            self.alias = alias
            self.label = label
            self.category = category
            self.form = form
            self.isExternal = isExternal
        }

        /// Mermaid's element type name, such as `external_system_db`, used for
        /// the `«type»` line and for per-type configuration keys.
        public var typeName: String {
            let base = category.rawValue + (form == .box ? "" : form == .database ? "_db" : "_queue")
            return isExternal ? "external_" + base : base
        }
    }

    /// A boundary or deployment node drawn around its members.
    public struct Boundary: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            /// `Boundary`, `Enterprise_Boundary`, `System_Boundary`, `Container_Boundary`.
            case boundary
            /// `Deployment_Node`/`Node` (`nil`), `Node_L` (`left`), `Node_R` (`right`).
            case deploymentNode(TextItem.Alignment?)
        }

        public var alias: String
        public var label: String
        public var kind: Kind
        /// The bracketed type line, such as `ENTERPRISE` or `Ubuntu 16.04 LTS`.
        public var type: String
        public var description = ""
        public var sprite: String?
        public var tags: [String] = []
        public var link: String?
        public var parent: String?
        public var style = ElementStyle()

        public init(alias: String, label: String, kind: Kind = .boundary, type: String = "", parent: String? = nil) {
            self.alias = alias
            self.label = label
            self.kind = kind
            self.type = type
            self.parent = parent
        }
    }

    /// A relationship between two elements or boundaries.
    public struct Relationship: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            case rel, biRel, up, down, left, right, back
        }

        public var kind: Kind
        public var from: String
        public var to: String
        public var label: String
        public var technology = ""
        public var description = ""
        public var sprite: String?
        public var tags: [String] = []
        public var link: String?
        /// The index given to `RelIndex`; mermaid.js numbers dynamic
        /// diagrams by statement order instead, and so does this renderer.
        public var index: String?
        public var textColor: Color?
        public var lineColor: Color?
        /// `DashedLine()`, `DottedLine()`, or `BoldLine()` from a relationship tag.
        public var lineStyle: String?
        /// Label displacement from `UpdateRelStyle($offsetX, $offsetY)`.
        public var offsetX: Double?
        public var offsetY: Double?

        public init(kind: Kind = .rel, from: String, to: String, label: String) {
            self.kind = kind
            self.from = from
            self.to = to
            self.label = label
        }

        /// Whether an arrowhead is drawn at the target (`to`) end.
        public var arrowAtTarget: Bool { kind != .back }
        /// Whether an arrowhead is drawn at the source (`from`) end.
        public var arrowAtSource: Bool { kind == .biRel || kind == .back }
    }

    /// Relationship overrides declared with `AddRelTag`.
    public struct RelationshipTagStyle: Hashable, Sendable {
        public var textColor: Color?
        public var lineColor: Color?
        public var lineStyle: String?
    }

    public var kind: Kind = .context
    public var title: String?
    /// Elements in declaration order.
    public var elements: [Element] = []
    /// Boundaries in declaration order; parents precede children.
    public var boundaries: [Boundary] = []
    public var relationships: [Relationship] = []
    /// `UpdateLayoutConfig($c4ShapeInRow)`; nil uses the configuration.
    public var shapesPerRow: Int?
    /// `UpdateLayoutConfig($c4BoundaryInRow)`; nil uses the configuration.
    public var boundariesPerRow: Int?
    public var elementTags: [String: ElementStyle] = [:]
    public var relationshipTags: [String: RelationshipTagStyle] = [:]
    public var accessibility = Accessibility()

    public init() {}

    public func element(_ alias: String) -> Element? { elements.first { $0.alias == alias } }
    public func boundary(_ alias: String) -> Boundary? { boundaries.first { $0.alias == alias } }
}
