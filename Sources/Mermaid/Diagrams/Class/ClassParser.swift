/// Parses class diagram source into a `ClassDiagram`.
///
/// The grammar is line-oriented, as in mermaid.js: every statement ends at
/// a newline, and only class bodies (`class A { ... }`) and namespace
/// blocks span lines.
struct ClassParser {
    var diagram = ClassDiagram()
    var classIndex: [String: Int] = [:]

    struct OpenBlock {
        var id: String
        var location: SourceLocation
    }
    /// Namespaces whose `}` has not been seen, innermost last.
    var namespaceStack: [OpenBlock] = []
    /// The class whose `{ ... }` body is being read.
    var openBody: OpenBlock?
    /// `style`, `cssClass` and interaction statements, applied after every
    /// class exists so they may appear before the class they name.
    var deferred: [(id: String, edit: (inout ClassDiagram.Class) -> Void)] = []

    static func parse(_ source: DiagramSource) throws -> ClassDiagram {
        var parser = ClassParser()
        parser.diagram.accessibility = source.accessibility
        for line in source.lines { try parser.line(line.text, at: line.location) }
        return try parser.finish()
    }

    mutating func finish() throws -> ClassDiagram {
        if let body = openBody {
            throw MermaidError.syntax("Class '\(body.id)' is missing its closing '}'", at: body.location)
        }
        if let open = namespaceStack.last {
            throw MermaidError.syntax("Namespace '\(open.id)' is missing its closing '}'", at: open.location)
        }
        for (id, edit) in deferred {
            if let i = classIndex[id] { edit(&diagram.classes[i]) }
        }
        return diagram
    }

    // MARK: - Lines

    mutating func line(_ raw: String, at location: SourceLocation) throws {
        let text = Self.removingComment(raw)
        guard !text.isEmpty else { return }
        if let body = openBody {
            try bodyLine(text, at: location, of: body)
            return
        }
        var statementText = text
        while statementText.hasSuffix(";") { statementText.removeLast() }
        var scanner = Scanner(statementText.trimmingWhitespace(), at: location)
        try statement(&scanner)
    }

    /// Cuts a trailing `%%` comment that is not inside a string.
    static func removingComment(_ text: String) -> String {
        var inString = false
        var previous: Character?
        for index in text.indices {
            let c = text[index]
            if c == "\"" { inString.toggle() }
            if c == "%", previous == "%", !inString {
                return String(text[..<text.index(before: index)]).trimmingWhitespace()
            }
            previous = c
        }
        return text.trimmingWhitespace()
    }

    /// A line inside `class A { ... }`: one member, or the closing `}`
    /// possibly preceded by a member and followed by another statement.
    mutating func bodyLine(_ text: String, at location: SourceLocation, of body: OpenBlock) throws {
        if let brace = text.firstIndex(of: "{") {
            throw MermaidError.syntax("Unexpected '{' inside the body of class '\(body.id)'",
                                      at: Self.location(location, advancedBy: text.distance(from: text.startIndex, to: brace)))
        }
        guard let close = text.firstIndex(of: "}") else {
            addMember(text, to: body.id)
            return
        }
        addMember(String(text[..<close]), to: body.id)
        openBody = nil
        let restStart = text.index(after: close)
        let rest = String(text[restStart...])
        if !rest.trimmingWhitespace().isEmpty {
            try line(rest, at: Self.location(location, advancedBy: text.distance(from: text.startIndex, to: restStart)))
        }
    }

    static func location(_ base: SourceLocation, advancedBy columns: Int) -> SourceLocation {
        SourceLocation(line: base.line, column: base.column + columns)
    }

    /// Consumes the rest of the scanner's line and parses it as a new
    /// statement (or body line), as after `{` and `}` on one line.
    mutating func continueLine(_ scanner: inout Scanner) throws {
        scanner.skipWhitespace()
        let location = scanner.location
        let rest = scanner.read { $0 != "\n" }
        if !rest.isEmpty { try line(rest, at: location) }
    }

    /// Requires that nothing but whitespace is left in the statement.
    func expectEnd(_ scanner: inout Scanner) throws {
        scanner.skipWhitespace()
        if let c = scanner.peek() {
            throw MermaidError.syntax("Unexpected '\(c)'", at: scanner.location)
        }
    }

    // MARK: - Classes and members

    @discardableResult
    mutating func ensureClass(_ name: ClassSyntax.ClassName) -> Int {
        if let i = classIndex[name.id] { return i }
        var newClass = ClassDiagram.Class(id: name.id)
        newClass.genericType = name.generic
        diagram.classes.append(newClass)
        classIndex[name.id] = diagram.classes.count - 1
        return diagram.classes.count - 1
    }

    /// Adds member text to a class: `<<name>>` is an annotation, text with
    /// a `)` is a method, and anything else is an attribute.
    mutating func addMember(_ raw: String, to id: String) {
        let text = raw.trimmingWhitespace()
        guard !text.isEmpty, let i = classIndex[id] else { return }
        if text.hasPrefix("<<"), text.hasSuffix(">>"), text.count >= 4 {
            diagram.classes[i].annotations.append(String(text.dropFirst(2).dropLast(2)).trimmingWhitespace())
            return
        }
        let member = ClassMember(parsing: text)
        if member.kind == .method {
            diagram.classes[i].methods.append(member)
        } else {
            diagram.classes[i].attributes.append(member)
        }
    }
}
