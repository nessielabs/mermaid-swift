/// Parses treemap source into a `TreemapDiagram`.
///
/// Rows are `"Section"`, `"Leaf": value` (or `"Leaf", value`), either
/// followed by `:::class`, plus `classDef name css` and `title` statements.
/// Indentation builds the hierarchy exactly as mermaid.js's `buildHierarchy`
/// does: a row becomes a child of the nearest preceding section indented
/// less than it, and leaves never take children.
enum TreemapParser {
    private struct Row {
        var level: Int
        var node: TreemapDiagram.Node
        var parent: Int?
    }

    static func parse(_ source: DiagramSource) throws -> TreemapDiagram {
        var diagram = TreemapDiagram()
        diagram.accessibility = source.accessibility
        guard source.headerArguments.isEmpty else {
            throw MermaidError.syntax("Unexpected '\(source.headerArguments)' after 'treemap'", at: source.header.location)
        }
        var rows: [Row] = []
        var stack: [(index: Int, level: Int)] = []
        for line in source.lines {
            let text = line.textWithoutComment
            if let title = PacketParser.titleStatement(text) {
                diagram.title = title
                continue
            }
            if text.hasPrefix("classDef"), text.dropFirst(8).first?.isWhitespace == true {
                let (name, css) = try classDefinition(text, line: line)
                diagram.classDefinitions[name] = (diagram.classDefinitions[name] ?? ElementStyle()).overlaid(with: ElementStyle(css: css))
                continue
            }
            let node = try item(text, line: line)
            while let top = stack.last, top.level >= line.indent { stack.removeLast() }
            rows.append(Row(level: line.indent, node: node, parent: stack.last?.index))
            if node.isSection { stack.append((rows.count - 1, line.indent)) }
        }
        var childrenOf: [Int: [Int]] = [:]
        for (index, row) in rows.enumerated() { childrenOf[row.parent ?? -1, default: []].append(index) }
        func assemble(_ parent: Int) -> [TreemapDiagram.Node] {
            (childrenOf[parent] ?? []).map { index in
                var node = rows[index].node
                node.children = assemble(index)
                return node
            }
        }
        diagram.roots = assemble(-1)
        return diagram
    }

    /// `classDef name fill:#f00,stroke:#333;`
    private static func classDefinition(_ text: String, line: SourceLine) throws -> (String, String) {
        var s = Scanner(text.dropFirst(8), at: line.location(atOffset: 8))
        s.skipWhitespace()
        let location = s.location
        let name = s.read { $0.isWordCharacter || $0 == "-" }
        guard !name.isEmpty else { throw MermaidError.syntax("Expected a class name after 'classDef'", at: location) }
        var css = s.read { _ in true }.trimmingWhitespace()
        while css.hasSuffix(";") { css.removeLast() }
        return (name, css)
    }

    private static func item(_ text: String, line: SourceLine) throws -> TreemapDiagram.Node {
        var s = Scanner(text, at: line.location)
        let start = s.location
        guard let name = try s.readQuoted() else {
            throw MermaidError.syntax("Expected a quoted name such as \"Section\" or \"Leaf\": 10", at: start)
        }
        var node = TreemapDiagram.Node(name: name)
        s.skipWhitespace()
        if !s.hasPrefix(":::"), s.consume(":") || s.consume(",") {
            s.skipWhitespace()
            let location = s.location
            let digits = s.read { $0.isNumber || $0 == "." || $0 == "," || $0 == "_" }
            guard let value = Double(digits.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "_", with: "")) else {
                throw MermaidError.syntax("Expected a number after '\(name)'", at: location)
            }
            node.value = value
            s.skipWhitespace()
        }
        if s.consume(":::") {
            let location = s.location
            let name = s.read { $0.isWordCharacter || $0 == "-" }
            guard !name.isEmpty else { throw MermaidError.syntax("Expected a class name after ':::'", at: location) }
            node.className = name
            s.skipWhitespace()
        }
        if let extra = s.peek() {
            throw MermaidError.syntax("Unexpected '\(extra)' in treemap item", at: s.location)
        }
        return node
    }
}
