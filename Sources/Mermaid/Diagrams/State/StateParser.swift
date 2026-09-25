/// Parses state diagram source into a `StateDiagram`.
///
/// Parsing runs in two passes, like mermaid.js: this parser turns lines into
/// a tree of statements (composite bodies nest), and `StateResolver` then
/// walks the tree to scope `[*]` pseudo-states, split concurrency regions
/// and assign states to their containers.
struct StateParser {
    private let lines: [SourceLine]
    private var lineIndex = 0

    /// An open document: the root, or the body of a composite state.
    private struct Frame {
        var declaration: StateDeclaration?
        var statements: [StateStatement] = []
    }
    private var stack = [Frame(declaration: nil)]

    /// What one statement piece produced.
    enum Parsed {
        case statement(StateStatement)
        /// `state X {`: a composite body follows.
        case open(StateDeclaration)
        /// `note left of X` without text: the text follows until `end note`.
        case noteBody(target: StateReference, position: StateDiagram.Note.Position, location: SourceLocation)
    }

    static func parse(_ source: DiagramSource) throws -> StateDiagram {
        let keyword = Mermaid.headerKeyword(source.header.text)
        let arguments = source.headerArguments
        guard arguments.isEmpty || arguments.hasPrefix("%%") || arguments == ";" else {
            throw MermaidError.syntax("Unexpected '\(arguments)' after '\(keyword)'", at: source.header.location)
        }
        var parser = StateParser(lines: source.lines)
        let document = try parser.document()
        var diagram = try StateResolver.resolve(document)
        diagram.version = keyword.lowercased() == "statediagram" ? 1 : 2
        diagram.accessibility = source.accessibility
        return diagram
    }

    private init(lines: [SourceLine]) {
        self.lines = lines
    }

    /// Parses every line into the root document.
    mutating func document() throws -> [StateStatement] {
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            lineIndex += 1
            // `#` starts a comment where a statement could begin.
            if line.text.hasPrefix("#") { continue }
            for piece in StatementSplitter.pieces(of: line) {
                try handle(piece)
            }
        }
        if stack.count > 1, let open = stack.last?.declaration {
            throw MermaidError.syntax("Composite state '\(open.reference.id)' is missing its closing '}'",
                                      at: open.reference.location)
        }
        return stack[0].statements
    }

    private mutating func handle(_ piece: StatementPiece) throws {
        switch piece.text {
        case "{":
            // `state X` followed by `{` on the next line opens X's body.
            guard case .state(let declaration)? = stack[stack.count - 1].statements.last,
                  declaration.usesKeyword, declaration.kind == .state else {
                throw MermaidError.syntax("Unexpected '{'", at: piece.location)
            }
            stack[stack.count - 1].statements.removeLast()
            stack.append(Frame(declaration: declaration))
        case "}":
            guard stack.count > 1, let frame = stack.popLast(), let declaration = frame.declaration else {
                throw MermaidError.syntax("'}' without a matching composite state", at: piece.location)
            }
            stack[stack.count - 1].statements.append(.composite(declaration, body: frame.statements))
        default:
            switch try Self.statement(piece, nested: stack.count > 1) {
            case .statement(let statement):
                stack[stack.count - 1].statements.append(statement)
            case .open(let declaration):
                stack.append(Frame(declaration: declaration))
            case .noteBody(let target, let position, let location):
                let text = try noteBody(from: location)
                stack[stack.count - 1].statements.append(.note(target: target, position: position, text: text, alias: nil))
            }
        }
    }

    /// Reads the lines of a multi-line note up to `end note`.
    private mutating func noteBody(from location: SourceLocation) throws -> String {
        var text: [String] = []
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            lineIndex += 1
            let words = line.text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" })
            if words == ["end", "note"] { return text.joined(separator: "\n") }
            text.append(line.text)
        }
        throw MermaidError.syntax("Note is missing its closing 'end note'", at: location)
    }
}
