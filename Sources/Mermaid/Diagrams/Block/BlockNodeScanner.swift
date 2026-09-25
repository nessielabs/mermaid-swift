/// A block reference as written in a block diagram statement.
struct BlockNodeToken: Equatable {
    var id: String
    var label: String?
    var kind: BlockDiagram.Kind?
    var span: Int?
}

/// Scans one block: an id, an optional shape with its label
/// (`a["label"]`, `b(("circle"))`, `c<["x"]>(right)`, ...) and an optional
/// column span (`:3`).
enum BlockNodeScanner {
    /// Openers, longest first, with the closers that may end them and the
    /// shape each pair makes, as in mermaid.js's `typeStr2Type`.
    static let delimiters: [(open: String, closers: [(String, NodeShape)])] = [
        ("(((", [(")))", .doubleCircle)]),
        ("((", [("))", .circle)]),
        ("([", [("])", .stadium)]),
        ("[[", [("]]", .subroutine)]),
        ("[(", [(")]", .cylinder)]),
        ("[/", [("/]", .leanRight), ("\\]", .trapezoid)]),
        ("[\\", [("\\]", .leanLeft), ("/]", .invertedTrapezoid)]),
        ("{{", [("}}", .hexagon)]),
        ("(", [(")", .rounded)]),
        ("[", [("]", .rect)]),
        ("{", [("}", .diamond)]),
        (">", [("]", .asymmetric)]),
    ]

    /// Every closer, longest first.
    static let anyCloser = [")))", "))", "])", "]]", ")]", "/]", "\\]", "}}", ")", "]", "}"]

    /// Characters that end an id: mermaid.js's NODE_ID excludes brackets,
    /// whitespace, `-`, `<`, `>`, `:` and `=`.
    static func isIDCharacter(_ c: Character) -> Bool {
        !c.isWhitespace && !"()[]{}-<>:=\"".contains(c)
    }

    static func scan(_ s: inout Scanner) throws -> BlockNodeToken? {
        let location = s.location
        let id = s.read(while: isIDCharacter)
        guard !id.isEmpty else { return nil }
        var token = BlockNodeToken(id: id)
        if s.hasPrefix("<[") {
            s.advance(by: 2)
            token.label = try readLabel(&s, closers: ["]>"], location: location).0
            token.kind = .arrow(try directions(&s, location: location))
        } else if let delimiter = delimiters.first(where: { s.hasPrefix($0.open) }) {
            s.advance(by: delimiter.open.count)
            // Any closer ends the label; a pair mermaid.js does not know
            // (such as `[/"x"]`) is its plain `na` block, drawn as a rectangle.
            let (label, closer) = try readLabel(&s, closers: delimiter.closers.map(\.0) + Self.anyCloser, location: location)
            token.label = label
            token.kind = .node(delimiter.closers.first { $0.0 == closer }?.1 ?? .rect)
        }
        if s.peek() == ":", let next = s.peek(1), next.isNumber {
            s.advance()
            token.span = s.readInteger()
        }
        return token
    }

    /// Reads a quoted, markdown ("`...`") or bare label up to one of `closers`.
    private static func readLabel(_ s: inout Scanner, closers: [String],
                                  location: SourceLocation) throws -> (String, String) {
        var label: String
        if s.consume("\"`") {
            guard let body = s.read(until: "`\"") else {
                throw MermaidError.syntax("Markdown string is missing its closing `\"", at: location)
            }
            s.advance(by: 2)
            label = "`" + body + "`"
        } else if s.peek() == "\"" {
            label = try s.readQuoted(multiline: true) ?? ""
        } else {
            // Leniency beyond mermaid.js, which requires quotes: a bare label.
            label = ""
            while let c = s.peek(), c != "\n", !closers.contains(where: { s.hasPrefix($0) }) {
                label.append(c)
                s.advance()
            }
            label = label.trimmingWhitespace()
        }
        guard let closer = closers.first(where: { s.hasPrefix($0) }) else {
            let expected = closers.map { "'\($0)'" }.joined(separator: " or ")
            throw MermaidError.syntax("Block label is missing its closing \(expected)", at: location)
        }
        s.advance(by: closer.count)
        return (label, closer)
    }

    /// `(right)`, `(x, down)`: one or more directions after a block arrow.
    private static func directions(_ s: inout Scanner, location: SourceLocation) throws -> [BlockDiagram.ArrowDirection] {
        s.skipWhitespace()
        guard s.consume("(") else {
            throw MermaidError.syntax("Block arrow needs directions such as '(right)'", at: s.location)
        }
        var result: [BlockDiagram.ArrowDirection] = []
        while true {
            s.skipWhitespace()
            let wordLocation = s.location
            let word = s.read { $0.isLetter }
            guard let direction = BlockDiagram.ArrowDirection(rawValue: word.lowercased()) else {
                throw MermaidError.syntax("Unknown block arrow direction '\(word)'; use right, left, up, down, x or y",
                                          at: wordLocation)
            }
            result.append(direction)
            s.skipWhitespace()
            if s.consume(",") { continue }
            guard s.consume(")") else { throw MermaidError.syntax("Block arrow directions are missing ')'", at: s.location) }
            return result
        }
    }
}
