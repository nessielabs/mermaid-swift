/// Parses mindmap source into a `MindmapDiagram`.
///
/// Each line is a node, an `::icon(...)` decoration or a `:::classes`
/// decoration for the node above. A node's parent is the closest earlier
/// node indented less than it, so unclear indentation resolves the way
/// mermaid.js resolves it.
enum MindmapParser {
    private struct Entry {
        var level: Int
        var node: MindmapDiagram.Node
        var parent: Int?
    }

    static func parse(_ source: DiagramSource) throws -> MindmapDiagram {
        var diagram = MindmapDiagram()
        diagram.accessibility = source.accessibility
        guard source.headerArguments.isEmpty else {
            throw MermaidError.syntax("Unexpected '\(source.headerArguments)' after 'mindmap'", at: source.header.location)
        }
        var entries: [Entry] = []
        for line in joiningMarkdownStrings(source.lines) {
            let text = line.text
            if text.hasPrefix("::icon(") {
                guard !entries.isEmpty else { throw MermaidError.syntax("An icon must follow a node", at: line.location) }
                entries[entries.count - 1].node.icon = try icon(text, line: line)
                continue
            }
            if text.hasPrefix(":::") {
                guard !entries.isEmpty else { throw MermaidError.syntax("Classes must follow a node", at: line.location) }
                entries[entries.count - 1].node.classes += classes(String(text.dropFirst(3)))
                continue
            }
            let node = try node(text, line: line)
            let parent = entries.lastIndex { $0.level < line.indent }
            if parent == nil, !entries.isEmpty {
                throw MermaidError.semantic(
                    "There can be only one root. No parent could be found for (\"\(node.label)\")", at: line.location)
            }
            entries.append(Entry(level: line.indent, node: node, parent: parent))
        }
        var childrenOf: [Int: [Int]] = [:]
        for (index, entry) in entries.enumerated() { if let p = entry.parent { childrenOf[p, default: []].append(index) } }
        func assemble(_ index: Int) -> MindmapDiagram.Node {
            var node = entries[index].node
            node.children = (childrenOf[index] ?? []).map(assemble)
            return node
        }
        diagram.root = entries.isEmpty ? nil : assemble(0)
        return diagram
    }

    /// Markdown strings may span lines; a line with an unpaired backtick is
    /// joined with the following lines until the string closes.
    static func joiningMarkdownStrings(_ lines: [SourceLine]) -> [SourceLine] {
        var result: [SourceLine] = []
        var pending: SourceLine?
        func isOpen(_ text: String) -> Bool { text.filter { $0 == "`" }.count % 2 == 1 }
        for line in lines {
            if var joined = pending {
                joined.text += "\n" + line.text
                if isOpen(joined.text) { pending = joined } else { result.append(joined); pending = nil }
            } else if isOpen(line.text) {
                pending = line
            } else {
                result.append(line)
            }
        }
        if let pending { result.append(pending) }
        return result
    }

    static func classes(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    private static func icon(_ text: String, line: SourceLine) throws -> String {
        guard let close = text.firstIndex(of: ")") else {
            throw MermaidError.syntax("'::icon(' is missing its closing ')'", at: line.location)
        }
        return String(text[text.index(text.startIndex, offsetBy: 7)..<close]).trimmingWhitespace()
    }

    /// Opening delimiters, longest first, with the shape they start.
    private static let openers: [(String, MindmapDiagram.Shape)] = [
        ("((", .circle), ("))", .bang), ("{{", .hexagon), ("(", .rounded), (")", .cloud), ("[", .rect),
    ]
    private static let closers = ["))", "((", "}}", ")", "]", "("]

    static func node(_ text: String, line: SourceLine) throws -> MindmapDiagram.Node {
        var s = Scanner(text, at: line.location)
        let id = s.read { !"([)]{}".contains($0) && $0 != "\n" }.trimmingWhitespace()
        guard let (opener, openShape) = openers.first(where: { s.hasPrefix($0.0) }) else {
            guard !id.isEmpty else { throw MermaidError.syntax("Unexpected '\(s.peek() ?? " ")'", at: s.location) }
            var node = MindmapDiagram.Node(id: id, label: id)
            try decorations(&s, into: &node)
            return node
        }
        let location = s.location
        s.advance(by: opener.count)
        let label: String
        if s.consume("\"`") {
            guard let body = s.read(until: "`\"") else {
                throw MermaidError.syntax("Markdown string is missing its closing `\"", at: location)
            }
            s.advance(by: 2)
            label = "`" + body + "`"
        } else if s.peek() == "`" {
            // A bare backtick string, which mermaid.js also renders as markdown.
            s.advance()
            guard let body = s.read(until: "`") else {
                throw MermaidError.syntax("Markdown string is missing its closing `", at: location)
            }
            s.advance()
            label = "`" + body + "`"
        } else if s.peek() == "\"" {
            label = try s.readQuoted(multiline: true) ?? ""
        } else {
            label = s.read { !")]}(".contains($0) && $0 != "\n" }.trimmingWhitespace()
        }
        guard let closer = closers.first(where: { s.hasPrefix($0) }) else {
            throw MermaidError.syntax("Node '\(id.isEmpty ? label : id)' is missing its closing delimiter", at: location)
        }
        s.advance(by: closer.count)
        // mermaid.js's getType: `(` becomes a cloud unless closed by `)`.
        let shape: MindmapDiagram.Shape = opener == "(" && closer != ")" ? .cloud : openShape
        var node = MindmapDiagram.Node(id: id.isEmpty ? label : id, label: label, shape: shape)
        try decorations(&s, into: &node)
        return node
    }

    /// Leniency beyond mermaid.js: `:::classes` and `::icon(...)` may also
    /// follow a node on its own line.
    private static func decorations(_ s: inout Scanner, into node: inout MindmapDiagram.Node) throws {
        while true {
            s.skipWhitespace()
            if s.isAtEnd { return }
            if s.consume(":::") {
                node.classes += classes(s.read { _ in true })
            } else if s.consume("::icon(") {
                guard let body = s.read(until: ")") else {
                    throw MermaidError.syntax("'::icon(' is missing its closing ')'", at: s.location)
                }
                s.advance()
                node.icon = body.trimmingWhitespace()
            } else {
                throw MermaidError.syntax("Unexpected '\(s.peek()!)' after node", at: s.location)
            }
        }
    }
}
