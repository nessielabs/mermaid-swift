import Testing
@testable import Mermaid

@Suite("Kanban")
struct KanbanTests {
    let context = RenderContext(measurer: ApproximateTextMeasurer())

    func parse(_ body: String) throws -> KanbanDiagram {
        let prepared = try Preprocessor.prepare("kanban\n" + body)
        return try KanbanParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    let board = """
          Todo
            [Create Documentation]
            docs[Create Blog about the new diagram]
          [In progress]
            id6["Quoted (with) brackets]"]
          id10[Ready for test]
            id4[Create parsing tests]@{ ticket: MC-2038, assigned: 'K.Sveidqvist', priority: 'High' }
            id66[last item]@{ priority: 'Very Low', assigned: knsv }
            id67[numbers]@{ ticket: 2040, priority: 'nonsense' }
        """

    @Test func columnsAndItems() throws {
        let d = try parse(board)
        #expect(d.columns.map(\.id) == ["Todo", "In progress", "id10"])
        #expect(d.columns.map(\.label) == ["Todo", "In progress", "Ready for test"])
        #expect(d.columns[0].items.map(\.id) == ["Create Documentation", "docs"])
        #expect(d.columns[0].items[1].label == "Create Blog about the new diagram")
        #expect(d.columns[1].items[0].label == "Quoted (with) brackets]")
    }

    @Test func metadata() throws {
        let items = try parse(board).columns[2].items
        #expect(items[0].ticket == "MC-2038" && items[0].assigned == "K.Sveidqvist" && items[0].priority == .high)
        #expect(items[1].priority == .veryLow && items[1].assigned == "knsv" && items[1].ticket == nil)
        #expect(items[2].ticket == "2040" && items[2].priority == nil)
    }

    @Test func multilineMetadataAndLabelOverride() throws {
        let d = try parse("""
            c[Column]
              a[Old]@{
                label: "New label"
                priority: "very high"
              }
              b[Next]
            """)
        #expect(d.columns[0].items.map(\.label) == ["New label", "Next"])
        #expect(d.columns[0].items[0].priority == .veryHigh)
    }

    @Test func decorationsAndOtherDelimiters() throws {
        let d = try parse("""
            c((Round column))
            ::icon(fa fa-book)
              a{{Hex item}}
              :::urgent
              b(Rounded)
            """)
        #expect(d.columns[0].label == "Round column" && d.columns[0].icon == "fa fa-book")
        #expect(d.columns[0].items[0].label == "Hex item" && d.columns[0].items[0].classes == ["urgent"])
        #expect(d.columns[0].items[1].label == "Rounded")
    }

    @Test func deeperNestingStillBelongsToTheColumn() throws {
        let d = try parse("  col\n    a\n      b\n  next")
        #expect(d.columns.map(\.id) == ["col", "next"] && d.columns[0].items.map(\.id) == ["a", "b"])
    }

    @Test func locatedErrors() throws {
        let cases: [(String, Int, Int)] = [
            ("    col\n  outdented", 3, 3),
            ("col\n  a[unclosed", 3, 4),
            ("col\n  a[x]@{ ticket: 1", 3, 7),
            ("col\n  a[x] trailing", 3, 8),
            ("::icon(fa)", 2, 1),
        ]
        for (body, line, column) in cases {
            let error = try #require(throws: MermaidError.self, "\(body)") { try parse(body) }
            #expect(error.location == SourceLocation(line: line, column: column), "\(body): \(error)")
        }
    }

    @Test func layoutStacksCardsInsideSideBySideColumns() throws {
        let layout = KanbanLayout.compute(try parse(board), context: context)
        let columns = layout.columns
        #expect(zip(columns, columns.dropFirst()).allSatisfy { $0.frame.maxX < $1.frame.minX })
        #expect(columns.allSatisfy { $0.frame.minY == 0 && $0.frame.width == 200 })
        for column in columns {
            #expect(column.titleFrame.maxY <= (column.cards.first?.frame.minY ?? .infinity))
            for card in column.cards {
                #expect(column.frame.insetBy(dx: 1, dy: 1).contains(card.frame.origin))
                #expect(card.frame.maxY < column.frame.maxY && card.frame.maxX < column.frame.maxX)
                #expect(card.frame.contains(card.labelFrame.center))
                if let ticket = card.ticketFrame, let assigned = card.assignedFrame {
                    #expect(ticket.maxX < assigned.minX && ticket.minY >= card.labelFrame.maxY)
                    #expect(assigned.maxY <= card.frame.maxY)
                }
            }
            #expect(zip(column.cards, column.cards.dropFirst()).allSatisfy { $0.frame.maxY < $1.frame.minY })
        }
    }

    @Test func configuredColumnWidthAndColors() throws {
        var wide = context
        wide.config = .object(["kanban": .object(["sectionWidth": .number(260)])])
        #expect(KanbanLayout.compute(try parse(board), context: wide).columns[0].frame.width == 260)
        #expect(KanbanDiagram.columnColor(0, theme: .default) == Theme.default.scaleColor(2).lightened(10))
        #expect(KanbanDiagram.color(for: .medium) == nil && KanbanDiagram.color(for: .veryHigh) == Color(hex: 0xFF0000))
    }

    @Test func rendersThroughTheRegistry() throws {
        #expect(Mermaid.detectType("kanban\n  todo") == .kanban)
        let scene = try Mermaid.render("kanban\n" + board, options: RenderOptions(measurer: ApproximateTextMeasurer()))
        #expect(scene.svg.contains(">MC-2038</text>") && scene.svg.contains(">Ready for test</text>"))
    }
}
