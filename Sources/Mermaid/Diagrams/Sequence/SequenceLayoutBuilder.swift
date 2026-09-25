/// Computes a `SequenceLayout`. See `SequenceLayout` for the two passes.
struct SequenceLayoutBuilder {
    typealias Diagram = SequenceDiagram

    let diagram: Diagram
    let settings: SequenceSettings
    let measurer: any TextMeasurer

    /// Visible participants in column order.
    var participants: [Diagram.Participant] = []
    var column: [String: Int] = [:]
    var labels: [TextBlock] = []
    /// Horizontal room reserved by each column.
    var widths: [Double] = []
    /// Lifeline x of each column, once the horizontal pass has run.
    var xs: [Double] = []
    /// Space between adjacent columns' lifelines before any constraint widens it.
    var baseGaps: [Double] = []
    /// The height of the head row: the tallest participant head.
    var rowHeight = 0.0

    // Vertical pass state.
    var layout = SequenceLayout()
    var y = 0.0
    /// Open activations per participant: where each starts.
    var openActivations: [String: [Double]] = [:]
    /// The most recent message line, when nothing else has been placed since.
    var lastLine: (from: String, to: String, y: Double)?

    /// Vertical rhythm, tuned so consecutive single-line messages sit about
    /// as far apart as in mermaid.js.
    static let gapBeforeMessage = 16.0
    static let labelToLine = 6.0
    static let gapBeforeNote = 12.0
    static let gapBeforeBlock = 14.0
    static let selfLoopWidth = 30.0
    static let dotRadius = 5.0
    static let crossSize = 16.0

    static func layout(_ diagram: Diagram, settings: SequenceSettings, measurer: any TextMeasurer) -> SequenceLayout {
        var builder = SequenceLayoutBuilder(diagram: diagram, settings: settings, measurer: measurer)
        builder.measureColumns()
        builder.placeColumns()
        return builder.layout
    }

    // MARK: - Text

    func text(_ raw: String, font: Font, wrapAt width: Double?) -> TextBlock {
        TextBlock(LabelParser.parse(raw), font: font, measurer: measurer,
                  maxWidth: width.map { max($0, 20) }, forceWrap: width != nil)
    }

    func wraps(_ explicit: Bool?) -> Bool { explicit ?? settings.wrap }

    /// The label of a message, wrapped (when wrapping is on) to the space
    /// the columns would have without any widening.
    func messageLabel(_ message: Diagram.Message) -> TextBlock {
        guard wraps(message.wrap), let a = column[message.from], let b = column[message.to] else {
            return text(message.text, font: settings.messageFont, wrapAt: nil)
        }
        let span = baseSpan(a, b) - 2 * settings.wrapPadding
        return text(message.text, font: settings.messageFont, wrapAt: a == b ? settings.width : max(settings.width, span))
    }

    func noteText(_ note: Diagram.Note) -> TextBlock {
        guard wraps(note.wrap) else { return text(note.text, font: settings.noteFont, wrapAt: nil) }
        var width = settings.width
        if case .over(let a, let b?) = note.placement, let i = column[a], let j = column[b] {
            width = max(width, baseSpan(i, j) + settings.actorMargin)
        }
        return text(note.text, font: settings.noteFont, wrapAt: width - 2 * settings.noteMargin)
    }

    /// The width a note needs, before it is placed.
    func noteWidth(_ note: Diagram.Note, text: TextBlock) -> Double {
        let natural = text.width + 2 * settings.noteMargin
        switch note.placement {
        case .leftOf(let id), .rightOf(let id):
            return max(column[id].map { widths[$0] } ?? settings.width, natural)
        case .over(let id, nil):
            return max(column[id].map { widths[$0] } ?? settings.width, settings.width, natural)
        case .over:
            return natural
        }
    }

    /// The x-range a note occupies once columns are placed.
    func noteSpan(_ note: Diagram.Note, text: TextBlock) -> (Double, Double) {
        let width = noteWidth(note, text: text)
        let half = settings.actorMargin / 2
        switch note.placement {
        case .rightOf(let id):
            let x = lifeline(id) + half
            return (x, x + width)
        case .leftOf(let id):
            let x = lifeline(id) - half
            return (x - width, x)
        case .over(let id, nil):
            return (lifeline(id) - width / 2, lifeline(id) + width / 2)
        case .over(let a, let b?):
            let lo = min(lifeline(a), lifeline(b)) - half, hi = max(lifeline(a), lifeline(b)) + half
            let extra = max(0, width - (hi - lo)) / 2
            return (lo - extra, hi + extra)
        }
    }

    func lifeline(_ id: String) -> Double { column[id].map { xs[$0] } ?? 0 }

    /// The lifeline distance between two columns before constraints widen it.
    func baseSpan(_ a: Int, _ b: Int) -> Double {
        let (lo, hi) = (min(a, b), max(a, b))
        return baseGaps[lo..<hi].reduce(0, +)
    }
}
