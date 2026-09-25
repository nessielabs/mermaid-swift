/// A parsed sequence diagram (`sequenceDiagram`).
///
/// Participants are listed in the order they are drawn. The body is a tree
/// of statements: messages, notes and activations at the leaves, and
/// blocks (`loop`, `alt`, `par`, `rect`, ...) holding nested statements.
public struct SequenceDiagram: Sendable {
    public static let type = DiagramType.sequence

    /// How a participant is drawn. `participant` and `actor` are the
    /// classic keywords; the rest come from `participant A@{ "type": ... }`.
    public enum ParticipantKind: String, Hashable, Sendable, CaseIterable {
        case participant, actor, boundary, control, entity, database, collections, queue
    }

    public struct Participant: Hashable, Sendable {
        public var id: String
        /// Raw label source; defaults to the id.
        public var label: String
        public var kind: ParticipantKind
        /// Explicit `wrap:`/`nowrap:` choice for the label.
        public var wrap: Bool?
        /// The index into `boxes` of the group this participant belongs to.
        public var box: Int?
        /// Whether the participant first appears mid-diagram (`create`).
        public var isCreated = false
        /// Actor menu entries from `link` and `links` statements.
        public var links: [Link] = []

        public init(id: String, label: String? = nil, kind: ParticipantKind = .participant) {
            self.id = id
            self.label = label ?? id
            self.kind = kind
        }
    }

    public struct Link: Hashable, Sendable {
        public var name: String
        public var url: String
    }

    /// A `box ... end` group of participants.
    public struct Box: Hashable, Sendable {
        public var title: String?
        /// The fill, or nil for a transparent box.
        public var color: Color?
        public var wrap: Bool?
        public var participants: [String] = []
    }

    public enum LineStyle: String, Hashable, Sendable { case solid, dotted }

    /// A decoration at one end of a message line.
    public enum ArrowHead: String, Hashable, Sendable {
        case none
        /// A filled triangle (`->>`).
        case arrow
        /// An open chevron for asynchronous messages (`-)`).
        case async
        /// A cross for lost or destroying messages (`-x`).
        case cross
        /// Half of a filled triangle on the upper or lower side of the line (`-|\`, `-|/`).
        case halfTop, halfBottom
        /// A single barb on the upper or lower side of the line (`-\\`, `-//`).
        case stickTop, stickBottom
    }

    public struct Message: Hashable, Sendable {
        public var from: String
        public var to: String
        /// Raw label source.
        public var text: String
        public var line: LineStyle
        /// The decoration where the message arrives.
        public var head: ArrowHead
        /// The decoration where the message leaves (bidirectional and reverse arrows).
        public var tail: ArrowHead
        /// `+`: the target activates when the message arrives.
        public var activatesTarget = false
        /// `-`: the sender deactivates when the message leaves.
        public var deactivatesSource = false
        /// `()`: the line meets the center of the sender's or target's lifeline.
        public var centralSource = false
        public var centralTarget = false
        /// The message creates its target, whose box is drawn at this message.
        public var createsTarget = false
        /// The message ends the sender's or target's lifeline.
        public var destroysSource = false
        public var destroysTarget = false
        /// Explicit `wrap:`/`nowrap:` choice.
        public var wrap: Bool?
        /// The message's `autonumber` value. Every message is numbered so the
        /// `showSequenceNumbers` setting can reveal them.
        public var number: Double = 0
        /// Whether `autonumber` was on for this message.
        public var showsNumber = false

        public init(from: String, to: String, text: String = "", line: LineStyle = .solid,
                    head: ArrowHead = .arrow, tail: ArrowHead = .none) {
            self.from = from
            self.to = to
            self.text = text
            self.line = line
            self.head = head
            self.tail = tail
        }

        public var isSelf: Bool { from == to }
    }

    public struct Note: Hashable, Sendable {
        public enum Placement: Hashable, Sendable {
            case leftOf(String)
            case rightOf(String)
            /// Over one participant, or spanning from the first to the second.
            case over(String, String?)
        }

        public var placement: Placement
        public var text: String
        public var wrap: Bool?

        public init(_ placement: Placement, text: String) {
            self.placement = placement
            self.text = text
        }
    }

    public enum BlockKind: String, Hashable, Sendable {
        case loop, alt, opt, par, parOver = "par_over", critical, `break`, rect

        /// The keyword that starts an additional section, if the kind has sections.
        var sectionKeyword: String? {
            switch self {
            case .alt: return "else"
            case .par, .parOver: return "and"
            case .critical: return "option"
            default: return nil
            }
        }
    }

    /// A control-flow or highlight region. Blocks with several sections
    /// (`alt`/`else`, `par`/`and`, `critical`/`option`) draw a dashed
    /// divider between sections.
    public struct Block: Hashable, Sendable {
        public struct Section: Hashable, Sendable {
            /// Raw condition text; empty when none was given.
            public var label: String
            public var wrap: Bool?
            public var statements: [Statement] = []
        }

        public var kind: BlockKind
        public var sections: [Section]
        /// The fill of a `rect` block, or nil for the theme default.
        public var color: Color?
    }

    public indirect enum Statement: Hashable, Sendable {
        case message(Message)
        case note(Note)
        case activate(String)
        case deactivate(String)
        case block(Block)
    }

    /// Participants in drawing order (order of first appearance).
    public var participants: [Participant] = []
    public var boxes: [Box] = []
    public var statements: [Statement] = []
    /// The `title` statement, if any.
    public var title: String?
    public var accessibility = Accessibility()

    public init() {}

    public func participant(_ id: String) -> Participant? { participants.first { $0.id == id } }

    /// Every message in source order, flattened out of blocks.
    public var messages: [Message] {
        var result: [Message] = []
        func visit(_ statements: [Statement]) {
            for statement in statements {
                switch statement {
                case .message(let message): result.append(message)
                case .block(let block): block.sections.forEach { visit($0.statements) }
                default: break
                }
            }
        }
        visit(statements)
        return result
    }
}
