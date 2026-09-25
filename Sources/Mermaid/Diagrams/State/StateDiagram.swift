/// A parsed state diagram (`stateDiagram` / `stateDiagram-v2`).
///
/// States are global by id, as in mermaid.js: a state referenced in several
/// places is one state. Composite states contain other states, either
/// directly or through concurrency regions separated by `--`.
public struct StateDiagram: Sendable {
    public static let type = DiagramType.state

    public enum Kind: String, Hashable, Sendable {
        /// An ordinary state, drawn as a rounded box (or a composite frame).
        case state
        /// The pseudo-state `[*]` at the start of a transition.
        case start
        /// The pseudo-state `[*]` at the end of a transition.
        case end
        /// `<<choice>>`: a decision diamond.
        case choice
        /// `<<fork>>`: a bar that splits one transition into several.
        case fork
        /// `<<join>>`: a bar that merges several transitions into one.
        case join
    }

    public struct State: Hashable, Sendable {
        public var id: String
        public var kind: Kind
        /// Descriptions in declaration order, from `id : text` and
        /// `state "text" as id`. The first is the state's title; any others
        /// are drawn below a divider.
        public var descriptions: [String] = []
        /// The composite state or concurrency region directly containing
        /// this state, or nil at the top level.
        public var parent: String?
        /// Whether the state has a body (`state X { ... }`).
        public var isComposite = false
        /// The direction declared inside a composite state's body.
        public var direction: LayeredGraph.Direction?
        public var classes: [String] = []
        public var style = ElementStyle()
        public var link: String?
        public var tooltip: String?

        public init(id: String, kind: Kind = .state, parent: String? = nil) {
            self.id = id
            self.kind = kind
            self.parent = parent
        }

        /// The text drawn as the state's name: its first description, or
        /// its id.
        public var title: String { descriptions.first ?? id }

        /// Description lines drawn below the title, for states that have
        /// more than one description.
        public var body: [String] { Array(descriptions.dropFirst()) }
    }

    /// One concurrency region of a composite state, from the statements
    /// between `--` separators.
    public struct Region: Hashable, Sendable {
        public var id: String
        /// The composite state the region divides.
        public var composite: String
        public var direction: LayeredGraph.Direction?
    }

    public struct Transition: Hashable, Sendable {
        public var from: String
        public var to: String
        public var label: String?

        public init(from: String, to: String, label: String? = nil) {
            self.from = from
            self.to = to
            self.label = label
        }
    }

    public struct Note: Hashable, Sendable {
        public enum Position: String, Hashable, Sendable {
            case left, right
            /// `note "text" as id`, which stands on its own.
            case floating
        }

        public var id: String
        /// The state the note is attached to; nil for a floating note.
        public var target: String?
        public var position: Position
        public var text: String
        /// The container of a floating note; attached notes sit beside
        /// their target.
        public var parent: String?
    }

    /// 1 for `stateDiagram`, 2 for `stateDiagram-v2`. Both render the v2 way.
    public var version = 2
    public var direction: LayeredGraph.Direction = .topToBottom
    /// States in order of first appearance.
    public var states: [State] = []
    public var regions: [Region] = []
    public var transitions: [Transition] = []
    public var notes: [Note] = []
    public var classDefinitions: [String: ElementStyle] = [:]
    /// `hide empty description`, accepted for PlantUML compatibility.
    public var hidesEmptyDescriptions = false
    /// `scale <n> width`, accepted for PlantUML compatibility.
    public var scaleWidth: Double?
    public var accessibility = Accessibility()

    public init() {}

    public func state(_ id: String) -> State? { states.first { $0.id == id } }

    public func region(_ id: String) -> Region? { regions.first { $0.id == id } }

    /// The ids of the states and regions directly inside `container` (nil
    /// for the top level), in declaration order.
    public func children(of container: String?) -> [String] {
        states.filter { $0.parent == container }.map(\.id) + regions.filter { $0.composite == container }.map(\.id)
    }
}
