extension KanbanDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        let layout = KanbanLayout.compute(self, context: context)
        let theme = context.theme
        let hasTicketLinks = !(context.section("kanban")["ticketBaseUrl"]?.stringValue ?? "").isEmpty
        var items: [SceneItem] = []
        for (k, column) in layout.columns.enumerated() {
            let fill = Self.columnColor(k, theme: theme)
            var group: [SceneItem] = [
                .shape(ShapeItem(.rect(column.frame, cornerRadius: 5), fill: fill, stroke: Stroke(fill))),
                .text(TextItem(column.title, frame: column.titleFrame, color: theme.textColor)),
            ]
            for card in column.cards {
                var cardItems: [SceneItem] = [
                    .shape(ShapeItem(.rect(card.frame, cornerRadius: 5), fill: theme.background,
                                     stroke: Stroke(theme.nodeBorder))),
                ]
                if let priority = card.item.priority, let color = Self.color(for: priority) {
                    let x = card.frame.minX + 2
                    cardItems.append(.shape(ShapeItem(.polyline([Point(x, card.frame.minY + 2), Point(x, card.frame.maxY - 2)]),
                                                      stroke: Stroke(color, width: 4))))
                }
                cardItems.append(.text(TextItem(card.label, frame: card.labelFrame, alignment: .leading, color: theme.textColor)))
                if let ticket = card.ticket, let frame = card.ticketFrame {
                    cardItems.append(.text(TextItem(ticket, frame: frame, alignment: .leading, color: theme.textColor)))
                    if hasTicketLinks, let line = ticket.lines.first {
                        // Tickets link to ticketBaseUrl; underline them like mermaid.
                        let y = frame.minY + line.baseline + 2
                        cardItems.append(.shape(ShapeItem(.polyline([Point(frame.minX, y), Point(frame.minX + line.width, y)]),
                                                          stroke: Stroke(theme.textColor, width: 1))))
                    }
                }
                if let assigned = card.assigned, let frame = card.assignedFrame {
                    cardItems.append(.text(TextItem(assigned, frame: frame, alignment: .trailing, color: theme.textColor)))
                }
                group.append(.group(GroupItem(id: card.item.id, role: "item", items: cardItems)))
            }
            items.append(.group(GroupItem(id: column.column.id, role: "column", items: group)))
        }
        let padding = context.section("kanban")["padding"]?.numberValue ?? 8
        return DiagramCanvas(context: context, margin: padding).scene(content: items, size: layout.size)
    }

    /// mermaid numbers columns from one and styles `.section-<n>` with
    /// `cScale<n+1>`, lightened 10 points (darkened on dark themes).
    static func columnColor(_ index: Int, theme: Theme) -> Color {
        let base = theme.scaleColor(index + 2)
        return theme.background.isDark ? base.darkened(10) : base.lightened(10)
    }

    /// mermaid's priority bar colors; `Medium` draws no bar.
    static func color(for priority: Priority) -> Color? {
        switch priority {
        case .veryHigh: return Color(hex: 0xFF0000)
        case .high: return Color(hex: 0xFFA500)
        case .medium: return nil
        case .low: return Color(hex: 0x0000FF)
        case .veryLow: return Color(hex: 0xADD8E6)
        }
    }
}
