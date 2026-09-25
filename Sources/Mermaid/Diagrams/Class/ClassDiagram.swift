/// A parsed UML class diagram (`classDiagram` / `classDiagram-v2`).
public struct ClassDiagram: Sendable {
    public static let type = DiagramType.classDiagram

    /// A class box: a name compartment with annotations, then attributes,
    /// then methods.
    public struct Class: Hashable, Sendable {
        public var id: String
        /// The display label from `class A["Label"]`; defaults to the id.
        public var label: String?
        /// The generic parameter from `class A~T~`, without tildes.
        public var genericType: String?
        /// Stereotypes such as `interface`, without `<<` `>>`.
        public var annotations: [String] = []
        public var attributes: [ClassMember] = []
        public var methods: [ClassMember] = []
        /// Style classes from `:::name` and `cssClass`.
        public var cssClasses: [String] = []
        /// Inline declarations from `style` statements.
        public var style = ElementStyle()
        /// The innermost namespace the class was declared in.
        public var namespace: String?
        public var link: String?
        public var linkTarget: String?
        public var tooltip: String?
        /// The function a `callback` or `click ... call` binds; never run.
        public var callback: String?

        public init(id: String) { self.id = id }

        /// The name shown in the box: the label (or id) plus any generic
        /// parameter, with tildes rendered as angle brackets.
        public var displayName: String {
            let base = label ?? id
            guard let genericType, !genericType.isEmpty else { return base }
            return base + "<" + ClassGenerics.render(genericType) + ">"
        }
    }

    /// The decoration at one end of a relation.
    public enum RelationEnd: String, Hashable, Sendable {
        case none
        /// `<|` / `|>`: a hollow triangle (inheritance and realization).
        case inheritance
        /// `*`: a filled diamond.
        case composition
        /// `o`: a hollow diamond.
        case aggregation
        /// `<` / `>`: an arrowhead (association and dependency).
        case association
        /// `()`: a lollipop interface circle.
        case lollipop
    }

    public enum LineStyle: String, Hashable, Sendable { case solid, dashed }

    /// A relation between two classes (or a class and a lollipop interface).
    /// `fromEnd` decorates the `from` side, as `<|--` decorates its left
    /// operand.
    public struct Relation: Hashable, Sendable {
        public var from: String
        public var to: String
        public var fromEnd: RelationEnd
        public var toEnd: RelationEnd
        public var line: LineStyle
        /// Multiplicity written next to `from` (`A "1" --> B`).
        public var fromCardinality: String?
        /// Multiplicity written next to `to` (`A --> "*" B`).
        public var toCardinality: String?
        public var label: String?

        public init(from: String, to: String, fromEnd: RelationEnd = .none, toEnd: RelationEnd = .none,
                    line: LineStyle = .solid, fromCardinality: String? = nil, toCardinality: String? = nil,
                    label: String? = nil) {
            self.from = from
            self.to = to
            self.fromEnd = fromEnd
            self.toEnd = toEnd
            self.line = line
            self.fromCardinality = fromCardinality
            self.toCardinality = toCardinality
            self.label = label
        }
    }

    /// A lollipop interface created by `bar ()-- Foo`: a small circle named
    /// `bar` attached to class `Foo`. Each declaration makes a distinct
    /// interface, as in mermaid.js.
    public struct Interface: Hashable, Sendable {
        /// The node id relations refer to (`interface0`, `interface1`, ...).
        public var id: String
        public var label: String
        public var classID: String
    }

    public struct Note: Hashable, Sendable {
        /// `note0`, `note1`, ... in declaration order.
        public var id: String
        public var text: String
        /// The class a `note for` statement attaches the note to.
        public var target: String?
        public var namespace: String?
    }

    /// A namespace, drawn as a cluster. Dotted names (`A.B`) nest inside
    /// automatically created ancestors.
    public struct Namespace: Hashable, Sendable {
        /// The fully qualified name, such as `Company.Engineering`.
        public var id: String
        public var label: String
        public var parent: String?
        /// False for ancestors created implicitly by a dotted name.
        public var isExplicit: Bool
    }

    public var direction: LayeredGraph.Direction = .topToBottom
    /// Classes in order of first appearance.
    public var classes: [Class] = []
    public var relations: [Relation] = []
    public var interfaces: [Interface] = []
    public var notes: [Note] = []
    /// Namespaces in creation order; parents precede children.
    public var namespaces: [Namespace] = []
    public var classDefinitions: [String: ElementStyle] = [:]
    public var accessibility = Accessibility()

    public init() {}

    public func `class`(_ id: String) -> Class? { classes.first { $0.id == id } }
}
