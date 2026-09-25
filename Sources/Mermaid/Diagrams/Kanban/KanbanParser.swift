/// Parses kanban source into a `KanbanDiagram`.
///
/// Kanban is indentation based, like mindmaps: the first node's
/// indentation marks columns, and deeper nodes are items of the column
/// above them. A node is `id`, `id[label]`, or `[label]` (any of the
/// mindmap delimiters are accepted), optionally followed by
/// `@{ ticket: ..., assigned: ..., priority: ... }` metadata that may
/// span lines. `::icon(name)` and `:::class` lines decorate the
/// previous node.
enum KanbanParser {
    private struct Node {
        var id: String
        var label: String
        var metadata: [String: ConfigValue] = [:]
    }

    static func parse(_ source: DiagramSource) throws -> KanbanDiagram {
        var diagram = KanbanDiagram()
        diagram.accessibility = source.accessibility
        var columnLevel: Int?
        var lastIsColumn = true
        var generated = 0
        let lines = source.lines
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.text.hasPrefix("::icon(") {
                let icon = String(line.text.dropFirst(7).prefix { $0 != ")" })
                try decorate(&diagram, lastIsColumn, line) { $0.icon = icon } item: { $0.icon = icon }
                continue
            }
            if line.text.hasPrefix(":::") {
                let classes = line.text.dropFirst(3).split(separator: " ").map(String.init)
                try decorate(&diagram, lastIsColumn, line) { $0.classes += classes } item: { $0.classes += classes }
                continue
            }
            // Metadata may continue onto following lines until its `}`.
            var text = line.text
            if let open = text.range(of: "@{"), !text[open.upperBound...].contains("}") {
                while index < lines.count {
                    // YAML-style lines become comma-separated entries.
                    let next = lines[index].text
                    let separator = next.hasPrefix("}") || text.hasSuffix("{") || text.hasSuffix(",") ? " " : ", "
                    text += separator + next
                    index += 1
                    if lines[index - 1].text.contains("}") { break }
                }
            }
            var node = try parseNode(text, line: line)
            if node.id.isEmpty {
                generated += 1
                node.id = "kbn\(generated)"
            }
            if let label = node.metadata["label"]?.stringValue { node.label = label }

            let level = columnLevel ?? line.indent
            columnLevel = level
            if line.indent < level {
                throw MermaidError.syntax("'\(node.label)' is indented less than the first column", at: line.location)
            }
            if line.indent == level {
                var column = KanbanDiagram.Column(id: node.id, label: node.label)
                column.icon = node.metadata["icon"]?.stringValue
                diagram.columns.append(column)
                lastIsColumn = true
            } else {
                var item = KanbanDiagram.Item(id: node.id, label: node.label)
                item.ticket = node.metadata["ticket"]?.stringValue
                item.assigned = node.metadata["assigned"]?.stringValue
                item.priority = node.metadata["priority"]?.stringValue.flatMap(KanbanDiagram.Priority.init(text:))
                item.icon = node.metadata["icon"]?.stringValue
                diagram.columns[diagram.columns.count - 1].items.append(item)
                lastIsColumn = false
            }
        }
        return diagram
    }

    private static func decorate(_ diagram: inout KanbanDiagram, _ lastIsColumn: Bool, _ line: SourceLine,
                                 column: (inout KanbanDiagram.Column) -> Void,
                                 item: (inout KanbanDiagram.Item) -> Void) throws {
        guard !diagram.columns.isEmpty else {
            throw MermaidError.syntax("Decoration '\(line.text)' has no node to apply to", at: line.location)
        }
        let c = diagram.columns.count - 1
        if lastIsColumn || diagram.columns[c].items.isEmpty {
            column(&diagram.columns[c])
        } else {
            item(&diagram.columns[c].items[diagram.columns[c].items.count - 1])
        }
    }

    /// Opening delimiters and their closers, longest first.
    private static let delimiters: [(open: String, close: String)] = [
        ("((", "))"), ("{{", "}}"), ("))", "(("), ("(-", "-)"), ("-)", "(-"), ("[", "]"), ("(", ")"), (")", "("),
    ]

    private static func parseNode(_ text: String, line: SourceLine) throws -> Node {
        var s = Scanner(text, at: line.location)
        let id = s.read { !"([{)}@".contains($0) }.trimmingWhitespace()
        var node = Node(id: id, label: id)
        if let delimiter = delimiters.first(where: { s.hasPrefix($0.open) }) {
            let start = s.location
            s.advance(by: delimiter.open.count)
            s.skipWhitespace()
            var label: String
            if s.consume("\"`") {
                guard let body = s.read(until: "`\"") else { throw MermaidError.syntax("Unclosed markdown label", at: start) }
                s.advance(by: 2)
                label = "`" + body + "`"
            } else if s.consume("\"") {
                guard let body = s.read(until: "\"") else { throw MermaidError.syntax("Unclosed quoted label", at: start) }
                s.advance()
                label = body
            } else {
                guard let body = s.read(until: delimiter.close) else {
                    throw MermaidError.syntax("Label is missing its closing '\(delimiter.close)'", at: start)
                }
                label = body.trimmingWhitespace()
            }
            s.skipWhitespace()
            guard s.consume(delimiter.close) else {
                throw MermaidError.syntax("Label is missing its closing '\(delimiter.close)'", at: s.location)
            }
            node.label = label
            if node.id.isEmpty { node.id = label }
        }
        s.skipWhitespace()
        if s.hasPrefix("@{") {
            let start = s.location
            s.advance()
            guard let body = s.read(until: "}") else { throw MermaidError.syntax("Metadata is missing its closing '}'", at: start) }
            s.advance()
            do {
                node.metadata = try LenientJSON.parse(body + "}", at: start).objectValue ?? [:]
            } catch let error as MermaidError {
                throw MermaidError.syntax("Invalid metadata: \(error.message)", at: error.location ?? start)
            }
        }
        s.skipWhitespace()
        if s.consume(":::") { _ = s.read { _ in true } }
        guard s.isAtEnd else {
            let location = s.location
            throw MermaidError.syntax("Unexpected '\(s.read { _ in true })' after node '\(node.id)'", at: location)
        }
        guard !node.id.isEmpty || !node.label.isEmpty else {
            throw MermaidError.syntax("Expected a column or item", at: line.location)
        }
        return node
    }
}
