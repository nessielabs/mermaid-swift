/// A node reference as written in a flowchart statement.
struct FlowchartNodeToken: Equatable {
    var id: String
    var label: String?
    var shape: NodeShape?
    var classes: [String] = []
    /// Keys from `@{ ... }` metadata, when present.
    var hasMetadata = false
}

/// Scans one node reference: an id followed by an optional bracketed shape
/// and label (`A[Text]`, `B((Circle))`, `C[/Lean/]`, ...), optional
/// `@{ shape: ..., label: ... }` metadata, and `:::class` shorthands.
enum FlowchartNodeScanner {
    /// Opening delimiters, longest first, with their closers and shapes.
    static let delimiters: [(open: String, closers: [(String, NodeShape)])] = [
        ("(((", [(")))", .doubleCircle)]),
        ("((", [("))", .circle)]),
        ("([", [("])", .stadium)]),
        ("[[", [("]]", .subroutine)]),
        ("[(", [(")]", .cylinder)]),
        ("{{", [("}}", .hexagon)]),
        ("[/", [("/]", .leanRight), ("\\]", .trapezoid)]),
        ("[\\", [("\\]", .leanLeft), ("/]", .invertedTrapezoid)]),
        ("(", [(")", .rounded)]),
        ("[", [("]", .rect)]),
        ("{", [("}", .diamond)]),
        (">", [("]", .asymmetric)]),
    ]

    static func scan(_ s: inout Scanner) throws -> FlowchartNodeToken? {
        let location = s.location
        let id = readID(&s)
        guard !id.isEmpty else { return nil }
        var token = FlowchartNodeToken(id: id)
        if s.hasPrefix("@{") {
            s.advance()
            try readMetadata(&s, into: &token, location: location)
        } else if let delimiter = delimiters.first(where: { s.hasPrefix($0.open) }) {
            s.advance(by: delimiter.open.count)
            let (label, shape) = try readLabel(&s, closers: delimiter.closers, location: location)
            token.label = label
            token.shape = shape
        }
        while s.consume(":::") {
            let name = s.read { $0.isWordCharacter || $0 == "-" }
            if !name.isEmpty { token.classes.append(name) }
        }
        return token
    }

    /// Letters, digits, and underscores, plus hyphens between word
    /// characters (so `node-1` is one id but `A-->B` stops at `A`).
    static func readID(_ s: inout Scanner) -> String {
        var id = ""
        while let c = s.peek() {
            if c.isWordCharacter {
                id.append(c)
                s.advance()
            } else if c == "-", !id.isEmpty, let next = s.peek(1), next.isWordCharacter {
                id.append(c)
                s.advance()
            } else {
                break
            }
        }
        return id
    }

    private static func readLabel(_ s: inout Scanner, closers: [(String, NodeShape)],
                                  location: SourceLocation) throws -> (String, NodeShape) {
        var probe = s
        probe.skipWhitespace()
        if probe.peek() == "\"" {
            probe.advance()
            if let quoted = probe.read(until: "\"") {
                probe.advance()
                probe.skipWhitespace()
                if let closer = closers.first(where: { probe.hasPrefix($0.0) }) {
                    probe.advance(by: closer.0.count)
                    s = probe
                    return (quoted, closer.1)
                }
            }
        }
        var text = ""
        while let c = s.peek() {
            if let closer = closers.first(where: { s.hasPrefix($0.0) }) {
                s.advance(by: closer.0.count)
                return (text.trimmingWhitespace(), closer.1)
            }
            if c == "\n" { break }
            text.append(c)
            s.advance()
        }
        let expected = closers.map { "'\($0.0)'" }.joined(separator: " or ")
        throw MermaidError.syntax("Node label is missing its closing \(expected)", at: location)
    }

    private static func readMetadata(_ s: inout Scanner, into token: inout FlowchartNodeToken,
                                     location: SourceLocation) throws {
        var depth = 0
        var text = ""
        var quote: Character?
        while let c = s.advance() {
            text.append(c)
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { break }
            }
        }
        guard depth == 0 else { throw MermaidError.syntax("Node metadata is missing its closing '}'", at: location) }
        let value = try LenientJSON.parse(text, at: location)
        token.hasMetadata = true
        if let name = value["shape"]?.stringValue {
            guard let shape = NodeShape(name: name) else {
                throw MermaidError.syntax("Unknown shape '\(name)'", at: location)
            }
            token.shape = shape
        }
        if let label = value["label"]?.stringValue { token.label = label }
    }
}
