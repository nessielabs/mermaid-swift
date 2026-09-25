/// Parses block diagram source into a `BlockDiagram`.
///
/// Statements are free-form, several per line: blocks (`a`, `b["label"]:2`),
/// edges between blocks (`a --> b`, `a -- "text" --> b`), `space[:n]`,
/// `columns n|auto`, composites (`block ... end`, `block:id ... end`,
/// `block:id:2 ... end`), and `classDef`, `class` and `style` lines.
struct BlockParser {
    var scanner: Scanner
    var diagram = BlockDiagram()
    /// Open composites, innermost last, with where they were opened.
    var stack: [(id: String, location: SourceLocation)] = [("root", .start)]
    var generated = 0
    /// `class` and `style` statements, applied once every block exists.
    var deferred: [(ids: [String], classes: [String], style: ElementStyle?, location: SourceLocation)] = []

    init(_ source: DiagramSource) throws {
        scanner = Scanner(source.text)
        diagram.accessibility = source.accessibility
        guard source.headerArguments.isEmpty else {
            throw MermaidError.syntax("Unexpected '\(source.headerArguments)' after '\(Mermaid.headerKeyword(source.header.text))'",
                                      at: source.header.location)
        }
    }

    static func parse(_ source: DiagramSource) throws -> BlockDiagram {
        var parser = try BlockParser(source)
        return try parser.run()
    }

    mutating func run() throws -> BlockDiagram {
        while true {
            scanner.skipWhitespace(newlines: true)
            if scanner.isAtEnd { break }
            try statement()
        }
        if stack.count > 1, let open = stack.last {
            throw MermaidError.syntax("Block '\(open.id)' is missing 'end'", at: open.location)
        }
        try applyDeferred()
        return diagram
    }

    var current: String { stack[stack.count - 1].id }

    mutating func nextID(_ prefix: String) -> String {
        generated += 1
        return "\(prefix)-\(generated)"
    }

    mutating func statement() throws {
        let location = scanner.location
        if scanner.hasPrefix("block:") {
            scanner.advance(by: 6)
            try openComposite(named: true, at: location)
        } else if scanner.consumeKeyword("block", caseInsensitive: false) {
            try openComposite(named: false, at: location)
        } else if scanner.consumeKeyword("end", caseInsensitive: false) {
            guard stack.count > 1 else { throw MermaidError.syntax("'end' without a matching 'block'", at: location) }
            stack.removeLast()
        } else if scanner.consumeKeyword("columns", caseInsensitive: false) {
            scanner.skipWhitespace()
            let valueLocation = scanner.location
            if scanner.consumeKeyword("auto", caseInsensitive: false) {
                diagram.blocks[current]?.columns = nil
            } else if let n = scanner.readInteger(), n > 0 {
                diagram.blocks[current]?.columns = n
            } else {
                throw MermaidError.syntax("'columns' expects a positive number or 'auto'", at: valueLocation)
            }
        } else if scanner.consumeKeyword("space", caseInsensitive: false) {
            var count = 1
            if scanner.peek() == ":", let next = scanner.peek(1), next.isNumber {
                scanner.advance()
                count = scanner.readInteger() ?? 1
            }
            // Like mermaid.js, `space:n` is n single-column spaces.
            for _ in 0..<min(count, 10_000) {
                let id = nextID("space")
                diagram.blocks[id] = .init(id: id, label: "", kind: .space)
                diagram.blocks[current]?.children.append(id)
            }
        } else if scanner.consumeKeyword("classDef", caseInsensitive: false) {
            let (name, css) = splitFirstWord(restOfLine())
            guard !name.isEmpty else { throw MermaidError.syntax("Expected a class name after 'classDef'", at: location) }
            diagram.classDefinitions[name] = (diagram.classDefinitions[name] ?? ElementStyle()).overlaid(with: ElementStyle(css: css))
        } else if scanner.consumeKeyword("class", caseInsensitive: false) {
            let (ids, name) = splitFirstWord(restOfLine())
            deferred.append((Self.list(ids), [name].filter { !$0.isEmpty }, nil, location))
        } else if scanner.consumeKeyword("style", caseInsensitive: false) {
            let (ids, css) = splitFirstWord(restOfLine())
            deferred.append((Self.list(ids), [], ElementStyle(css: css), location))
        } else {
            try nodeStatement()
        }
    }

    // MARK: - Composites

    /// `block`, `block:id`, `block:id:2`, `block:id["label"]:2`. Leniency
    /// beyond mermaid.js: `block:2` (digits only) is an anonymous composite
    /// two columns wide, which is what authors mean by it.
    mutating func openComposite(named: Bool, at location: SourceLocation) throws {
        var composite = BlockDiagram.Block(id: "", label: "", kind: .composite)
        if named {
            guard let token = try BlockNodeScanner.scan(&scanner) else {
                throw MermaidError.syntax("Expected a block id after 'block:'", at: scanner.location)
            }
            if token.id.allSatisfy(\.isNumber), token.label == nil, token.span == nil, let width = Int(token.id) {
                composite.id = nextID("block")
                composite.span = max(1, width)
            } else {
                composite.id = token.id
                composite.label = token.label ?? ""
                composite.span = max(1, token.span ?? 1)
            }
        } else {
            composite.id = nextID("block")
        }
        if let existing = diagram.blocks[composite.id], existing.isComposite {
            throw MermaidError.semantic("Block '\(composite.id)' is already defined", at: location)
        }
        diagram.blocks[composite.id] = composite
        diagram.blocks[current]?.children.append(composite.id)
        stack.append((composite.id, location))
    }

    // MARK: - Blocks and edges

    /// `a`, `a["x"]:2`, `a --> b`, `a -- "label" --> b --> c`.
    mutating func nodeStatement() throws {
        let location = scanner.location
        guard var previous = try node() else {
            let found = scanner.peek().map { "'\($0)'" } ?? "end of input"
            throw MermaidError.syntax("Expected a block but found \(found)", at: location)
        }
        while true {
            var probe = scanner
            probe.skipWhitespace()
            guard let link = try FlowchartLinkScanner.scan(&probe) else { break }
            scanner = probe
            scanner.skipWhitespace()
            let targetLocation = scanner.location
            guard let next = try node() else {
                throw MermaidError.syntax("Expected a block after the link", at: targetLocation)
            }
            diagram.edges.append(.init(from: previous, to: next, label: link.label, stroke: link.stroke,
                                       startMarker: link.startMarker, endMarker: link.endMarker))
            previous = next
        }
    }

    /// Scans a block and records it; a new id joins the current composite's
    /// grid, a known one only takes a new label or shape (as in mermaid.js,
    /// its position and width stay where it was first declared).
    mutating func node() throws -> String? {
        guard let token = try BlockNodeScanner.scan(&scanner) else { return nil }
        if var existing = diagram.blocks[token.id] {
            if let label = token.label { existing.label = label }
            if let kind = token.kind, !existing.isComposite { existing.kind = kind }
            diagram.blocks[token.id] = existing
        } else {
            diagram.blocks[token.id] = .init(id: token.id, label: token.label ?? token.id,
                                             kind: token.kind ?? .node(.rect), span: max(1, token.span ?? 1))
            diagram.blocks[current]?.children.append(token.id)
        }
        return token.id
    }

    // MARK: - Styling

    mutating func applyDeferred() throws {
        for statement in deferred {
            for id in statement.ids {
                guard var block = diagram.blocks[id] else {
                    throw MermaidError.semantic("Unknown block '\(id)'", at: statement.location)
                }
                block.classes += statement.classes
                if let style = statement.style { block.style = block.style.overlaid(with: style) }
                diagram.blocks[id] = block
            }
        }
    }

    mutating func restOfLine() -> String {
        var text = scanner.read { $0 != "\n" }.trimmingWhitespace()
        while text.hasSuffix(";") { text.removeLast() }
        return text.trimmingWhitespace()
    }

    func splitFirstWord(_ text: String) -> (String, String) {
        // `class a, b name` allows spaces after the commas.
        var head = "", rest = Substring(text)
        while let c = rest.first, !c.isWhitespace || head.hasSuffix(",") {
            if !c.isWhitespace { head.append(c) }
            rest = rest.dropFirst()
        }
        return (head, rest.trimmingWhitespace())
    }

    static func list(_ ids: String) -> [String] {
        ids.split(separator: ",").map { $0.trimmingWhitespace() }.filter { !$0.isEmpty }
    }
}
