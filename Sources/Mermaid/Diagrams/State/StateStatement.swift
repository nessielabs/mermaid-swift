/// A state as written in a statement: an id or `[*]`, with any `:::class`
/// shorthands.
struct StateReference: Equatable {
    var id: String
    var classes: [String] = []
    var location: SourceLocation

    /// `[*]`, the start or end pseudo-state of the enclosing scope.
    var isTerminal: Bool { id == "[*]" }
}

/// A `state` statement or a bare state reference.
struct StateDeclaration: Equatable {
    var reference: StateReference
    var kind: StateDiagram.Kind = .state
    var descriptions: [String] = []
    /// Whether the statement used the `state` keyword, which lets a `{` on
    /// the following line open its body.
    var usesKeyword = false
}

/// One statement of a state diagram document, before scopes are resolved.
/// Composite states hold their body as a nested document, as in mermaid.js.
indirect enum StateStatement: Equatable {
    case state(StateDeclaration)
    case relation(from: StateReference, to: StateReference, label: String?)
    case composite(StateDeclaration, body: [StateStatement])
    /// `--`, separating concurrency regions.
    case divider(SourceLocation)
    case note(target: StateReference?, position: StateDiagram.Note.Position, text: String, alias: String?)
    case direction(LayeredGraph.Direction)
    case classDef(names: [String], style: ElementStyle)
    case applyClass(ids: [String], classes: [String], location: SourceLocation)
    case style(ids: [String], style: ElementStyle, location: SourceLocation)
    case click(id: String, url: String?, tooltip: String?, location: SourceLocation)
    case hideEmptyDescription
    case scale(Double)
}

/// A fragment of a source line holding one statement or brace.
struct StatementPiece: Equatable {
    var text: String
    var location: SourceLocation
}

enum StatementSplitter {
    /// Splits a trimmed source line into statements.
    ///
    /// Beyond newlines, mermaid.js' lexer lets braces sit on the same line
    /// as statements (`state A { a --> b }`), so a `{` ending a `state`
    /// statement and a `}` at either end of a piece become pieces of their
    /// own. Braces inside descriptions and labels (after a `:`) stay text.
    /// `%%` starts a comment anywhere, and `;` separates statements.
    static func pieces(of line: SourceLine) -> [StatementPiece] {
        let text = stripComment(line.text)
        var result: [StatementPiece] = []
        for (chunk, offset) in split(text, on: ";") {
            var rest = Substring(chunk)
            var column = offset
            while true {
                let leading = rest.prefix { $0 == " " || $0 == "\t" }.count
                rest = rest.dropFirst(leading)
                column += leading
                guard !rest.isEmpty else { break }
                let location = line.location(atOffset: column)
                if rest.first == "}" {
                    result.append(StatementPiece(text: "}", location: location))
                    rest = rest.dropFirst()
                    column += 1
                    continue
                }
                let end = pieceEnd(rest)
                let piece = String(rest[..<end]).trimmingWhitespace()
                if !piece.isEmpty { result.append(StatementPiece(text: piece, location: location)) }
                column += rest.distance(from: rest.startIndex, to: end)
                rest = rest[end...]
            }
        }
        return result
    }

    /// Where the statement at the start of `text` ends: just after the `{`
    /// of a `state` header, or at a `}` outside descriptions and quotes.
    private static func pieceEnd(_ text: Substring) -> Substring.Index {
        let isState = text.lowercased().hasPrefix("state ") || text.lowercased().hasPrefix("state\t")
        var inQuote = false
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if c == "\"" {
                inQuote.toggle()
            } else if !inQuote {
                if c == "{", isState || index == text.startIndex { return text.index(after: index) }
                if c == "}" { return index }
                if c == ":", !isState, !text[index...].hasPrefix(":::") { return text.endIndex }
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    /// Removes a `%%` comment (but not a `%%{` directive) outside quotes.
    static func stripComment(_ text: String) -> String {
        var inQuote = false
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if c == "\"" { inQuote.toggle() }
            if !inQuote, text[index...].hasPrefix("%%"), !text[index...].hasPrefix("%%{") {
                return String(text[..<index]).trimmingWhitespace()
            }
            index = text.index(after: index)
        }
        return text
    }

    /// Splits on `separator` outside double quotes, returning each part
    /// with its character offset in `text`.
    static func split(_ text: String, on separator: Character) -> [(String, Int)] {
        var parts: [(String, Int)] = []
        var current = ""
        var start = 0
        var inQuote = false
        for (offset, c) in text.enumerated() {
            if c == "\"" { inQuote.toggle() }
            if c == separator, !inQuote {
                parts.append((current, start))
                current = ""
                start = offset + 1
            } else {
                current.append(c)
            }
        }
        parts.append((current, start))
        return parts
    }
}
