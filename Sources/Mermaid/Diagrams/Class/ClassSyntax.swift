/// Token-level scanning shared by the class diagram statements: class
/// names, quoted strings, annotations, and relation operators.
enum ClassSyntax {
    /// A class reference: its name plus the generic parameter of `Name~T~`.
    struct ClassName: Hashable {
        var id: String
        var generic: String?
    }

    /// A relation operator such as `<|--`, `..>`, `*--o` or `()--`.
    struct RelationOperator: Hashable {
        var left: ClassDiagram.RelationEnd
        var line: ClassDiagram.LineStyle
        var right: ClassDiagram.RelationEnd
    }

    /// Whether `c` may appear in an unquoted class name. mermaid.js allows
    /// letters (including Unicode), digits, `_`, `-` and `.`; the scanner
    /// stops at `--` and `..`, which start relation operators.
    static func isNameCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-" || c == "."
    }

    /// Scans a class name: backtick-quoted text or name characters,
    /// optionally followed by a `~generic~` parameter.
    static func className(_ scanner: inout Scanner) throws -> ClassName? {
        let start = scanner.location
        var id: String
        if scanner.consume("`") {
            guard let quoted = scanner.read(until: "`") else {
                throw MermaidError.syntax("Unterminated '`' in class name", at: start)
            }
            scanner.advance()
            id = quoted
        } else {
            id = ""
            while let c = scanner.peek(), isNameCharacter(c) {
                if (c == "-" || c == "."), scanner.peek(1) == c { break }
                id.append(c)
                scanner.advance()
            }
            guard !id.isEmpty else { return nil }
        }
        var generic: String?
        if scanner.peek() == "~" {
            let tilde = scanner.location
            scanner.advance()
            guard let type = scanner.read(until: "~") else {
                throw MermaidError.syntax("Unterminated '~' in generic class name", at: tilde)
            }
            scanner.advance()
            generic = type
        }
        return ClassName(id: id, generic: generic)
    }

    /// Scans a class name, throwing a located error when there is none.
    static func requireClassName(_ scanner: inout Scanner, _ what: String = "a class name") throws -> ClassName {
        let location = scanner.location
        guard let name = try className(&scanner) else {
            let found = scanner.peek().map { "'\($0)'" } ?? "end of line"
            throw MermaidError.syntax("Expected \(what) but found \(found)", at: location)
        }
        return name
    }

    /// Scans a `"double quoted"` string (no escapes, as in mermaid.js).
    static func string(_ scanner: inout Scanner) throws -> String? {
        let start = scanner.location
        guard scanner.consume("\"") else { return nil }
        guard let text = scanner.read(until: "\"") else {
            throw MermaidError.syntax("Unterminated string", at: start)
        }
        scanner.advance()
        return text
    }

    static func requireString(_ scanner: inout Scanner, _ what: String) throws -> String {
        let location = scanner.location
        guard let text = try string(&scanner) else {
            throw MermaidError.syntax("Expected \(what) in double quotes", at: location)
        }
        return text
    }

    /// Scans `<<name>>`, returning the trimmed name.
    static func annotation(_ scanner: inout Scanner) throws -> String? {
        let start = scanner.location
        guard scanner.consume("<<") else { return nil }
        guard let text = scanner.read(until: ">>") else {
            throw MermaidError.syntax("Unterminated '<<' annotation", at: start)
        }
        scanner.advance(by: 2)
        let name = text.trimmingWhitespace()
        guard !name.isEmpty else { throw MermaidError.syntax("Empty annotation", at: start) }
        return name
    }

    /// Scans a relation operator: an optional end type, `--` or `..`, and
    /// an optional end type. Leaves the scanner untouched when none is next.
    static func relationOperator(_ scanner: inout Scanner) -> RelationOperator? {
        var probe = scanner
        let left = leftEnd(&probe)
        let line: ClassDiagram.LineStyle
        if probe.consume("--") {
            line = .solid
        } else if probe.consume("..") {
            line = .dashed
        } else {
            return nil
        }
        let right = rightEnd(&probe)
        scanner = probe
        return RelationOperator(left: left, line: line, right: right)
    }

    private static func leftEnd(_ scanner: inout Scanner) -> ClassDiagram.RelationEnd {
        if scanner.consume("<|") { return .inheritance }
        if scanner.consume("()") { return .lollipop }
        if scanner.consume("*") { return .composition }
        if scanner.consume("<") { return .association }
        // `o` is an end only when a line follows, so `order` stays a name.
        if scanner.peek() == "o", scanner.peek(1) == "-" || scanner.peek(1) == "." {
            scanner.advance()
            return .aggregation
        }
        return .none
    }

    private static func rightEnd(_ scanner: inout Scanner) -> ClassDiagram.RelationEnd {
        if scanner.consume("|>") { return .inheritance }
        if scanner.consume("()") { return .lollipop }
        if scanner.consume("*") { return .composition }
        if scanner.consume(">") { return .association }
        // `A --o B` aggregates; `A --orders` is not an operator end.
        if scanner.peek() == "o", !(scanner.peek(1).map(isNameCharacter) ?? false) {
            scanner.advance()
            return .aggregation
        }
        return .none
    }
}
