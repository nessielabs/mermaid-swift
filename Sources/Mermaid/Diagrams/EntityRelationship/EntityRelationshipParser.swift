/// Parses `erDiagram` source into an `EntityRelationshipDiagram`.
///
/// Statements are one per line: entity declarations with optional aliases,
/// classes, and attribute blocks (which may span lines), relationships,
/// `direction`, styling (`style`, `classDef`, `class`, `:::`), and
/// `subgraph ... end` groups.
struct EntityRelationshipParser {
    typealias Diagram = EntityRelationshipDiagram

    var scanner: Scanner
    var diagram = Diagram()
    var entityIndex: [String: Int] = [:]
    /// Entities given an alias or attributes, as opposed to ones created by
    /// a bare reference (which may turn out to name a subgraph).
    var definedEntities: Set<String> = []

    struct OpenSubgraph {
        var index: Int
        var location: SourceLocation
        var references: [String] = []
    }
    var openSubgraphs: [OpenSubgraph] = []
    /// Entities already placed in a completed subgraph.
    var claimed: Set<String> = []

    init(_ source: DiagramSource) throws {
        scanner = Scanner(source.text)
        diagram.accessibility = source.accessibility
        let args = source.headerArguments
        if !args.isEmpty {
            // Leniency: `erDiagram LR` sets the direction like `direction LR`.
            guard let direction = LayeredGraph.Direction(keyword: args) else {
                throw MermaidError.syntax("Unexpected '\(args)' after 'erDiagram'", at: source.header.location)
            }
            diagram.direction = direction
        }
    }

    static func parse(_ source: DiagramSource) throws -> EntityRelationshipDiagram {
        var parser = try EntityRelationshipParser(source)
        return try parser.run()
    }

    mutating func run() throws -> Diagram {
        while true {
            skipSeparators()
            if scanner.isAtEnd { break }
            try statement()
            scanner.skipWhitespace()
            while scanner.consume(";") { scanner.skipWhitespace() }
            if let c = scanner.peek(), c != "\n" {
                throw MermaidError.syntax("Unexpected '\(c)'", at: scanner.location)
            }
        }
        if let open = openSubgraphs.last {
            throw MermaidError.syntax("Subgraph '\(diagram.subgraphs[open.index].id)' is missing 'end'", at: open.location)
        }
        finalize()
        return diagram
    }

    mutating func skipSeparators() {
        while let c = scanner.peek(), c == " " || c == "\t" || c == "\r" || c == "\n" || c == ";" { scanner.advance() }
    }

    mutating func statement() throws {
        let location = scanner.location
        if let direction = directionStatement() {
            if let open = openSubgraphs.last {
                diagram.subgraphs[open.index].direction = direction
            } else {
                diagram.direction = direction
            }
        } else if scanner.consumeKeyword("classDef", caseInsensitive: false) {
            let (names, css) = splitFirstWord(restOfLine())
            guard !names.isEmpty else { throw MermaidError.syntax("classDef needs a class name", at: location) }
            for name in list(names) {
                diagram.classDefinitions[name] = (diagram.classDefinitions[name] ?? ElementStyle())
                    .overlaid(with: ElementStyle(css: css))
            }
        } else if scanner.consumeKeyword("class", caseInsensitive: false) {
            let (ids, classes) = splitFirstWord(restOfLine())
            guard !ids.isEmpty, !classes.isEmpty else {
                throw MermaidError.syntax("class needs entity names and class names", at: location)
            }
            for id in list(ids) { applyClasses(list(classes), to: id) }
        } else if scanner.consumeKeyword("style", caseInsensitive: false) {
            let (ids, css) = splitFirstWord(restOfLine())
            guard !ids.isEmpty else { throw MermaidError.syntax("style needs an entity name", at: location) }
            for id in list(ids) { applyStyle(ElementStyle(css: css), to: id) }
        } else if scanner.consumeKeyword("subgraph", caseInsensitive: false) {
            try openSubgraph(at: location)
        } else if !openSubgraphs.isEmpty, scanner.consumeKeyword("end", caseInsensitive: false) {
            closeSubgraph()
        } else {
            try entityStatement()
        }
    }

    /// `direction TB|BT|LR|RL`. An entity that happens to be named
    /// `direction` is still an entity.
    mutating func directionStatement() -> LayeredGraph.Direction? {
        var probe = scanner
        guard probe.consumeKeyword("direction") else { return nil }
        probe.skipWhitespace()
        let word = probe.read { !$0.isWhitespace && $0 != ";" }
        guard let direction = LayeredGraph.Direction(keyword: word), word.count == 2 else { return nil }
        scanner = probe
        return direction
    }

    /// The rest of the line, trimmed, without a trailing `;`.
    mutating func restOfLine() -> String {
        var text = scanner.read { $0 != "\n" }.trimmingWhitespace()
        while text.hasSuffix(";") { text.removeLast() }
        return text.trimmingWhitespace()
    }

    func splitFirstWord(_ text: String) -> (String, String) {
        let word = String(text.prefix { !$0.isWhitespace })
        return (word, String(text.dropFirst(word.count)).trimmingWhitespace())
    }

    func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingWhitespace().unquoted }.filter { !$0.isEmpty }
    }
}
