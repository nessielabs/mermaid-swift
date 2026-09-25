/// The geometry of a kanban board, following mermaid.js: fixed-width
/// columns side by side with their titles on top, and item cards stacked
/// in each column showing the label, then the ticket (left) and assignee
/// (right) beneath it.
struct KanbanLayout {
    struct Card {
        var item: KanbanDiagram.Item
        var frame: Rect
        var label: TextBlock
        var labelFrame: Rect
        var ticket: TextBlock?
        var ticketFrame: Rect?
        var assigned: TextBlock?
        var assignedFrame: Rect?
    }

    struct Column {
        var column: KanbanDiagram.Column
        var frame: Rect
        var title: TextBlock
        var titleFrame: Rect
        var cards: [Card]
    }

    var columns: [Column] = []

    var size: Size {
        Size(columns.map(\.frame.maxX).max() ?? 0, columns.map(\.frame.maxY).max() ?? 0)
    }

    static func compute(_ diagram: KanbanDiagram, context: RenderContext) -> KanbanLayout {
        let config = context.section("kanban")
        let columnWidth = config["sectionWidth"]?.numberValue ?? 200
        let gap = 10.0
        let cardInset = gap * 1.5 / 2
        let cardWidth = columnWidth - 1.5 * gap
        let textPadding = 10.0

        let titles = diagram.columns.map { context.label($0.label, maxWidth: columnWidth - 2 * textPadding, forceWrap: true) }
        let titleArea = max(25, titles.map(\.height).max() ?? 0) + 10

        var layout = KanbanLayout()
        for (k, column) in diagram.columns.enumerated() {
            let x = Double(k) * (columnWidth + gap / 2)
            var y = titleArea
            var cards: [Card] = []
            for item in column.items {
                let label = context.label(item.label, maxWidth: cardWidth - 2 * textPadding, forceWrap: true)
                let small = context.theme.fontSize * 0.875
                let ticket = item.ticket.map { context.label($0, size: small) }
                let assigned = item.assigned.map { context.label($0, size: small) }
                let rowHeight = max(ticket?.height ?? 0, assigned?.height ?? 0)
                let height = label.height + 2 * textPadding + (rowHeight > 0 ? rowHeight + 2 : 0)
                let frame = Rect(x: x + cardInset, y: y, width: cardWidth, height: height)
                let labelFrame = Rect(x: frame.minX + textPadding, y: frame.minY + textPadding,
                                      width: frame.width - 2 * textPadding, height: label.height)
                let rowY = labelFrame.maxY + 2
                cards.append(Card(
                    item: item, frame: frame, label: label, labelFrame: labelFrame,
                    ticket: ticket,
                    ticketFrame: ticket.map { Rect(x: labelFrame.minX, y: rowY, width: $0.width, height: $0.height) },
                    assigned: assigned,
                    assignedFrame: assigned.map { Rect(x: labelFrame.maxX - $0.width, y: rowY, width: $0.width, height: $0.height) }))
                y = frame.maxY + gap / 2
            }
            let height = max(y + 2.5 * gap - (cards.isEmpty ? 0 : gap / 2), 50 + titleArea - 25)
            let title = titles[k]
            layout.columns.append(Column(
                column: column, frame: Rect(x: x, y: 0, width: columnWidth, height: height), title: title,
                titleFrame: Rect(x: x + (columnWidth - title.width) / 2, y: (titleArea - title.height) / 2,
                                 width: title.width, height: title.height),
                cards: cards))
        }
        return layout
    }
}
