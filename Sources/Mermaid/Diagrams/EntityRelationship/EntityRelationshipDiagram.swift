/// A parsed entity relationship diagram (`erDiagram`).
public struct EntityRelationshipDiagram: Sendable {
    public static let type = DiagramType.entityRelationship

    /// One row of an entity's attribute table.
    public struct Attribute: Hashable, Sendable {
        /// The attribute's type, such as `string` or `varchar(255)`.
        /// Generic markers are already resolved (`list~int~` is `list<int>`).
        public var type: String
        public var name: String
        /// Key markers such as `PK`, `FK`, and `UK`, in source order.
        public var keys: [String]
        public var comment: String

        public init(type: String, name: String, keys: [String] = [], comment: String = "") {
            self.type = type
            self.name = name
            self.keys = keys
            self.comment = comment
        }
    }

    public struct Entity: Hashable, Sendable {
        public var name: String
        /// The display name given with `NAME[alias]`.
        public var alias: String?
        public var attributes: [Attribute] = []
        public var classes: [String] = []
        public var style = ElementStyle()

        public init(name: String, alias: String? = nil) {
            self.name = name
            self.alias = alias
        }

        /// The text drawn in the entity's header.
        public var label: String { alias ?? name }
    }

    /// How many instances of an entity take part in a relationship.
    public enum Cardinality: String, Hashable, Sendable, CaseIterable {
        case zeroOrOne, exactlyOne, zeroOrMore, oneOrMore
        /// The parent of a multi-dimensional relationship (`u`).
        case mdParent
    }

    public struct Relationship: Hashable, Sendable {
        /// The entity (or subgraph) written first.
        public var from: String
        public var to: String
        /// The cardinality at the `from` end, written before the line.
        public var fromCardinality: Cardinality
        /// The cardinality at the `to` end, written after the line.
        public var toCardinality: Cardinality
        /// Solid (`--`) when the child cannot exist without the parent,
        /// dashed (`..`) otherwise.
        public var identifying: Bool
        public var label: String

        public init(from: String, to: String, fromCardinality: Cardinality, toCardinality: Cardinality,
                    identifying: Bool = true, label: String = "") {
            self.from = from
            self.to = to
            self.fromCardinality = fromCardinality
            self.toCardinality = toCardinality
            self.identifying = identifying
            self.label = label
        }
    }

    /// A titled group of entities (`subgraph id [title] ... end`).
    public struct Subgraph: Hashable, Sendable {
        public var id: String
        public var title: String
        public var parent: String?
        /// Entities placed directly in this subgraph.
        public var entities: [String] = []
        public var direction: LayeredGraph.Direction?
        public var classes: [String] = []
        public var style = ElementStyle()
    }

    public var direction: LayeredGraph.Direction = .topToBottom
    /// Entities in order of first appearance.
    public var entities: [Entity] = []
    public var relationships: [Relationship] = []
    /// Subgraphs in declaration order; parents precede children.
    public var subgraphs: [Subgraph] = []
    public var classDefinitions: [String: ElementStyle] = [:]
    public var accessibility = Accessibility()

    public init() {}

    public func entity(_ name: String) -> Entity? { entities.first { $0.name == name } }
}
