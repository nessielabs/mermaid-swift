/// The geometry of a laid-out sequence diagram, in diagram space.
///
/// Layout happens in two passes. The horizontal pass places participant
/// columns so every message label, note and self-message fits between
/// the lifelines it concerns. The vertical pass then walks the statements
/// top to bottom, stacking messages, notes and block frames and tracking
/// activations. Drawing only reads this structure.
struct SequenceLayout {
    typealias Kind = SequenceDiagram.ParticipantKind

    struct Actor {
        var id: String
        var kind: Kind
        var label: TextBlock
        /// The x of the lifeline.
        var x: Double
        /// The horizontal room the column reserves (not the drawn glyph).
        var width: Double
        /// Where the head is drawn: the top row, or mid-diagram when created.
        var head: Rect
        /// The mirrored head below the diagram, if drawn.
        var foot: Rect?
        var lifelineTop: Double
        var lifelineBottom: Double
        /// Whether a message destroyed the participant at `lifelineBottom`.
        var isDestroyed = false
    }

    struct Message {
        var message: SequenceDiagram.Message
        /// Where the line leaves and arrives. Equal x values for self-messages.
        var start: Point
        var end: Point
        /// The rightmost x of a self-message loop.
        var loopRight: Double?
        var label: TextBlock
        var labelFrame: Rect
        var labelAlignment: TextItem.Alignment
        /// The autonumber badge, when shown.
        var number: (text: TextBlock, center: Point, radius: Double)?
        /// Central-connection dots on the sender's and receiver's lifelines.
        var dots: [Point] = []

        var isSelf: Bool { message.isSelf }
        /// The y of the message line where it leaves the sender.
        var y: Double { start.y }
    }

    struct Note {
        var frame: Rect
        var text: TextBlock
        var alignment: TextItem.Alignment
    }

    struct Frame {
        struct Divider {
            var y: Double
            var label: TextBlock?
            var labelFrame: Rect
        }

        var kind: SequenceDiagram.BlockKind
        var frame: Rect
        /// Nesting depth; outer frames have lower depth and are drawn first.
        var depth: Int
        /// The `rect` fill.
        var fill: Color?
        var tag: TextBlock
        var tagFrame: Rect
        var condition: TextBlock?
        var conditionFrame: Rect
        var dividers: [Divider] = []
    }

    struct Activation {
        var participant: String
        var frame: Rect
        var depth: Int
    }

    struct Group {
        var frame: Rect
        var title: TextBlock?
        var titleFrame: Rect
        var color: Color?
    }

    var actors: [Actor] = []
    var messages: [Message] = []
    var notes: [Note] = []
    var frames: [Frame] = []
    var activations: [Activation] = []
    var groups: [Group] = []

    func actor(_ id: String) -> Actor? { actors.first { $0.id == id } }

    /// Glyph size of the icon-style participants (actor, boundary, control, entity).
    static let glyphSize = Size(40, 40)
    static let glyphGap = 4.0

    /// Whether the kind is drawn as a glyph with its label underneath rather
    /// than as a shape containing the label.
    static func isGlyph(_ kind: Kind) -> Bool {
        switch kind {
        case .actor, .boundary, .control, .entity: return true
        case .participant, .database, .collections, .queue: return false
        }
    }
}
