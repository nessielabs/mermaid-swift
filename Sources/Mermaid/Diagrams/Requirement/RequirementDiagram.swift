/// A parsed requirement diagram (`requirementDiagram`), in the SysML v1.6
/// style mermaid.js implements: requirements, the elements that satisfy
/// or verify them, and typed relationships between the two.
public struct RequirementDiagram: Sendable {
    public static let type = DiagramType.requirement

    /// The kind of requirement, displayed as its stereotype.
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case requirement = "Requirement"
        case functionalRequirement = "Functional Requirement"
        case interfaceRequirement = "Interface Requirement"
        case performanceRequirement = "Performance Requirement"
        case physicalRequirement = "Physical Requirement"
        case designConstraint = "Design Constraint"

        /// The keyword that declares this kind, such as `designConstraint`.
        public var keyword: String {
            switch self {
            case .requirement: return "requirement"
            case .functionalRequirement: return "functionalRequirement"
            case .interfaceRequirement: return "interfaceRequirement"
            case .performanceRequirement: return "performanceRequirement"
            case .physicalRequirement: return "physicalRequirement"
            case .designConstraint: return "designConstraint"
            }
        }
    }

    public enum Risk: String, Hashable, Sendable, CaseIterable {
        case low = "Low", medium = "Medium", high = "High"
    }

    public enum VerifyMethod: String, Hashable, Sendable, CaseIterable {
        case analysis = "Analysis", demonstration = "Demonstration", inspection = "Inspection", test = "Test"
    }

    public struct Requirement: Hashable, Sendable {
        public var name: String
        public var kind: Kind
        /// The requirement's identifier (`id:`), which may be empty.
        public var id = ""
        public var text = ""
        public var risk: Risk?
        public var verifyMethod: VerifyMethod?
        public var classes: [String] = []
        public var style = ElementStyle()

        public init(name: String, kind: Kind = .requirement) {
            self.name = name
            self.kind = kind
        }
    }

    /// Something outside the requirements (a test, a design, a document)
    /// that relates to them.
    public struct Element: Hashable, Sendable {
        public var name: String
        public var type = ""
        public var docRef = ""
        public var classes: [String] = []
        public var style = ElementStyle()

        public init(name: String) { self.name = name }
    }

    public enum RelationshipType: String, Hashable, Sendable, CaseIterable {
        case contains, copies, derives, satisfies, verifies, refines, traces
    }

    public struct Relationship: Hashable, Sendable {
        public var source: String
        public var target: String
        public var type: RelationshipType

        public init(source: String, target: String, type: RelationshipType) {
            self.source = source
            self.target = target
            self.type = type
        }
    }

    public var direction: LayeredGraph.Direction = .topToBottom
    /// Requirements in declaration order.
    public var requirements: [Requirement] = []
    public var elements: [Element] = []
    public var relationships: [Relationship] = []
    public var classDefinitions: [String: ElementStyle] = [:]
    public var accessibility = Accessibility()

    public init() {}

    public func requirement(_ name: String) -> Requirement? { requirements.first { $0.name == name } }
    public func element(_ name: String) -> Element? { elements.first { $0.name == name } }
}
